# README walkthroughs

These animations use TAWL's production terminal renderer with fixed, synthetic snapshots. They are not recordings of a real user's processes, performance benchmarks, or evidence that termination caused a resource change. No process is terminated while generating them.

| Asset | Content | Playback |
| --- | --- | --- |
| [Workload overview](tawl-overview.gif) | Application, project and category views; CPU cores and device-level GPU activity | 22 seconds |
| [Process review](tawl-process-review.gif) | Affected application, explicit confirmation, and before/after charts | 15.4 seconds |

Both clips loop at 1240 × 804 pixels. [Overview](tawl-overview.png) and [comparison](tawl-process-review.png) posters provide static alternatives. Visible captions describe the controls, and a synthetic-data label stays on screen throughout.

The process-review clip compresses a synthetic 60-second observation window. CPU, pressure and swap-write values change; the swap stock stays unchanged. GPU activity is per device, not per GPU core.

## Reproduce

Run from the repository root on macOS with Xcode and the same Swift build tools used for TAWL. The commands below use the Xcode build backend's debug output paths. The rasterizer requires Python 3 and Pillow as documentation tooling only; neither is required to install or run TAWL.

```sh
mkdir -p work
swift test
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx15.0" \
  -I .build/out/Products/Debug \
  -Xcc -fmodule-map-file=.build/out/Intermediates.noindex/GeneratedModuleMaps/CTawl.modulemap \
  scripts/readme-demo.swift \
  .build/out/Products/Debug/TawlCore.o \
  .build/out/Products/Debug/CTawl.o \
  -framework AppKit -framework IOKit -o work/readme-demo
./work/readme-demo > work/readme-demo.json
python3 scripts/render-readme-gifs.py work/readme-demo.json
```

[`readme-demo.swift`](../../scripts/readme-demo.swift) drives the real screen state and renderer using a fake termination controller. It checks the default Cancel choice, explicit confirmation, a single simulated request, and a completed comparison. It never calls the native process termination controller.

[`render-readme-gifs.py`](../../scripts/render-readme-gifs.py) converts those ANSI frames to GIFs and PNGs. It preserves terminal colors, uses one palette per clip, and verifies frame counts, timing, dimensions and a 2 MiB limit per GIF. Menlo is the default font; `--font /path/to/monospace-font` selects another installed font. All generated assets go to this directory unless `--output` overrides it.

The renderer and fixture are deliberately separate from the installed application. Rebuild these assets when the demonstrated screens or controls change.
