# TAWL usage guide

**Terminal Activity & Workload Lens** is a live terminal and reporting tool for reading macOS load at **application, project and usage-category level**.

It answers “Is the machine under pressure?”, “Which applications consume resources?” and “What changed during the slowdown?” with measurement time, scope and explanation. Enter opens the process list; a second Enter opens the selected process's evidence and recommendations.

## Run from source

The `tawl` binary built in this directory runs directly without installation on PATH:

```sh
cd tawl
./tawl
```

Use the existing Xcode/Swift tools to rebuild:

```sh
make build
make test
```

No external Swift package, Homebrew package, daemon, web server or privileged helper is installed by this workflow. The first validated development environment was **Apple Silicon, macOS 27.0.1, Swift 6.4**. The initial macOS 15 deployment setting was not itself proof of compatibility; the 0.1.0 release was subsequently built and tested on hosted macOS 15 ARM and Intel runners. Linux and Windows are not supported.

## Language

Language selection is available from **0.2.0**. English is the default; Turkish is available explicitly:

```sh
./tawl --lang en
./tawl --lang tr
TAWL_LANG=tr ./tawl
TAWL_LANG=tr ./tawl --lang en
```

The command-line `--lang en|tr` setting overrides `TAWL_LANG`. If neither is set, TAWL uses English, independently of the OS locale. The selected language applies to interface text and human-readable output; metric meanings, keyboard controls and machine-readable data contracts remain unchanged. Project documentation is in English.

## Upgrade an installed version

```sh
tawl update check
tawl update
tawl --version
```

`tawl update` shows the candidate version and asks for confirmation. Homebrew installs delegate to Homebrew; alternatively run `brew update` and then `brew upgrade phalegethon/tawl/tawl`. Standalone installs verify the downloaded executable before replacement. Source checkouts use `make build`. Recordings and existing reports are preserved.

## Commands

```sh
./tawl status --sample 3s
./tawl status --json
./tawl watch --record ./session.tawl
./tawl record --duration 10m --output ./session.tawl
./tawl report ./session.tawl --last 5m
./tawl report ./session.tawl --json
./tawl --help
```

`status` takes its own short sample. `report` reads the explicitly supplied file offline; it does not measure the computer's current load. `--last` is relative to the recording's final sample. Durations accept `s`, `m` and `h`; `status --sample` accepts 0.1–10 seconds and recording duration is capped at 24 hours. `record` defaults to 60 seconds; the file-size limit may stop it earlier.

## Live controls

| Control | Action |
|---|---|
| ↑/↓ or j/k | Select a workload, or a process in details |
| Enter | Open a workload's process list, then a process's assessment and recommendations |
| Tab | Applications → Projects → Usage categories |
| 1 / 2 / 3 / 4 / 5 | Sort by name / CPU / footprint / Δ memory / member count |
| Active 1–5 key again, or r | Reverse sort direction |
| 0 / s | Automatic sorting / next sort field |
| o | Show only recommended processes in the selected workload; press again for all processes |
| x | Open process closure: select a candidate, review impact, confirm |
| e | Open the latest accepted closure request's before/after resource comparison |
| d (comparison) | Save one HTML report with charts and values |
| a (save result) | Open the saved report in a browser |
| g | Show or hide the CPU core / GPU panel; visible at launch |
| [ / ] | Change hardware page when there are more cores/devices |
| b | Focus on memory/swap: sort applications by footprint and inspect system swap; press again to leave focus |
| / | Search names; Enter applies, Esc clears |
| h, then ←/→ | Browse actual historical samples from this session |
| Space | Freeze the displayed frame while collection continues |
| m | Add a slowdown marker at the current live time |
| PgUp/PgDn, Home/End | Navigate long lists |
| Mouse wheel | Move selection in lists or scroll within an assessment |
| ?, Esc | Help / back |
| q or Ctrl-C | Quit and restore terminal settings |

Minimum size is 80×24. At launch, the top area shows CPU core charts and whole-device GPU utilization. g returns to CPU/memory/disk/network summary charts. Hardware mode retains memory pressure, swap, disk and network in a compact summary line. At 120 columns or more, a right-hand inspector shows the selected workload's CPU/memory history and leading processes. Numeric columns align right and selection spans the full row.

Each detail row compares one process's PID, name, CPU, footprint, memory change and, when space permits, age. The selected-process assessment appears on the right on wide screens and below the list on narrow screens. A second Enter opens graphical assessment with CPU/footprint history and observation durations. The first view shows a short next step, with detailed reasons below. A wide assessment also shows system swap context. Esc goes back one level. Detail lists use sorting keys **1–4**; member count applies only to workload lists.

Observation bars show measured progress toward the **30-second CPU** and **600-second low-activity** conditions; they are not confidence scores or problem probabilities. “No evidence” and `?` indicate missing measurements; `0 s` means evidence is new or interrupted. Missing resource measurements cannot establish that a threshold was not exceeded.

The live interface fills the terminal's content area and uses an alternate screen buffer that preserves shell history. The wheel navigates within the application; refreshes do not append lines to terminal scrollback. Input, cursor, wrapping and mouse modes are restored on exit. Whether the host hides its scrollbar or forwards wheel input depends on terminal support/settings; TAWL never changes persistent terminal preferences.

CPU is cyan, GPU purple, memory amber, disk blue and network green. High consumption makes the **corresponding numeric cell** yellow/red. `CPU!`, `RAM!` or `Δ!` beside the name identifies the resource needing attention. `RAM!` refers to footprint, not a physical RAM percentage.

Investigation thresholds are **CPU ≥1 core yellow, ≥2 red**; **footprint ≥2 GiB yellow, ≥4 red**; **memory growth ≥100 MiB in the latest interval yellow**. These are not bottleneck or leak diagnoses. Pressure history uses `▁` normal, `▄` warning, `█` critical and `·` missing. `NO_COLOR=1 ./tawl` disables colors while shapes, labels and numbers preserve meaning. The interface is designed for a dark terminal background.

Main monitoring and process charts show samples from **up to the latest 120 seconds**, not a uniform time axis. The displayed time range is labelled. When multiple samples share a column, the peak is drawn; any missing sample produces `·`. Collection gaps over five seconds are also marked. System CPU uses 0–100%; disk/network directions share an automatic scale. Selected-workload charts label their automatic scales. Row CPU bars are relative to total logical-core capacity; row memory bars are relative to **the largest footprint in that list**, not RAM occupancy.

Automatic sorting uses footprint under memory pressure and CPU otherwise. A manually selected field remains selected when pressure changes; the heading arrow shows direction. Memory change sorts by signed value; unknowns stay last in both directions. Selection retains workload identity across reorderings. When a process disappears, its old values are labelled and no current closure recommendation is generated. Under the recommendation filter, a selection that stops qualifying moves to a visible candidate or clears if none remain. Applied search remains visible after Enter. Use `status` or `report` for redirected output.

## CPU cores and GPU

**g** toggles the main hardware area, which is open at launch. Each CPU chart shows one logical processor's busy time on a shared fixed **0–100%** scale. **E** means efficiency and **P** performance; unverified types remain **?**. Percentages come from two readings. The first sample, a long gap, changed topology or reset counter is unmeasured. **≥80% yellow and ≥95% red** highlight load without diagnosing a bottleneck.

The initial test Mac had **12 CPUs (4 E / 8 P)** and a **38-core Apple M2 Max GPU**. The GPU chart is the driver's **whole-device total**; 38 is hardware metadata. This source exposes no individual GPU-core utilization. TAWL neither copies one percentage across every core nor infers a measured active-core count. Unavailable measurements show — instead of zero. Measurements are system-wide and do not isolate an LLM process. Equal E/P percentages do not imply equal compute throughput.

At 80×24, that machine's 12 CPUs, GPU and at least six application rows fit together. **[ / ]** reach additional cores/devices; the heading shows page coverage. Space and h bind hardware charts to the same frozen/historical instant. Old recordings without hardware fields show measurements as unavailable; new recordings carry them as optional fields.

For local LLM investigation, compare an idle baseline with model loading and response generation using CPU/GPU charts and memory pressure. GPU percentage is neither tokens per second nor GPU memory. See the [CPU/GPU measurement note](research/2026-10-22-hardware-telemetry.md) for sources and limits.

## Metric definitions

| Field | Meaning |
|---|---|
| System CPU % | Capacity percentage calculated from aggregate CPU counter differences between two readings |
| Application CPU cores | Process CPU-time delta / elapsed time. **1.00 = one logical core**, not 100% of the machine. P/E performance is not assumed equal; this is a time equivalent. |
| Memory footprint | macOS `ri_phys_footprint`, summed over visible members of the group. Neither a RAM percentage nor guaranteed reclaimable memory. Compression/accounting mean application totals must not be equated with physical RAM capacity. |
| Δ memory | Change during the last valid interval for the same PID + start time. Added/exited processes are separate effects. Missing member deltas are not complete group growth. |
| Memory pressure | OS normal / warning / critical signal; unavailable if it cannot be read. |
| Swap and swap activity | Total disk-backed swap and interval swap-in/out are separate metrics. Rates derive from page counters, not physical bytes written to the SSD. Large inactive swap alone does not prove a bottleneck. |
| Disk rate | Read/write rates from physical IOKit block drivers that expose counters. Virtual disk images are excluded. This is not latency, queue, file-level or application-level causal measurement. |
| Network rate | `en*` Ethernet/Wi-Fi interfaces; excludes loopback, tunnels, virtual bridges and differently named interfaces. No per-application network attribution. |
| Process age | Time from OS process start to the sample, not time since the user's last interaction. Unknown when unreadable or absent in old recordings. |
| `?`, `—`, `*` | Unknown/not-yet-calculated value or partial total; never measured zero. |

The first sample establishes a baseline. Counter reset, changed process identity, changed device and gaps over 15 seconds reset rate calculation. Very short-lived jobs may fall between readings. The base interval is two seconds; one collection pass is not an atomic system snapshot.

## Grouping and interpretation

- Nested helper `.app` processes join the outer application. Children outside the bundle may use the live parent chain. Unmatched processes use executable identity, or their own lifetime identity when that is unreadable. The actual owner of a visible VM or shared helper cannot always be determined.
- Project attribution searches a bounded number of parents of a readable working directory for `.git`, `package.json`, `Package.swift`, `pyproject.toml`, `go.mod` or `Cargo.toml`. A monorepo package may match the nearest marker. Arguments/environment are not scanned; a command started elsewhere may remain unmatched. Without evidence it stays in the unidentified-project group.
- Usage categories are independent of projects: **Browsers, Development, AI, Communication, Virtualization, Databases, Media, System and Other**. They use known application/process names; helpers stay with a recognized application's category. Uncertain applications go to Other. This describes the application's general purpose, not its current task. User-defined categories are not available in this version.
- Memory pressure is described as a direct observation. A system CPU finding requires every sample above 85% during at least 30 uninterrupted seconds. Process recommendation thresholds are separate below.
- “Largest consumer” does not mean root cause. This version does not diagnose memory leaks, GPU/thermal throttling, SSD latency or network latency. Lower CPU does not always mean a faster application.

## Process recommendations and closure

In a selected workload, `o` filters processes with an investigation recommendation. Recommendations require verified ownership and application eligibility. System, database and virtualization services receive resource warnings but no closure recommendation.

- **Sustained CPU:** ≥1 core for at least 30 uninterrupted seconds. The explanation notes that this may be an expected build or other useful task.
- **Memory pressure:** footprint ≥2 GiB while system pressure is elevated. Large consumption is not presented as a proven cause or guaranteed RAM recovery.
- **Long-running, low-activity candidate:** age ≥2 hours with 600 uninterrupted seconds of known CPU <0.02 cores, disk reads and writes each <1 KiB/s, and footprint ≥256 MiB. Missing measurements, changed process identity or gaps interrupt the duration. Window/keyboard interaction and per-process network activity are unmeasured, so **“unused” is never concluded**.

Check the application's task/tab and save your work first. **x** opens **Process closure** from the main list, process list or assessment. From the main list it prioritizes the selected workload; from process details it retains the selected process. Opening or navigating the dialog sends no request.

1. Select with **↑/↓**. **Tab** switches between every process in the selected workload and recommendations across all applications.
2. **Status** distinguishes **SUGGESTED**, **MANUAL** and blocked targets. You may manually select a verified owned application process without an automatic recommendation. The lower area shows affected application, single-PID scope and reason. Unverified ownership/protection is explained there. **A large application total does not automatically recommend every helper; absence of a recommendation alone does not block closure.**
3. **Enter or i** opens impact/confirmation. Review application, PID, process name, recommendation and possible data loss. **Cancel** is selected by default. Use **→ or Tab** to select the send-termination-request action, then **Enter or Space** to confirm. Scroll to the end of long impact text first.
4. **Esc** returns from confirmation to process control; another Esc returns to monitoring. Native validation/permission errors remain in the dialog. The attempted row becomes red **BLOCKED**, and Enter/i retries. An unreadable terminal ancestry chain is explained separately from target protection. History/frozen views show how to return to live measurement.

If Enter does not respond in your terminal, use **x → i → right arrow → Space**. i only opens review; Space activates the selected button, with Cancel still the initial selection.

An accepted request opens resource comparison. **Esc** returns to the control dialog; **e** reopens the same comparison. `o` still filters recommendations in the original process list.

Only the selected process receives **SIGTERM**. This is not the application's normal Quit menu: a save dialog may not appear, unsaved changes may be lost, and related tabs/windows/tasks or the whole application may be affected. Other members receive no direct signal. There is no automatic retry, bulk closure or SIGKILL.

Confirmation is valid for **30 seconds**. Enter collects a fresh sample; ownership, process and application must still match. A decreasing/disappearing recommendation does not revoke explicit target selection; recommendations and closure eligibility are separate. The OS audit token, start time, executable and user identity are revalidated. If macOS cannot supply the required identity, the action stays blocked rather than falling back to PID-only signalling. TAWL, its ancestors, system/database/VM services and other users' processes are protected. History and frozen views cannot terminate processes.

**Request sent**, **exit confirmed**, **still running**, **identity changed** and **outcome unverified** are distinct. The application may restart a helper; one process's exit does not establish that the entire application closed. See [process-control safety](research/process-control-safety.md).

When bracketed paste is supported, pasted text is not treated as commands; use keys to confirm. TAWL does not change process priority, clean RAM or alter system settings.

## Before and after closure

The comparison opens automatically when the confirmed **SIGTERM request is accepted**. It freezes the **30 seconds before** the request and collects **60 seconds after**. The header shows application/PID, request time and the process's separate exit outcome. Four charts fit together even at 80×24:

- **System CPU:** time-weighted averages for both periods and percentage-point change, on a fixed 0–100% scale.
- **Memory pressure:** normal/warning/critical history and each period's last valid state. Categories are never averaged numerically.
- **Swap amount:** final disk-backed amounts and difference, on an explicitly labelled shared zoomed scale that reveals small changes.
- **Swap writes:** time-weighted RAM→disk activity. New writes may stop even while swap amount stays unchanged.

This view has a **uniform, fixed −30…+60 second axis**; the vertical line marks the request. Dots mean missing measurements, blank space means future time, and a baseline means measured zero. CPU/writes show actual valid coverage; short history does not count as a full 30 seconds. A rate interval crossing the request is excluded from the after-period average. Unreadable pressure/amount or a final reading older than five seconds remains unknown.

Collection continues after **Esc/Enter** returns to monitoring; **e** opens the same report. At 60 seconds the result becomes fixed. Only the last accepted request's report stays in session memory; cancelling or rejecting a new confirmation does not replace it. Preparing a new confirmation releases the previous native observation identity; any unresolved earlier exit remains unverified. There is no automatic disk save; reports not exported with d disappear when TAWL exits.

Charts show **observed system changes**, not the isolated causal effect of closing one process while other tasks run. Swap change is not guaranteed freed RAM and no time-to-zero forecast is made.

## Export a chart report

In comparison, **d** saves the current report as one `.html` file in **reports/** beneath the launch directory. The result dialog shows the **full path**; **a** opens it in a browser, and **Esc/Enter** returns to comparison. On a write error, **d** retries from the same dialog.

The report includes target/exited process name and PID, affected application, request/export times, confirmed or uncertain exit outcome, before/after values and differences, measurement coverage, and **four SVG charts for CPU, memory pressure, swap amount and swap writes**. System-wide changes are not presented as guaranteed per-process savings.

Exports made before 60 seconds are labelled **Partial report**. Files do not update themselves; press d later for a new copy. Every filename is unique and existing reports are never overwritten. Charts/styles are embedded; no internet, web server or additional program installation is required. Browser printing can save a PDF.

Files are created with mode 0600 and newly created report directories with 0700; existing directory permissions are unchanged. Reports contain application/process names and PIDs, so inspect them before sharing. HTML is a separate document and does not replace a `.tawl` session recording.

## Memory and swap focus

`b` clears search and sorts applications by descending footprint. The side panel or narrow summary separates **disk-backed swap amount**, **RAM → disk writes** and **disk → RAM reads**. Amount and rates have their own scales; read rate does not imply the same reduction in swap amount. Up to 120 seconds of continuous amount change is an observation, not a clearance forecast.

The view distinguishes writes, reads, no transfer and unknown measurement. Under pressure or current writes, the goal is to close unnecessary work normally and **compare whether pressure and new swap writes fall**. Normal pressure and no writes do not justify closing applications solely because accumulated swap is high.

Per-process swap ownership is not measured. The largest application is not a proven swap cause, and footprint is neither reclaimable GiB nor a time-to-reduction estimate. TAWL does not clean swap, run `purge`/`swapoff` or restart the machine. See the [swap research note](research/2026-10-22-swap-evidence.md).

## History, recording and privacy

Default history stays in memory: **the latest 30 minutes or an estimated 64 MiB recording budget**. The estimate uses JSON size plus entry allowance, not an actual RSS cap. The screen shows the retained window's start/end. Events before TAWL launched are unavailable.

FROZEN and HISTORY retain their displayed chart even if live history is evicted. Each pinned window additionally holds up to 120 seconds / 8 MiB of encoded history; if the selected sample alone exceeds the budget, it is retained on its own. This is also not an RSS limit. Leaving the mode releases that history.

Live recommendations maintain a small duration summary separately from full history: current process identities, the last resource reading and durations capped at 30/600 seconds. This preserves uninterrupted activity evidence when full samples are evicted; process exit or a measurement gap resets it. Freezing live data preserves its evidence. Moving to another historical sample never borrows later evidence.

Disk recording starts only with `--record` or `record --output`. Files are exclusively created with mode 0600; existing files and target symlinks are not overwritten. Recording stops with an explicit error at **100 MiB**. Files are not automatically deleted. On a Mac with many processes, the limit may arrive before ten minutes because every visible process is recorded in each sample.

The format is version 1 NDJSON. New recordings use format identifier `tawl`; `.tawl` is the recommended extension. The reader also accepts legacy identifier `nabiz` and `.nabiz` recordings; old files need not be renamed.

Process age and owned-application eligibility are optional fields. If absent in older recordings, they remain unknown and cannot support closure recommendations. Full paths, working directories, command arguments, environment variables and network endpoints are not recorded. Application/project/process names and PIDs are included; **recordings are not anonymous**. Local identity hashes are not cryptographic anonymization. Measurement data is never uploaded. At monitor launch, GitHub release metadata may be requested in the background at most once per day; `TAWL_NO_UPDATE_CHECK=1` or `--no-update-check` disables this. Treat JSON reports with the same care.

The reader validates file/line sizes and numbers; malformed interior lines and unsupported versions are rejected. A truncated final line may be recovered with a warning while reading the complete preceding portion. Invalid monotonic order is rejected; wall-clock corrections do not change duration calculations.

## Development structure

`CTawl` provides native counters and the terminal bridge. `TawlCore` handles measurement deltas, attribution, interpretation, history and terminal presentation. `Tawl` connects the CLI. Paths in `RawReading` stay in memory; `Snapshot` is the persistent measurement model.

Rendering uses the alternate screen buffer and absolute cursor positioning (CUP), emits no LF, and disables automatic wrapping for the session. Vertical wheel input supports SGR and legacy X10. Supported saved modes are restored on exit; this does not guarantee the host terminal's scrollbar visibility.

[Research and use cases](research.md) · [Product scope](../PRODUCT.md) · [Installation and updates](../README.md)
