# Changelog

## 0.2.0 — 2026-10-22

- English is now the default interface language. Turkish remains available through `--lang tr` or `TAWL_LANG=tr`; the command-line flag takes priority and OS locale does not select the language automatically.
- Project documentation is now in English, with one detailed usage guide.
- New chart reports use the `reports/` directory and English filenames. Existing reports remain untouched.

Upgrade with `tawl update`, or `brew update` followed by `brew upgrade phalegethon/tawl/tawl` for a Homebrew-managed installation.

## 0.1.0

Initial TAWL distribution for macOS 15 and later.

- Live CPU core history, driver-provided GPU device utilization, memory pressure, swap, disk and network activity.
- Workload grouping by application, project and usage category; sortable resource columns and process details.
- Explicitly confirmed process termination with affected-application preview, identity validation and protected-process guards.
- Before/after resource comparisons and standalone HTML reports containing charts.
- Opt-in session recording and offline reports, including legacy `.nabiz` compatibility.
- Standalone and Homebrew installation; version checks, background update notices and explicit update commands.

The initial 0.1.0 terminal interface used Turkish labels. GPU core-level usage and per-process swap ownership are not measured. See release notes for each build's signing status.
