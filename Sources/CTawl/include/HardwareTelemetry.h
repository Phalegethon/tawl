#ifndef TAWL_HARDWARE_TELEMETRY_H
#define TAWL_HARDWARE_TELEMETRY_H
#include <stdint.h>

enum { NB_HARDWARE_CPU_VALID = 1, NB_HARDWARE_GPU_VALID = 2 };
enum { NB_CPU_KIND_UNKNOWN = 0, NB_CPU_KIND_EFFICIENCY = 1, NB_CPU_KIND_PERFORMANCE = 2 };
enum { NB_GPU_DEVICE_VALID = 1, NB_GPU_RENDERER_VALID = 2, NB_GPU_TILER_VALID = 4 };
enum { NB_MAX_CPU_COUNT = 1024, NB_MAX_CPU_ID = 4095, NB_MAX_GPU_COUNT = 16 };

typedef struct {
    int32_t id, kind;
    uint32_t user, system, nice, idle;
} nb_cpu_core;

typedef struct {
    uint64_t registry_id;
    char name[256];
    int32_t core_count;
    uint32_t valid;
    double utilization_percent, renderer_percent, tiler_percent;
} nb_gpu;

typedef struct {
    uint32_t valid, cpu_count, gpu_count;
    nb_cpu_core *cpus;
    nb_gpu *gpus;
} nb_hardware_reading;

/* Read-only collection; caller owns the result until nb_free_hardware. */
nb_hardware_reading *nb_collect_hardware(void);
void nb_free_hardware(nb_hardware_reading *reading);
#endif
