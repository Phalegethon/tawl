# Distribution and release maintenance

This guide is for maintainers. Users should follow the [installation guide](installation.md), which makes Homebrew the primary path and documents the standalone alternative.

TAWL runs on macOS 15 or later. Version is defined in `Sources/TawlCore/BuildInfo.swift`; release tags use `vX.Y.Z`. The initial release source is `Phalegethon/tawl`.

## Build and install a development checkout

```sh
make build
make install PREFIX="$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
tawl --version
```

The installer writes `bin/tawl` and `share/tawl/install.json` beneath the prefix. The receipt identifies a standalone installation. Shell configuration is not modified. The updater never edits a source checkout or invokes sudo.

```sh
bash scripts/uninstall.sh --prefix "$HOME/.local"
```

Uninstall preserves recordings, reports and unrelated files. Homebrew installations should use `brew uninstall phalegethon/tawl/tawl` instead.

## Release assets

Each release has one raw executable and one convenience archive per architecture:

- `tawl-X.Y.Z-macos-arm64`
- `tawl-X.Y.Z-macos-x86_64`
- Matching `.tar.gz` archives, including an installer, uninstaller and MIT license
- `SHA256SUMS`
- Generated `tawl.rb` formula
- MIT `LICENSE` and per-architecture signing status

The self-updater downloads the raw executable and verifies the SHA-256 digest in GitHub's release metadata, its Mach-O architecture and its reported version before replacement. It does not extract a remote archive or execute a remote installation script. Published stable versions must have complete assets before publication; drafts and prereleases are not offered as normal updates.

## Signing policy

Current releases use ad hoc signatures and are not Apple-notarized. Developer ID signing and notarization are deferred; they are optional future maintainer work, not a prerequisite for using TAWL. Homebrew verifies archive checksums and owns the installation, but does not confer Apple Developer ID identity or notarization. No installation path disables Gatekeeper or removes quarantine attributes. The [release preparation guide](../packaging/RELEASE.md) retains the optional signing configuration for future use.

## Prepare a release

1. Update `BuildInfo.version`, commit, and create the corresponding `vX.Y.Z` tag.
2. Run the release workflow. ARM and Intel build/test jobs use explicit macOS runners. The workflow prepares a **draft** release rather than publishing automatically.
3. Review CI results, final assets, checksums and release notes. If Developer ID signing/notarization is configured, verify the successful Apple submission; otherwise label the release as ad hoc signed and not notarized.
4. Commit the generated `tawl.rb` as `Formula/tawl.rb` so the Homebrew tap points to that version's immutable downloads/checksums, then publish the reviewed draft. Publishing triggers Homebrew installation checks on both architectures.
5. Verify a clean install, `tawl --version`, `tawl update check`, monitoring and export from the released artifacts.

Local packaging can be performed without publication:

```sh
bash scripts/package-release.sh --binary ./tawl --output work/release
```

Do not build checksums before signing: signing changes the executable. Do not replace assets of a published version to fix a bug; issue a new version.

## Update behavior

`tawl update check` performs an explicit network check. `tawl update` presents the candidate and asks before applying it; `--yes` is the explicit non-interactive form. Homebrew installations delegate to `brew update` and a formula-scoped `brew upgrade`. The standalone path requires an installation receipt and replaces only the owned executable after verification.

Interactive auto-checking is asynchronous and caches checks for at most daily requests. A newer-version notice appears in the footer when no higher-priority action/search message is present. `TAWL_NO_UPDATE_CHECK=1` or `--no-update-check` disables this background request. The GitHub API receives the usual release-request metadata, never process names, project paths or resource samples. Explicit errors are reported; silent background failures keep the monitor usable.

## Validation

```sh
make test
python3 -m unittest discover -s Tests/Distribution
python3 Tests/Interaction/hardware_pty.py
```

Native process-control and closure/report interaction checks are documented in [the interaction test guide](../Tests/Interaction/README.md). That guide also covers the published Homebrew workflow: clean installation, a live `tawl` screen, and real upgrades through both Homebrew and TAWL on native ARM and Intel runners. Distribution unit tests operate in temporary prefixes; the Homebrew upgrade workflow is restricted to disposable hosted runners.

## References

- [Homebrew taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap) and [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [GitHub latest release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
- [GitHub hosted runner labels](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
