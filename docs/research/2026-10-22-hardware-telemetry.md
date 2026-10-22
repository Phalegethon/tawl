# CPU / GPU telemetry research — 2026-10-22

Live, read-only observations on this machine (no sudo/install/workload):

- `sysctl`: Mac14,6; 12 physical/logical CPUs; perflevel0 Performance 8, perflevel1 Efficiency 4.
- IODeviceTree `/cpus`: `logical-cpu-id` CFNumber 0–3 have `cluster-type` CFData E; IDs 4–11 P. Thus do not infer core index ordering from perflevel0.
- IOAccelerator: model Apple M2 Max, gpu-core-count 38. PerformanceStatistics showed Device Utilization %=10, Renderer Utilization %=9, Tiler Utilization %=10. These were a momentary sample, not a benchmark.
- Observed PerformanceStatistics keys contain no per-GPU-core utilization array.

## Implementation recommendation

CPU: host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, ...); maintain raw uint32 user/system/nice/idle ticks per logical processor. At second valid sample, calculate per-state differences; busy=(user+system+nice)/total. The implemented conservative policy treats any decreasing uint32 counter (including wrap) as unknown for that interval, then establishes a fresh baseline, rather than guessing reset versus wrap. First, missing, invalid, topology-changed, or zero-delta samples are unknown, not measured zero. Validate array count against processor count * CPU_STATE_MAX. Free returned memory via vm_deallocate; deallocate host port. Optional PROCESSOR_BASIC_INFO slot_num gives explicit stable processor IDs rather than assuming order. Map those IDs to IODeviceTree logical-cpu-id. Missing/unrecognized cluster metadata keeps CPU utilization available with unknown kind. Newer hardware may have M type; do not blindly force all non-E into P. Current M2 E/P is directly observed.

GPU: enumerate IOServiceMatching("IOAccelerator"), use IORegistryEntryGetRegistryEntryID for per-device identity, read PerformanceStatistics CFDictionary with type/range validation. Device Utilization % is a directly reported 0–100 device metric, not a cumulative counter to differentiate. Optional GPU Activity(%) fallback is established in Stats; separate Renderer Utilization % and Tiler Utilization % are engine metrics, never individual GPU cores. Read model (CFString or CFData) and gpu-core-count only as metadata. Absent/wrong-type/nonfinite/out-of-range values are unavailable. Do not hold last value as a current reading on collector failure.

Suggested GPU wording: “Apple M2 Max · 38 çekirdek · Aygıt toplamı”; “Çekirdek bazında ölçüm sağlanmıyor”. Do not multiply device utilization by 38 and present it as measured active-core count, nor display 38 cloned meters.

IOKit property keys are driver interfaces, not a guaranteed public GPU utilization contract. Capability-based fallback is necessary. Public Metal counter sample APIs instrument own command passes and do not establish a passive universal per-core meter for another app. Show system-wide scope, not LLM-specific attribution. CPU busy-time is not normalized compute throughput between E/P; the panel establishes distribution and saturation, not guaranteed bottleneck cause.

## Primary sources checked

- Apple system capabilities (hw.nperflevels and perflevel counts): https://developer.apple.com/documentation/kernel/1387446-sysctlbyname/determining_system_capabilities
- Apple XNU host_processor_info implementation: https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/host.c
- Apple XNU accounting overview: https://github.com/apple-oss-distributions/xnu/blob/main/doc/observability/recount.md
- hwloc Darwin topology implementation uses logical-cpu-id and cluster-type: https://github.com/open-mpi/hwloc/blob/master/hwloc/topology-darwin.c
- Stats GPU collector directly reads PerformanceStatistics fields: https://github.com/exelban/stats/blob/master/Modules/GPU/reader.swift
- Stats CPU collector uses host_processor_info deltas: https://github.com/exelban/stats/blob/master/Modules/CPU/readers.swift
- Apple Metal counter sampling model: https://developer.apple.com/documentation/metal/gpu-counters-and-counter-sample-buffers
