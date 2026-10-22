#include "CTawl.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/IOBlockStorageDriver.h>
#include <IOKit/storage/IOStorageProtocolCharacteristics.h>
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/if_types.h>
#include <net/route.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>

static int read_sysctl(const char *name, void *value, size_t length) {
    size_t actual = length;
    return sysctlbyname(name, value, &actual, NULL, 0) == 0 && actual == length;
}

static void collect_host(nb_reading *out) {
    mach_port_t host = mach_host_self();
    host_cpu_load_info_data_t cpu = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        for (int index = 0; index < CPU_STATE_MAX; ++index) {
            out->cpu_total += cpu.cpu_ticks[index];
            if (index != CPU_STATE_IDLE) out->cpu_busy += cpu.cpu_ticks[index];
        }
        out->valid |= NB_CPU_VALID;
    }
    if (read_sysctl("hw.memsize", &out->memory_total, sizeof(out->memory_total))) out->valid |= NB_MEMORY_VALID;
    read_sysctl("hw.logicalcpu", &out->logical_cpus, sizeof(out->logical_cpus));
    vm_statistics64_data_t vm = {0};
    count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size = 0;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS &&
        host_page_size(host, &page_size) == KERN_SUCCESS) {
        out->compressed_bytes = (uint64_t)vm.compressor_page_count * page_size;
        out->swap_in_bytes = vm.swapins * page_size;
        out->swap_out_bytes = vm.swapouts * page_size;
        out->valid |= NB_VM_VALID;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap = {0};
    if (read_sysctl("vm.swapusage", &swap, sizeof(swap))) {
        out->swap_used_bytes = swap.xsu_used;
        out->valid |= NB_SWAP_VALID;
    }
    /* XNU exports dispatch pressure values: normal=1, warning=2, critical=4. */
    if (read_sysctl("kern.memorystatus_vm_pressure_level", &out->pressure_level, sizeof(out->pressure_level))) {
        if (out->pressure_level == 1 || out->pressure_level == 2 || out->pressure_level == 4) out->valid |= NB_PRESSURE_VALID;
    }
}

static uint64_t mix_id(uint64_t value) {
    value ^= value >> 30; value *= UINT64_C(0xbf58476d1ce4e5b9);
    value ^= value >> 27; value *= UINT64_C(0x94d049bb133111eb);
    return value ^ (value >> 31);
}

static void collect_network(nb_reading *out) {
    int mib[] = { CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0 };
    size_t length = 0;
    if (sysctl(mib, 6, NULL, &length, NULL, 0) != 0 || length == 0) return;
    char *buffer = malloc(length);
    if (!buffer) return;
    if (sysctl(mib, 6, buffer, &length, NULL, 0) != 0) { free(buffer); return; }
    char *cursor = buffer, *end = buffer + length;
    int complete = 1;
    /* Address and multicast messages have shorter headers than interface messages. */
    struct route_prefix { uint16_t length; uint8_t version, type; };
    while ((size_t)(end - cursor) >= sizeof(struct route_prefix)) {
        struct route_prefix *header = (struct route_prefix *)cursor;
        if (header->length < sizeof(struct route_prefix) || header->length > (size_t)(end - cursor)) { complete = 0; break; }
        if (header->type == RTM_IFINFO2 && header->length >= sizeof(struct if_msghdr2)) {
            struct if_msghdr2 *info = (struct if_msghdr2 *)cursor;
            char name[IF_NAMESIZE] = {0};
            if (if_indextoname(info->ifm_index, name) &&
                name[0] == 'e' && name[1] == 'n' && name[2] >= '0' && name[2] <= '9' &&
                !(info->ifm_flags & IFF_LOOPBACK) && info->ifm_data.ifi_type == IFT_ETHER) {
                out->network_in_bytes += info->ifm_data.ifi_ibytes;
                out->network_out_bytes += info->ifm_data.ifi_obytes;
                out->network_signature ^= mix_id(info->ifm_index);
                ++out->network_interface_count;
            }
        }
        cursor += header->length;
    }
    if (complete && cursor == end && out->network_interface_count > 0) out->valid |= NB_NETWORK_VALID;
    free(buffer);
}

static int dictionary_counter(CFDictionaryRef dictionary, CFStringRef key, uint64_t *value) {
    CFTypeRef item = CFDictionaryGetValue(dictionary, key);
    int64_t signed_value = 0;
    if (!item || CFGetTypeID(item) != CFNumberGetTypeID() ||
        !CFNumberGetValue((CFNumberRef)item, kCFNumberSInt64Type, &signed_value) || signed_value < 0) return 0;
    *value = (uint64_t)signed_value;
    return 1;
}

static void collect_disk(nb_reading *out) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("IOBlockStorageDriver");
    if (!matching || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) return;
    io_registry_entry_t driver;
    int all_readable = 1;
    while ((driver = IOIteratorNext(iterator))) {
        /* Virtual disks also appear here; their backing device already accounts for I/O. */
        io_registry_entry_t provider = IO_OBJECT_NULL;
        int physical = -1;
        if (IORegistryEntryGetParentEntry(driver, kIOServicePlane, &provider) == KERN_SUCCESS) {
            CFTypeRef properties = IORegistryEntryCreateCFProperty(provider, CFSTR(kIOPropertyProtocolCharacteristicsKey), kCFAllocatorDefault, 0);
            if (properties && CFGetTypeID(properties) == CFDictionaryGetTypeID()) {
                CFTypeRef type = CFDictionaryGetValue((CFDictionaryRef)properties, CFSTR(kIOPropertyPhysicalInterconnectTypeKey));
                if (type && CFGetTypeID(type) == CFStringGetTypeID() && CFStringGetLength((CFStringRef)type) > 0) {
                    physical = CFEqual(type, CFSTR(kIOPropertyPhysicalInterconnectTypeVirtual)) ? 0 : 1;
                }
            }
            if (properties) CFRelease(properties);
            IOObjectRelease(provider);
        }
        if (physical <= 0) {
            if (physical == 0) ++out->disk_virtual_count;
            else { ++out->disk_unknown_count; all_readable = 0; }
            IOObjectRelease(driver);
            continue;
        }
        CFTypeRef stats = IORegistryEntryCreateCFProperty(driver, CFSTR(kIOBlockStorageDriverStatisticsKey), kCFAllocatorDefault, 0);
        uint64_t read_bytes = 0, write_bytes = 0, registry_id = 0;
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID() &&
            dictionary_counter((CFDictionaryRef)stats, CFSTR(kIOBlockStorageDriverStatisticsBytesReadKey), &read_bytes) &&
            dictionary_counter((CFDictionaryRef)stats, CFSTR(kIOBlockStorageDriverStatisticsBytesWrittenKey), &write_bytes) &&
            IORegistryEntryGetRegistryEntryID(driver, &registry_id) == KERN_SUCCESS) {
            out->disk_read_bytes += read_bytes;
            out->disk_write_bytes += write_bytes;
            out->disk_signature ^= mix_id(registry_id);
            ++out->disk_driver_count;
        } else { all_readable = 0; }
        if (stats) CFRelease(stats);
        IOObjectRelease(driver);
    }
    IOObjectRelease(iterator);
    if (all_readable && out->disk_driver_count > 0) out->valid |= NB_DISK_VALID;
}

static int is_denied(int error) { return error == EPERM || error == EACCES; }
static void identity_unavailable(nb_reading *out, int error) {
    ++out->unreadable_process_count;
    if (is_denied(error)) ++out->identity_denied_count;
    else if (error == ESRCH || error == ENOENT) ++out->identity_changed_count;
    else ++out->identity_other_error_count;
}

static void collect_process(nb_reading *out, pid_t pid, mach_timebase_info_data_t timebase) {
    struct proc_bsdinfo before = {0}, after = {0};
    errno = 0;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, sizeof(before)) != sizeof(before)) {
        identity_unavailable(out, errno); return;
    }
    nb_process process = {0};
    process.pid = pid;
    process.parent_pid = (int32_t)before.pbi_ppid;
    process.is_owned_by_current_user = getuid() != 0 && before.pbi_uid == getuid() && before.pbi_ruid == getuid();
    process.start_microseconds = before.pbi_start_tvsec * UINT64_C(1000000) + before.pbi_start_tvusec;
    strlcpy(process.name, before.pbi_name[0] ? before.pbi_name : before.pbi_comm, sizeof(process.name));
    struct rusage_info_v4 usage = {0};
    errno = 0;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) == 0) {
        /* proc_pid_rusage CPU times are Mach absolute ticks, including on arm64. */
        __uint128_t cpu_ticks = (__uint128_t)usage.ri_user_time + usage.ri_system_time;
        process.cpu_nanoseconds = (uint64_t)(cpu_ticks * timebase.numer / timebase.denom);
        process.footprint_bytes = usage.ri_phys_footprint;
        process.resident_bytes = usage.ri_resident_size;
        process.disk_read_bytes = usage.ri_diskio_bytesread;
        process.disk_write_bytes = usage.ri_diskio_byteswritten;
        process.valid |= NB_PROCESS_USAGE_VALID;
    } else { process.usage_error = errno; }
    errno = 0;
    if (proc_pidpath(pid, process.executable_path, sizeof(process.executable_path)) > 0) process.valid |= NB_PROCESS_PATH_VALID;
    else process.path_error = errno;
    struct proc_vnodepathinfo paths = {0};
    errno = 0;
    if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, sizeof(paths)) == sizeof(paths) && paths.pvi_cdir.vip_path[0]) {
        strlcpy(process.working_directory, paths.pvi_cdir.vip_path, sizeof(process.working_directory));
        process.valid |= NB_PROCESS_CWD_VALID;
    } else { process.cwd_error = errno; }
    /* Recheck identity after the non-atomic calls: PID reuse must not join two lifetimes. */
    errno = 0;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after)) {
        identity_unavailable(out, errno); return;
    }
    if (before.pbi_start_tvsec != after.pbi_start_tvsec || before.pbi_start_tvusec != after.pbi_start_tvusec) {
        identity_unavailable(out, ESRCH); return;
    }
    if (before.pbi_uid != after.pbi_uid || before.pbi_ruid != after.pbi_ruid) process.is_owned_by_current_user = 0;
    out->processes[out->process_count++] = process;
}

static void collect_processes(nb_reading *out, mach_timebase_info_data_t timebase) {
    int estimate = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (estimate <= 0) return;
    pid_t *pids = NULL;
    int bytes = 0, capacity = 0;
    for (int attempt = 0; attempt < 3; ++attempt) {
        capacity = estimate + 256 * (int)sizeof(pid_t);
        if (capacity > 4 * 1024 * 1024) { free(pids); return; }
        free(pids); pids = calloc(1, (size_t)capacity);
        if (!pids) return;
        bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, capacity);
        if (bytes <= 0) { free(pids); return; }
        if (bytes < capacity) break;
        estimate = capacity * 2;
    }
    if (bytes >= capacity) out->valid |= NB_PROCESS_LIST_TRUNCATED;
    size_t count = (size_t)bytes / sizeof(pid_t);
    out->processes = calloc(count, sizeof(nb_process));
    if (!out->processes) { free(pids); return; }
    out->valid |= NB_PROCESS_LIST_VALID;
    for (size_t index = 0; index < count; ++index) {
        if (pids[index] <= 0) continue; /* kernel_task/PID 0 has no userspace process lifetime. */
        ++out->listed_process_count;
        collect_process(out, pids[index], timebase);
    }
    free(pids);
}

nb_reading *nb_collect(void) {
    nb_reading *out = calloc(1, sizeof(nb_reading));
    if (!out) return NULL;
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    out->monotonic_seconds = (double)mach_continuous_time() * timebase.numer / timebase.denom / 1e9;
    collect_host(out);
    collect_network(out);
    collect_disk(out);
    collect_processes(out, timebase);
    return out;
}

void nb_free_reading(nb_reading *reading) {
    if (reading) { free(reading->processes); free(reading); }
}
