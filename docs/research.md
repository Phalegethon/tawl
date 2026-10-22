# Making system load understandable: tools and use cases

Research date: October 22, 2026. This document records the research stage; later device validation of the local prototype is in the private development log. Scope: macOS-first personal-computer monitoring, prompted by the supplied htop screenshot, including developer applications, background jobs and Docker/VM load. OS version and processor model were not independently verified at this research stage. Features were researched in official documentation and repositories; no tool installation, live performance measurement or hands-on comparison was performed. Recommendations below were therefore a proposed evaluation order, not a measured performance ranking.

**Subsequent user decision: build from scratch, with a live terminal and report commands.** Installing/evaluating existing tools was removed from scope. The user wanted no installation. Market research remains a reference for features, design and technical limits. The new product starts with application/project ownership, understandable load explanations and evidence over time. The user selected a terminal interface; a separate design specifies the product scope.

## What the supplied screenshot showed

These observations concern the captured instant, not the computer's current state.

| Visible data | Plain-language interpretation | What it cannot establish alone |
|---|---|---|
| 12 CPU indicators at approximately 58–83% | Simple mean about 69.3%; substantial CPU activity | CPU caused the slowdown, or exactly 69% of compute throughput was used |
| Memory 26.3 / 32 GB | About 82% usage as reported by htop | Insufficient RAM; the image lacks macOS pressure/compression information |
| Swap 19.3 / 20 GB | Significant disk-backed swap usage | Heavy current swap traffic, a 96%-full disk, or a fixed “20 GB extra RAM” limit |
| Load average 18.07 / 12.98 / 11.61 | One-, five- and fifteen-minute averages; the short-term value is higher | “CPU 1807%” or a definitive bottleneck cause |
| VS Code Helper (Plugin): CPU 114.3% | About 1.14 cores' worth of CPU time | 114% of the whole computer, or the responsible extension's identity |
| Same row: VIRT 1910G, RES 226M | Virtual address space and resident memory are different quantities | VS Code consumed 1.9 TB of physical RAM |
| Claude, VS Code and virtualization processes | Several application families consume resources concurrently | Complete family totals from only the visible rows |
| Approximately nine days of uptime | A long-running system | All accumulated swap originated during the latest slowdown |

Multithreaded process CPU percentages can exceed 100. Different Apple Silicon core types and changing frequencies mean average busy time is not compute throughput. [Apple: process CPU usage](https://developer.apple.com/tutorials/instruments/identifying-a-hang), [Apple: load average](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/getloadavg.3.html).

For memory, macOS Memory Pressure is a more useful starting point than used GB alone; swap rate, free memory and other components contribute. Virtual address-space size does not directly represent physical consumption. The first investigation priority for this screenshot would be pressure/swap activity and the VS Code/Claude families over time. That is a research priority, not a diagnosis. [Apple: memory usage](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac), [Apple: allocation and footprint](https://developer.apple.com/documentation/xcode/analyzing-the-memory-usage-of-your-metal-app).

## Three distinct questions

First: what is the system doing now across CPU, memory, disk, network and GPU? Second: which application or task owns that consumption? Third: how does it relate to the delay the user experiences? Most monitors answer the first. The second needs process grouping and project context. The third needs duration, history, wait/pressure signals and, when possible, comparative measurement.

High usage is not necessarily a problem: a build may be doing useful work. Low total CPU is not proof of responsiveness: a single thread, lock, short spike or remote-service wait can still delay work. The USE approach separates utilization, saturation/wait and errors for each resource and provides a useful basis for interpretation. [Brendan Gregg: USE method](https://www.brendangregg.com/usemethod.html).

## Simplification before building

The initial short-term suggestion was to inspect Memory Pressure and leading consumers in Activity Monitor's Memory tab, and the few highest consumers in CPU. View → All Processes, Hierarchically reveals helper relationships but does not itself guarantee complete application totals. Hiding unnecessary columns and checking whether rapid refresh is useful improve readability. [Apple: process views and columns](https://support.apple.com/en-au/guide/activity-monitor/-actmntr1001/mac).

A menu bar could retain only CPU, memory pressure and disk/network when needed, with technical details one click deeper. That simplifies the immediate view; explaining past events and project ownership requires more capability. These existing-tool suggestions were superseded by the user's build-from-scratch decision.

## Existing tools

The limits column identifies the portion of this user's need still requiring work; it does not dismiss the tool.

| Tool | Model and platform at research time | Relevant strengths | Limits / evaluation |
|---|---|---|---|
| [Mac Performance Monitor](https://github.com/Zesty0wl/mac-performance-monitor) | Free, MIT; macOS 15+, Apple Silicon | System/process history together, application groups, event investigation | First open-source evaluation candidate; accuracy and overhead need measurement on current hardware |
| [Vitals](https://vitalsmac.com/features/apps-not-processes) | Commercial; macOS 15+, Intel and Apple Silicon | Application helper grouping; project, port and agent context | Close product approach, but new; grouping accuracy not tested hands-on |
| [Stats](https://github.com/exelban/stats) | Free, MIT; macOS 12+ | Customizable menu-bar resource summaries | Useful for glancing; causal interpretation remains the user's job |
| [iStat Menus](https://bjango.com/mac/istatmenus/) | Commercial; page listed macOS 13.5+ | History, top applications, pressure and duration-based notifications | Too many modules can restore clutter; 14-day trial |
| [iStatistica Pro](https://www.imagetasks.com/istatistica/pro/) | Commercial; macOS, Intel/Apple Silicon | Window dashboard, application CPU history | Some sensors/process details need an extra plugin; automatic root-cause analysis unverified |
| [btop](https://github.com/aristocratos/btop) | Open source, Apache-2.0; macOS/Linux and other supported systems | Terminal charts/process tree; current macOS version supported Apple Silicon GPU | More visual than htop, but much interpretation remains |
| [bottom](https://github.com/ClementTsang/bottom) | Open source, MIT; macOS/Linux/Windows | Customizable terminal charts/process view | Metric coverage differs by platform; application/project diagnosis is not the focus |
| [Glances](https://glances.readthedocs.io/en/latest/) | Open source, LGPL-3.0; macOS/Linux/Windows | Terminal/web, plugins, export and containers | Threshold alerts are not root-cause proof; sensors/GPU/I/O vary by platform |
| [Netdata](https://learn.netdata.cloud/docs/collecting-metrics/collectors/operating-systems/macos) | Open-source agent and commercial cloud options | Continuous time series/alerts; machine plus server/container context | Larger system for simple single-Mac use; current macOS modules need individual checks |
| [macmon — vladkens](https://github.com/vladkens/macmon) | Free, MIT; Apple Silicon | CPU/GPU/ANE, power/temperature; current version also had process details | Terminal/low-level telemetry focus; private macOS interfaces add compatibility burden |
| [NeoHtop](https://github.com/Abdenasser/neohtop) | Open source, MIT; desktop with macOS support | Search, filters and pinned processes | Cleaner process list; no documented explanatory diagnosis layer |
| [Performance Monitor — inequitas](https://github.com/inequitas/performancemonitor/blob/v1.3.1/README.md) | Open source, MIT; macOS 14+, Apple Silicon | Application/helper grouping, plain status sentences, process descriptions | Ad hoc signed without notarization: a concrete distribution limitation |

NeoAsitop and asitop were also reviewed. They can explain hardware activity, but evidence of current macOS/hardware compatibility and maintenance was more limited, so they were not first candidates. [NeoAsitop](https://github.com/op06072/NeoAsitop), [asitop](https://github.com/tlkh/asitop).

[Mission Center](https://missioncenter.io/) on Linux is a useful application-focused reference, and [System Informer](https://www.system-informer.com/index.php) on Windows illustrates navigation from a historical peak to a process. Neither is a macOS alternative. Netdata's [process documentation](https://learn.netdata.cloud/docs/live-view/processes) covers macOS grouping; live process tables and historical charts are distinct capabilities.

## Details that affect evaluation

Mac Performance Monitor's site documented comparison of eight live/exited processes on one timeline, CSV export and navigation from alerts to evidence. The site showed version 2.0 while GitHub's latest stable was 2.4.0 build 289, dated October 17, 2026. Use the release record for installation version because of that discrepancy. [Product features](https://macperformancemonitor.com/), [2.4.0 release](https://github.com/Zesty0wl/mac-performance-monitor/releases/tag/v2.4.0.289).

MPM's version-pinned alert documentation does not treat stable high swap alone as an alarm, does not interpret missing data as recovery and distinguishes growth from leak evidence. It also notes that some new rules need broader live validation. This is a useful explainability approach, not independently measured alert accuracy. [Rules and validation limits](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/docs/adaptive-alerts.md).

Its 0–100 pressure index is an application-computed composite, not a direct Apple pressure percentage. Shared reports do not automatically anonymize names/paths. It is not sandboxed and offers an optional helper for broader process access. Exposing local metrics to an external AI agent may transfer data to that agent's provider; basic recording and additional sharing are separate decisions. [Index definition](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/docs/pressure-index.md), [data/sharing policy](https://github.com/Zesty0wl/mac-performance-monitor/blob/v2.4.0.289/SECURITY.md).

Vitals first launched publicly on September 22, 2026; its changelog listed 1.8.1 dated October 21 during research. It offered a three-day trial. Pricing/currency varied by page/region, so no fixed Turkish-lira or annual total was asserted without checkout verification. [Changelog](https://vitalsmac.com/changelog), [license terms](https://vitalsmac.com/terms).

“Up to one year of history” does not mean a year of detailed process records: the FAQ limited application/time correlation to two days, with older system metrics and daily application summaries. Sampling is not second-by-second forensic recording. If pinpointing the second a slowdown began matters, test this distinction. [History details](https://vitalsmac.com/features/history).

Vitals' privileged helper for fuller visibility is optional. Enabling AI-plan usage features reads existing tool-session information and requests provider data; these are not required for basic monitoring. The Mac App Store's Vitals Lite has different scope. Start comparisons with resource monitoring and evaluate integrations separately. These are vendor statements, not an independent security audit. [Privacy and permissions](https://vitalsmac.com/privacy).

## Use cases: user outcomes

P0 means the initial product/tool evaluation, P1 a follow-up, and P2 only after need is established. Priorities are proposals. Each explanation/action below is a proposed product requirement, not an event observed on the current machine.

| Priority and scenario | User question | Required evidence | Understandable outcome and next step |
|---|---|---|---|
| P0 · Current slowdown | Why did it slow down now? | Recent CPU, pressure, swap activity, I/O and application changes | Strongest candidate, evidence window and missing evidence; open its application |
| P0 · Whole-application impact | What do Claude/VS Code consume in total? | Application identity, helper relationships, consistent metrics | One application row with members and attribution reasons |
| P0 · Project ownership | Which projects own these ten node processes? | Start time, parents, working directory, ports; integrations if needed | Project → task → process; uncertain mapping labelled |
| P0 · Memory pressure | Is RAM actually insufficient? | Pressure/compression trends, swap-in/out deltas, footprints | Distinguish full but healthy memory from pressure |
| P0 · Recent history | Why did it stall five minutes ago? | Timestamped data including exited processes | Pressure, consumers and start/end events on one axis |
| P0 · Intervention effect | Did closing an application help? | Comparable before/after workloads and a user latency measure | Separate resource change from task-time/responsiveness change |
| P1 · Docker/VM | Docker, or which internal service? | Host VM plus container identities, limits and stats | Nested but separately accounted host and guest consumption |
| P1 · VS Code extension | Which extension is loading the editor? | Extension Host/renderer distinction and VS Code profiling | Navigate to extension profiling; never guess an extension without evidence |
| P1 · Agent-launched work | Which session started this test/server? | Session identity, launched commands, ownership chain | Agent → project → task → process, retained after the window closes |
| P1 · Idle work | Which unneeded tasks remain open? | Age, activity history, listening ports and dependencies | Candidate list without treating low CPU as unnecessary |
| P1 · Disk waits | Is the SSD causing stalls? | Rates, available latency/queue signals, process I/O deltas | Separate storage capacity from I/O pressure; no diagnosis from MB/s alone |
| P1 · Network/remote service | Local computer or internet/API? | Traffic, connections, request timings/logs if available | Separate local load from remote waits; low traffic is not healthy-network proof |
| P1 · Heat/power | Is heat reducing performance? | OS thermal state and load/frequency/power relationship | Temperature alone is not throttling; observe changes after reducing load |
| P1 · Memory growth | Is an application retaining memory? | Long-term same-workload footprint, idle/completion/repetition | Report sustained growth; use a profiler for leak evidence |
| P2 · GPU/local model | CPU or GPU bottleneck? | GPU activity, memory/thermal limits, model/task timing | Do not hide GPU pressure behind low CPU; distinguish local/cloud models |
| P2 · Support sharing | How can I show this slowdown? | Event window, metric version, anonymized consumer information | Local report for only the selected interval with sensitive arguments/paths removed |

A monitor can identify VS Code's helper, but extension attribution needs editor tools such as Process Explorer and Extension Bisect. General monitoring should provide a useful path into application-specific diagnosis. [Microsoft: performance issues](https://github.com/microsoft/vscode/wiki/Performance-Issues), [Extension Bisect](https://code.visualstudio.com/blogs/2021/02/16/extension-bisect).

## Proposed interface

Organize around four questions: Now shows a short state sentence, resources and leading applications. Applications offers comparable rows and expandable helpers. Projects groups ports, agent sessions, servers and containers by work. History compares events and consumers on one timeline. This is a design proposal, not an approved screen or usability result.

Avoid a single “health score 73”. State measurement time and knowledge instead: “CPU busy; memory pressure normal”, “Pressure increased; X had the largest growth”, or “No data for this interval”. Consumption ranking and possible delay causes need separate wording. Freeze/stable ordering and “mark now” make moving numbers readable.

A wholly hypothetical explanation: “Pressure rose over the last three minutes. X's footprint increased in the same interval. Swap writes also accelerated. The relationship is strong; why the application's memory grew is unknown. Open that interval.” It helps without exceeding evidence.

## Feasible build scope

The user selected live terminal plus report commands, superseding the initial SwiftUI-window suggestion. Preserve an independent collector, explicit rules and local history; one core feeds terminal and reports. Storage/language details belong to the new design, not an already-implemented architecture claim here.

Flow: OS/tool measurements → time/unit normalization → application/project mapping → history → rules → explanation/evidence. Counter metrics use differences between samples. Process identity is PID + start time. Unavailable readings never become zero; access denied, unsupported, stale and sleep gaps remain distinct.

Do not conflate RSS, footprint and virtual space. Shared pages, compression and Apple Silicon unified memory make summed process RAM different from total physical RAM. Apple's proc_pid_rusage example for an app's own footprint does not guarantee equal access to every process. [Apple: memory profiling](https://developer.apple.com/videos/play/wwdc2022/10106/).

libproc is a powerful source, but its Apple header warns about private interfaces subject to change. Verify each call by SDK, permissions and distribution model; do not assume every API is stable/public or guaranteed App Store eligible. [Apple XNU libproc header](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/libsyscall/wrappers/libproc/libproc.h).

| Data | Feasible approach | Initial boundary |
|---|---|---|
| CPU/application identity | Counter deltas, bundle identity, lifetime and parents | No rate from the first sample; identical names do not imply the same app/project |
| Pressure | OS events plus VM/swap counters | No claim that categorical events reproduce Activity Monitor's numeric graph |
| Process disk activity | Rates from cumulative bytes | Not per-file latency or physical-disk waiting |
| Network | Interface totals first; process attribution separately | Connection lists are not per-app bytes or HTTP response times |
| Thermal/GPU | Thermal state and supported hardware/OS metrics | Temperature, power and every process's GPU share do not have one universal Mac API |
| Docker | Adapter for the selected local daemon | Do not count host VM and guest/container totals twice |

Apple's [Dispatch memory-pressure source](https://developer.apple.com/documentation/dispatch/dispatch_source_type_memorypressure) and [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication) support these layers. Process disk bytes appear in [XNU resource definitions](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/resource.h); access/comparability still require runtime validation. Apple's DTS [Network Extension approach](https://developer.apple.com/forums/thread/824751) for process network attribution requires additional permission/distribution and scope work.

Docker Desktop's Linux VM and internal containers have different accounting. The CLI may subtract cache differently from raw API memory. Every percentage/total must identify its layer and definition. [Docker VMM](https://docs.docker.com/desktop/features/vmm/), [Docker stats](https://docs.docker.com/reference/cli/docker/container/stats/).

Initial collector proposal: 1–2 seconds while visible, 5–10 seconds in background, expensive details on demand. Tune by measurement. Short processes can start and end between polls; never interpolate sleep/wake gaps as real data. Full command arguments and environment variables should not enter default history.

## Evidence and notification rules

Expose four evidence levels: measured fact; temporally related candidate; effect supported by comparison; insufficient data. Improvement after stopping an application is useful support, but concurrent changes prevent proof of a single cause. An LLM should not be the first diagnosis engine; if added later, it should explain measured signals/rule outputs without inventing missing data.

Notifications should depend on persistence, recovery and recurrence rather than one sample, and not repeat each refresh. Investigation is the initial default action. Process termination, service stop and fan control are separate user-initiated actions. CPU percentage alone cannot establish that an idle database or development server is safe to stop.

## Proposed validation experiment

Record normal development, then a build/test and a multi-application session. Mark real slowdowns without deliberately forcing swap. Install no new tool. Existing OS tools provide system references, Docker's own stats can reference containers, and existing application profilers can investigate internal causes. Metrics with the same name but different definitions must not be tested for literal equality.

| Proposed acceptance criterion | Evaluation |
|---|---|
| Understand state in ten seconds | User correctly identifies main pressure and freshness |
| Find application/work in thirty seconds | Known ownership maps correctly; uncertain ownership is not guessed |
| Retrieve a past event | Reach a marked slowdown interval and its processes |
| High healthy use does not cause panic | Builds, cache and stable swap avoid false definitive diagnosis |
| Unmeasured data remains visible | Fields show unknown without unavailable helper/permission |
| Monitoring does not distort measurement | Measure its CPU, RAM, disk writes and battery impact visible/hidden |
| Intervention benefit can be measured | Compare task time/user latency alongside resource percentages |

An initial overhead goal might be below 1% of one core on average when hidden and around 100 MB memory. These are engineering targets, not measured results or guarantees. Recording scope/hardware affect the budget; frequent scans, sensor queries and per-process history writes need separate measurement.

## Scope and effort proposal

Assuming one experienced developer, macOS priority and basic features: 3–5 working days for data/permission feasibility, roughly 3–5 weeks for a personal MVP, then another 4–8 weeks for broader hardware, event/history reliability, signed distribution and recovery. These are rough scope estimates, not measured schedules or commitments. Project/agent integration and comprehensive process network/GPU attribution increase effort most.

The MVP should combine summary, application grouping, pressure/swap activity, short history, event markers and evidence-backed basic project mapping. Mapping can start with working/command directories and explicit user labels; ambiguous work remains unassigned. Docker and detailed agent sessions follow later; advanced GPU/sensors and application-specific diagnosis links depend on demonstrated need. Multiple OSes, cloud fleets, automatic cleanup and definitive AI answers unnecessarily expand the first scope.

The chosen direction is a product built from scratch with a live terminal and report commands. Installing existing tools or forking a project is not the current request. These use cases and evidence limits inform design.

This research establishes documented features and technical limits. It does not claim to identify this computer's bottleneck, measure competitors' accuracy/battery cost or validate the proposed interface with users.
