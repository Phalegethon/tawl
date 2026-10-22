# Swap assessment: measurement and interpretation limits

October 22, 2026. This note explains why the application does not identify a definitive per-process “swap culprit” or estimate reclaimable GiB.

## Verified sources

- [Apple Activity Monitor — memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac): pressure considers free memory, swap rate, wired memory and file cache together. Swap Used is space on the startup disk; Compressed is separate. Per-application VM Compressed can be displayed, but is not the application's byte share of the swap file.
- [Apple Activity Monitor — RAM requirements](https://support.apple.com/guide/activity-monitor/check-if-your-mac-needs-more-ram-actmntr34865/mac): more free memory does not automatically improve performance; green pressure means efficient use. Zero swap is therefore not the product's objective.
- [Apple XNU `vm_statistics.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h): system `swapins`/`swapouts` count pages moved through compressor segments. TAWL converts counter deltas using page size and elapsed time. These are neither process attribution nor actual physical SSD write bytes.
- [Apple XNU `resource.h`](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h): the current `proc_pid_rusage` collector's structure exposes footprint, resident/wired, page-ins and disk I/O. It does not provide current per-process swap bytes; relabelling page-ins as swap would be wrong.
- [Apple XNU `task_info.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/task_info.h): `task_vm_info` includes compressed memory and footprint. That model also does not directly prove that a process caused system swap. This feature does not seek other processes' task ports or additional privileges.
- [Apple Virtual Memory System, archived](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/AboutMemory.html): page-ins can come from swap backing or files; page-outs can move inactive pages selected by the system. This 2013 source supports the mechanism distinguishing page ownership from pressure-causing allocation, not details of today's compressor implementation.

## Product inference and decision

An application's memory being swapped does not prove it initiated pressure. Another application's allocations may cause the system to choose the first application's pages. Large footprint also does not prove causality. This is a mechanism-based inference; the product makes no definitive process attribution.

Memory focus sorts existing applications by footprint; growth and verified low activity can be investigated separately. Under pressure or current swap writes, recommend saving unnecessary work/tabs, exiting normally, then comparing pressure and write rate. Footprint is not promised recovered RAM or reduced swap. The swap-assessment feature itself does not close applications, run purge/swapoff or restart the system; separately confirmed process closure has its own safety boundary.

`assessSwap` distinguishes writes, reads, no transfer and unknown in the latest interval. “No transfer” requires both rates to be known and zero. Up to 120 seconds of continuous amount change may be shown as observation. Missing data, time gaps and samples after a historical frame never extend that evidence. The rate of change is not used to forecast minutes until swap empties.

Assessment duration fields follow the same evidence rules: unknown is `nil`, eligible but new/interrupted observation is `0`, and verified duration is capped at 30 seconds for CPU and 600 for low activity. System/VM/database processes and unverified owners stay outside closure recommendations.
