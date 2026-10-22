#include "HardwareTelemetry.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static int read_number(CFTypeRef value, double *result) {
    return value && CFGetTypeID(value) == CFNumberGetTypeID() &&
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, result) && isfinite(*result);
}

static void core_kinds(nb_cpu_core *cores, uint32_t count) {
    io_registry_entry_t root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus");
    if (!root) return;
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) != KERN_SUCCESS) {
        IOObjectRelease(root); return;
    }
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        CFTypeRef id = IORegistryEntryCreateCFProperty(entry, CFSTR("logical-cpu-id"), kCFAllocatorDefault, 0);
        CFTypeRef type = IORegistryEntryCreateCFProperty(entry, CFSTR("cluster-type"), kCFAllocatorDefault, 0);
        double logical = -1;
        if (read_number(id, &logical) && logical >= 0 && logical <= NB_MAX_CPU_ID && floor(logical) == logical &&
            type && CFGetTypeID(type) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)type) >= 1) {
            UInt8 kind = CFDataGetBytePtr((CFDataRef)type)[0];
            for (uint32_t i = 0; i < count; ++i) if (cores[i].id == (int32_t)logical) {
                cores[i].kind = kind == 'E' ? NB_CPU_KIND_EFFICIENCY : kind == 'P' ? NB_CPU_KIND_PERFORMANCE : NB_CPU_KIND_UNKNOWN;
            }
        }
        if (id) CFRelease(id);
        if (type) CFRelease(type);
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator); IOObjectRelease(root);
}

static void collect_cpus(nb_hardware_reading *out) {
    mach_port_t host = mach_host_self();
    processor_info_array_t loads = NULL, basics = NULL;
    natural_t load_cpus = 0, basic_cpus = 0;
    mach_msg_type_number_t load_count = 0, basic_count = 0;
    kern_return_t load_result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &load_cpus, &loads, &load_count);
    kern_return_t basic_result = host_processor_info(host, PROCESSOR_BASIC_INFO, &basic_cpus, &basics, &basic_count);
    if (load_result != KERN_SUCCESS || basic_result != KERN_SUCCESS || !loads || !basics ||
        !load_cpus || load_cpus > NB_MAX_CPU_COUNT || load_cpus != basic_cpus ||
        load_count != load_cpus * PROCESSOR_CPU_LOAD_INFO_COUNT ||
        basic_count != basic_cpus * PROCESSOR_BASIC_INFO_COUNT) goto cleanup;
    out->cpus = calloc(load_cpus, sizeof(nb_cpu_core));
    if (!out->cpus) goto cleanup;
    for (uint32_t i = 0; i < load_cpus; ++i) {
        processor_basic_info_t basic = (processor_basic_info_t)(basics + i * PROCESSOR_BASIC_INFO_COUNT);
        if (basic->slot_num < 0 || basic->slot_num > NB_MAX_CPU_ID) goto invalid;
        for (uint32_t j = 0; j < i; ++j) if (out->cpus[j].id == basic->slot_num) goto invalid;
        processor_cpu_load_info_t load = (processor_cpu_load_info_t)(loads + i * PROCESSOR_CPU_LOAD_INFO_COUNT);
        nb_cpu_core *core = &out->cpus[i];
        core->id = basic->slot_num;
        core->user = load->cpu_ticks[CPU_STATE_USER];
        core->system = load->cpu_ticks[CPU_STATE_SYSTEM];
        core->nice = load->cpu_ticks[CPU_STATE_NICE];
        core->idle = load->cpu_ticks[CPU_STATE_IDLE];
    }
    out->cpu_count = load_cpus;
    core_kinds(out->cpus, out->cpu_count);
    out->valid |= NB_HARDWARE_CPU_VALID;
    goto cleanup;
invalid:
    free(out->cpus); out->cpus = NULL;
cleanup:
    if (loads) vm_deallocate(mach_task_self(), (vm_address_t)loads, (vm_size_t)load_count * sizeof(integer_t));
    if (basics) vm_deallocate(mach_task_self(), (vm_address_t)basics, (vm_size_t)basic_count * sizeof(integer_t));
    mach_port_deallocate(mach_task_self(), host);
}

static int percentage(CFDictionaryRef stats, CFStringRef key, double *result) {
    return read_number(CFDictionaryGetValue(stats, key), result) && *result >= 0 && *result <= 100;
}

static void gpu_name(io_registry_entry_t entry, char *name, size_t length) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(entry, CFSTR("model"), kCFAllocatorDefault, 0);
    CFStringRef string = NULL;
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) string = CFRetain(value);
    else if (value && CFGetTypeID(value) == CFDataGetTypeID()) {
        CFDataRef data = (CFDataRef)value;
        string = CFStringCreateWithBytes(kCFAllocatorDefault, CFDataGetBytePtr(data), CFDataGetLength(data), kCFStringEncodingUTF8, false);
    }
    if (!string || !CFStringGetCString(string, name, length, kCFStringEncodingUTF8) || !name[0]) strlcpy(name, "GPU", length);
    if (string) CFRelease(string);
    if (value) CFRelease(value);
}

static void collect_gpus(nb_hardware_reading *out) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("IOAccelerator");
    if (!matching || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) return;
    out->gpus = calloc(NB_MAX_GPU_COUNT, sizeof(nb_gpu));
    if (!out->gpus) { IOObjectRelease(iterator); return; }
    int complete = 1;
    io_registry_entry_t entry;
    while ((entry = IOIteratorNext(iterator))) {
        if (out->gpu_count >= NB_MAX_GPU_COUNT) { complete = 0; IOObjectRelease(entry); break; }
        nb_gpu *gpu = &out->gpus[out->gpu_count];
        if (IORegistryEntryGetRegistryEntryID(entry, &gpu->registry_id) != KERN_SUCCESS) {
            complete = 0; IOObjectRelease(entry); continue;
        }
        gpu_name(entry, gpu->name, sizeof(gpu->name));
        CFTypeRef cores = IORegistryEntryCreateCFProperty(entry, CFSTR("gpu-core-count"), kCFAllocatorDefault, 0);
        double core_count = 0;
        if (read_number(cores, &core_count) && core_count > 0 && core_count <= 65536 && floor(core_count) == core_count) gpu->core_count = (int32_t)core_count;
        if (cores) CFRelease(cores);
        CFTypeRef stats = IORegistryEntryCreateCFProperty(entry, CFSTR("PerformanceStatistics"), kCFAllocatorDefault, 0);
        if (stats && CFGetTypeID(stats) == CFDictionaryGetTypeID()) {
            if (percentage(stats, CFSTR("Device Utilization %"), &gpu->utilization_percent) ||
                percentage(stats, CFSTR("GPU Activity(%)"), &gpu->utilization_percent)) gpu->valid |= NB_GPU_DEVICE_VALID;
            if (percentage(stats, CFSTR("Renderer Utilization %"), &gpu->renderer_percent)) gpu->valid |= NB_GPU_RENDERER_VALID;
            if (percentage(stats, CFSTR("Tiler Utilization %"), &gpu->tiler_percent)) gpu->valid |= NB_GPU_TILER_VALID;
        }
        if (stats) CFRelease(stats);
        out->gpu_count++;
        IOObjectRelease(entry);
    }
    IOObjectRelease(iterator);
    if (complete) out->valid |= NB_HARDWARE_GPU_VALID;
}

nb_hardware_reading *nb_collect_hardware(void) {
    nb_hardware_reading *reading = calloc(1, sizeof(nb_hardware_reading));
    if (!reading) return NULL;
    collect_cpus(reading); collect_gpus(reading);
    return reading;
}

void nb_free_hardware(nb_hardware_reading *reading) {
    if (!reading) return;
    free(reading->cpus); free(reading->gpus); free(reading);
}
