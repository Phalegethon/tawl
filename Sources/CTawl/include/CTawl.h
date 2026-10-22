#ifndef CTAWL_H
#define CTAWL_H
#include <stdint.h>
#include <stddef.h>
#include "TerminalSupport.h"
#include "ProcessControl.h"
#include "HardwareTelemetry.h"

enum {
    NB_CPU_VALID = 1 << 0, NB_MEMORY_VALID = 1 << 1,
    NB_VM_VALID = 1 << 2, NB_SWAP_VALID = 1 << 3,
    NB_PRESSURE_VALID = 1 << 4, NB_NETWORK_VALID = 1 << 5,
    NB_DISK_VALID = 1 << 6, NB_PROCESS_LIST_VALID = 1 << 7,
    NB_PROCESS_LIST_TRUNCATED = 1 << 8
};
enum { NB_PROCESS_USAGE_VALID = 1 << 0, NB_PROCESS_PATH_VALID = 1 << 1, NB_PROCESS_CWD_VALID = 1 << 2 };

typedef struct {
    int32_t pid, parent_pid;
    int32_t is_owned_by_current_user;
    uint64_t start_microseconds;
    uint32_t valid;
    int32_t usage_error, path_error, cwd_error;
    char name[64], executable_path[4096], working_directory[1024];
    uint64_t cpu_nanoseconds, footprint_bytes, resident_bytes;
    uint64_t disk_read_bytes, disk_write_bytes;
} nb_process;

typedef struct {
    uint32_t valid;
    double monotonic_seconds;
    uint64_t cpu_busy, cpu_total, memory_total;
    int32_t logical_cpus, pressure_level;
    uint64_t compressed_bytes, swap_used_bytes, swap_in_bytes, swap_out_bytes;
    uint64_t network_in_bytes, network_out_bytes, network_signature;
    uint32_t network_interface_count;
    uint64_t disk_read_bytes, disk_write_bytes, disk_signature;
    uint32_t disk_driver_count, disk_virtual_count, disk_unknown_count;
    uint32_t listed_process_count, process_count, unreadable_process_count;
    uint32_t identity_denied_count, identity_changed_count, identity_other_error_count;
    nb_process *processes;
} nb_reading;

/* Collection calls below are read-only; ownership of the returned allocation passes to caller. */
nb_reading *nb_collect(void);
void nb_free_reading(nb_reading *reading);
#endif
