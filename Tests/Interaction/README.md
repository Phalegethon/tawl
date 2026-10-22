# Terminal process control and report integration checks

`ClosurePTYHarness.swift` runs the real `TerminalUI` against synthetic snapshots
and an explicitly injected `ClosureSpy`. The spy only logs calls; it never
constructs `NativeProcessController` and never signals a process. The Python
runner may send SIGTERM solely to clean up its own harness child after failure.

After `swift test` has produced the debug objects with the current macOS build
backend, compile the standalone harness without another SwiftPM build:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx15.0 \
  -I .build/out/Products/Debug \
  -Xcc -fmodule-map-file=.build/out/Intermediates.noindex/GeneratedModuleMaps/CTawl.modulemap \
  Tests/Interaction/ClosurePTYHarness.swift \
  .build/out/Products/Debug/TawlCore.o .build/out/Products/Debug/CTawl.o \
  -framework AppKit -framework IOKit -o work/closure-pty-harness
CLOSURE_FINAL_FEATURES=1 CLOSURE_EFFECTS=1 CLOSURE_CONTROLS=1 \
  python3 Tests/Interaction/closure_pty.py
```

The runner opens the process control manager with `x`, chooses a process, and
opens a separate confirmation with Enter. It checks default cancel, Escape, explicit confirmation, replay and
queued keys, small viewports, target stability across sorting changes, stale
samples, explicit choices surviving changed advice, changed ownership/application rejection, PID replacement, split bracketed paste, and scrolling
through long impact information. Effect-comparison checks cover automatic opening,
continued sampling after Escape, reopening with `e` from process/history views,
cancelled or rejected previews preserving the previous comparison, replacement
only after another accepted request, missing data, and independent native status.
Control checks also cover `x` from the main page, manual selection when no recommendation is available, frozen-view rejection, switching to recommendations
outside the selected workload, a visible native-prepare failure, and exporting a
standalone HTML file with all four SVG charts and process/application metadata.
Exports run in a unique per-case working directory; repeated exports preserve
the previous file and return to the same comparison request. A blocked export
path produces a visible error; after removing only the test fixture that caused
the error, `d` retries directly from that overlay without repeating the signal.
Every case also checks terminal mode cleanup.

`CLOSURE_EFFECT_WINDOW=1` adds one real 61.5-second observation, without changing
the production 60-second window. It verifies completion, continued ordinary
sampling, and comparison metrics remaining frozen after the window and on reopen.
Omit that flag for the 37 shorter scenarios. `CLOSURE_EFFECTS=1` enables the eight
short comparison scenarios; `CLOSURE_CONTROLS=1` adds fifteen manager/export and Return-compatibility cases.
`CLOSURE_FINAL_FEATURES=1` includes bracketed-paste
and long-confirmation checks.

Artifacts and fake controller call logs are saved in `work/control-pty/` (override with `CLOSURE_OUTPUT`). The spy
models ticket replacement/clearing by immutable process identity and request time;
its submit/observe results remain synthetic, including any reported process exit.

For a focused rerun, set `CLOSURE_CASES` to comma-separated scenario names from
`work/control-pty/results.json`. Actual native process termination is outside the
scope of these interaction checks.

## Native manual closure from the keyboard

`NativeClosurePTYHarness.swift` creates one disposable `.app` fixture under this
repository's ignored `work/` directory, with a 20-second child failsafe. It runs
the real collector, reducer, terminal input loop and `NativeProcessController`.
An additional test-only wrapper refuses every prepare/submit whose PID differs
from that fixture. Existing user applications are never signalled.

After the current debug build:

```sh
xcrun swiftc -swift-version 5 -target arm64-apple-macosx15.0 \
  -I .build/out/Products/Debug \
  -Xcc -fmodule-map-file=.build/out/Intermediates.noindex/GeneratedModuleMaps/CTawl.modulemap \
  Tests/Interaction/NativeClosurePTYHarness.swift \
  .build/out/Products/Debug/TawlCore.o .build/out/Products/Debug/CTawl.o \
  -framework AppKit -framework IOKit -o work/native-closure-pty-harness
python3 Tests/Interaction/native_closure_pty.py
```

This verifies the original failure end to end: a low-footprint owned application
with zero automatic recommendations is found using `/`, selected using `x`,
reviewed with Enter, and explicitly confirmed using Right/Enter. A real SIGTERM
is sent once to that child. Its exit is observed natively, the comparison opens
automatically with real CPU/pressure/swap samples, and `d` exports four SVG charts.
No expected resource improvement is asserted: the tiny fixture may have no
measurable system effect. This short run exports an honestly partial comparison.
Evidence is saved in `work/native-closure-pty/`.

## Return compatibility regression

The 118×46 MANUAL-manager cases cover CR, LF, atomic/split CRLF,
application-keypad Enter (including split SS3), inherited IGNCR/INLCR, and
`i → Right → Space`. They assert default Cancel, no implicit submission and
restoration of the original terminal flags. CRLF is one logical Return even
across reads; consecutive CR Returns remain distinct.

`TAWL_TEST_KEYBOARD_FALLBACK=1 python3 Tests/Interaction/native_closure_pty.py`
runs the same guarded disposable native child using `i / Right / Space`, with
real exit observation and HTML export; evidence goes to
`work/native-closure-fallback-pty/`.

## Language coverage

The harnesses default to English. Set `TAWL_LANG=tr` to run the same keyboard,
process-identity, confirmation and report assertions in Turkish. The shared
`language_support.py` reads expected labels from the compiled source catalogs;
behavioral assertions remain independent of translated labels. Use separate
`CLOSURE_OUTPUT` directories when running both languages concurrently:

```sh
TAWL_LANG=en CLOSURE_OUTPUT=work/closure-en CLOSURE_FINAL_FEATURES=1 CLOSURE_EFFECTS=1 CLOSURE_CONTROLS=1 python3 Tests/Interaction/closure_pty.py
TAWL_LANG=tr CLOSURE_OUTPUT=work/closure-tr CLOSURE_FINAL_FEATURES=1 CLOSURE_EFFECTS=1 CLOSURE_CONTROLS=1 python3 Tests/Interaction/closure_pty.py
```

Hardware checks finish a partially received frame before evaluating it and save
ANSI output on failure. This avoids mistaking a split PTY read for a missing panel.
