# TAWL

**Terminal Activity & Workload Lens** — understand what is loading your Mac, from your terminal.

TAWL groups processes by application, project and usage category, shows CPU core and GPU activity, and helps investigate memory pressure. Inspect a process, review which application it affects, confirm termination, then compare system resources before and after with exportable charts.

Requires **macOS 15 or later**. Apple Silicon and Intel release builds are separate. The interface currently uses Turkish labels. No Python, Node.js or Swift toolchain is required to run a release binary.

## Install with Homebrew

```sh
brew tap phalegethon/tawl https://github.com/Phalegethon/tawl
brew install phalegethon/tawl/tawl
tawl
```

The tap and formula live in this repository. Homebrew owns this installation and handles its upgrades.

## Install without Homebrew

Download the archive matching your Mac from [Releases](https://github.com/Phalegethon/tawl/releases/latest): `macos-arm64` for Apple Silicon or `macos-x86_64` for Intel. Verify it against the release's `SHA256SUMS`, extract it and run the included installer:

```sh
bash install.sh
```

The default prefix is `~/.local`. If `~/.local/bin` is not already in your shell's PATH, the installer prints the line to add to your shell configuration. It does not edit that configuration automatically. A custom prefix is supported:

```sh
bash install.sh --prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
tawl
```

Release signing status is stated in the release notes. An ad hoc signature is not Apple Developer ID signing or notarization. TAWL does not disable Gatekeeper or remove quarantine attributes.

## Commands

```sh
tawl                                  # Live monitor
tawl --version
tawl status --sample 3s                # Short system report
tawl status --json
tawl watch --record session.tawl       # Explicit recording
tawl record --duration 10m --output session.tawl
tawl report session.tawl --last 5m     # Offline analysis
tawl report session.tawl --json
```

Legacy `.nabiz` recordings remain readable. Recordings are opt-in and may contain process and project names; treat them as private data.

## Updates

```sh
tawl update check                     # Check for a newer stable release
tawl update --check                   # Same check
tawl update                           # Show version and ask before installing
tawl update --yes                     # Explicit unattended update
```

When launched, the interactive monitor checks for releases in the background, at most once per day, and displays a notice when a newer version is available. It never installs an update automatically. Monitoring works offline; failed checks do not mean the installed version is current. Only release metadata is requested from GitHub; process measurements are not uploaded.

To disable automatic checks:

```sh
tawl --no-update-check
# Or persist this environment setting:
export TAWL_NO_UPDATE_CHECK=1
```

Homebrew installs delegate updates to Homebrew. Standalone installs verify the downloaded binary's SHA-256 digest, architecture and version before replacing the installed executable. Failed verification leaves the current binary intact. Source checkouts are rebuilt by the developer rather than overwritten by the updater.

## Main controls

| Key | Action |
| --- | --- |
| ↑/↓ or j/k | Select workload or process |
| Enter / i | Open details and process assessment |
| Tab | Applications → Projects → Usage categories |
| 1–5 / r | Sort columns / reverse order |
| g / [ / ] | Toggle CPU/GPU view / hardware page |
| b | Memory and swap investigation |
| x | Open the process closure dialog |
| e | Open the last closure comparison |
| d (comparison) | Export standalone HTML with charts |
| h / ← / → | History and samples |
| Space | Freeze the displayed frame; collection continues |
| / / ? / q | Search / help / quit |

Closing a process always requires a separate confirmation. TAWL shows the affected application, validates the process identity immediately before sending SIGTERM, protects system/terminal infrastructure, and distinguishes a sent request from a confirmed exit. It does not escalate automatically to SIGKILL. Comparisons show observed changes, not proof that closing one process caused every change.

## What the numbers mean

- CPU in a process row uses **core equivalents**: 1.00 means one logical core. System CPU is a percentage of total capacity.
- CPU core history is shown individually. GPU utilization is per device when the driver exposes it; per-GPU-core load is not available.
- Memory is the process physical footprint. It is not a guaranteed amount recoverable by closing that process.
- Swap is system-wide. TAWL cannot identify exact per-process swap ownership or promise when swap usage will drop. It shows pressure, swap traffic and memory candidates together.
- Missing or inaccessible data is marked explicitly. High consumption alone is not proof of a bottleneck, a leak or an unused application.

[Detailed Turkish usage guide](docs/usage-tr.md) · [Product scope](PRODUCT.md) · [Measurement research](docs/research.md)

## Build and test

Development requires Xcode with Swift 6 and the macOS SDK.

```sh
make build
make test
./tawl
make install PREFIX="$HOME/.local"
```

Additional checks and release preparation are documented in [Distribution](docs/distribution.md). The release workflow builds each architecture and prepares a draft release for review.

## Uninstall

Homebrew: `brew uninstall phalegethon/tawl/tawl`.

Standalone: run the included `bash uninstall.sh --prefix "$HOME/.local"`. It removes the owned executable and receipt, preserving recordings, reports and unrelated files. Automatic-check cache data may remain in the user's cache directory.

## License

[MIT](LICENSE).
