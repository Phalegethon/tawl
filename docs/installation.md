# Install TAWL

TAWL requires **macOS 15 or later** and supports Apple Silicon and Intel Macs. Release binaries need no Swift, Python or Node.js runtime. Homebrew is the primary installation method.

## Homebrew

With [Homebrew](https://brew.sh/) available, run:

```sh
brew tap phalegethon/tawl https://github.com/Phalegethon/tawl
brew install phalegethon/tawl/tawl
tawl
```

The explicit tap URL is required because the formula shares the `tawl` repository. Homebrew selects the architecture and manages the executable on PATH.

To update:

```sh
brew update && brew upgrade phalegethon/tawl/tawl
tawl --version
```

You can also use `tawl update check` and `tawl update`; TAWL delegates a Homebrew-managed update to Homebrew and asks before applying it.

If GitHub limits release checks, these commands show a quota-specific warning. When retry timing is available, it includes the local retry time, timezone and remaining wait. Otherwise, it states that the exact retry time is unknown and advises waiting at least a minute. For Homebrew installations, `brew update && brew upgrade phalegethon/tawl/tawl` skips TAWL's release-metadata check; upstream network limits can still affect Homebrew.

At monitor launch, a background release check runs at most once daily. A newer release or rate limit can appear as a short footer notice while monitoring continues; other background failures stay quiet. A warning does not trigger an automatic retry or installation, and the daily check schedule is unchanged. `TAWL_NO_UPDATE_CHECK=1` or `tawl --no-update-check` disables that automatic check.

To uninstall:

```sh
brew uninstall phalegethon/tawl/tawl
```

Your recordings and exported reports remain in their existing locations.

## Language

English is the default, independently of the OS locale. Select Turkish explicitly or set a shell preference:

```sh
tawl --lang en
tawl --lang tr
TAWL_LANG=tr tawl
```

`--lang en|tr` takes priority over `TAWL_LANG`. For example, `TAWL_LANG=tr tawl --lang en` opens in English. See the [usage guide](usage.md) for keyboard controls, recording and reports.

## Alternative: standalone archive

Download the matching `.tar.gz` and `SHA256SUMS` from the **same [release](https://github.com/Phalegethon/tawl/releases/latest)**:

| Mac | Archive suffix |
|---|---|
| Apple Silicon | `macos-arm64.tar.gz` |
| Intel | `macos-x86_64.tar.gz` |

For example, for the 0.2.0 Apple Silicon archive, calculate its checksum before extracting:

```sh
shasum -a 256 tawl-0.2.0-macos-arm64.tar.gz
```

Match the complete digest to that archive's line in the release's `SHA256SUMS`. Use the Intel filename on an Intel Mac. Continue only when they match, then extract into a new directory:

```sh
mkdir tawl-install
tar -xzf tawl-0.2.0-macos-arm64.tar.gz -C tawl-install
cd tawl-install
bash install.sh
export PATH="$HOME/.local/bin:$PATH"
tawl --version
tawl
```

The installer defaults to `~/.local`; `bash install.sh --prefix /absolute/custom/prefix` selects another location. If needed, add the printed PATH line to your shell configuration. The installer never edits shell files automatically.

Keep the included `uninstall.sh`. Installation creates an ownership receipt at `<prefix>/share/tawl/install.json`; keep it with the installation so `tawl update` and the uninstaller can recognize it. The updater verifies the release binary's SHA-256 digest, architecture and version before replacing the executable. Failed verification preserves the existing binary. It does not overwrite a Homebrew-managed executable or a source checkout.

Standalone update: `tawl update check`, then `tawl update`. Standalone uninstall, using the same prefix:

```sh
bash uninstall.sh --prefix "$HOME/.local"
```

The uninstaller preserves recordings, reports and unrelated files.

## Signing status

Current release binaries are **ad hoc signed and not Apple-notarized**. Developer ID signing and notarization are deferred. Homebrew manages installation and verifies the formula's checksums; it does not turn an ad hoc signature into Apple Developer ID signing or notarization. TAWL does not change Gatekeeper or remove quarantine attributes. You do not need an Apple Developer Program membership to use TAWL.

[Usage guide](usage.md) · [Maintainer distribution guide](distribution.md)
