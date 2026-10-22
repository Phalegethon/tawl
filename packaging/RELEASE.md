# Preparing a release

The compiled `tawl --version` output is the version authority. The release
workflow checks it against the pushed `vX.Y.Z` tag or manual version input.
Both macOS 15 runners build and test independently: `macos-15` for Apple Silicon,
`macos-15-intel` for Intel. Both jobs select Xcode 16.4 and print the Swift
toolchain version. `MACOSX_DEPLOYMENT_TARGET=15.0` keeps the minimum OS explicit.

The workflow creates **a draft only**. It refuses to replace a published release
or to attach binaries to an existing tag that points to a different commit.
Review both build jobs, both signing status files and the final checksums before
publishing the draft in GitHub Releases. The workflow does not publish it or
change the Homebrew formula in the repository automatically.

Final assets for each architecture are:

- `tawl-X.Y.Z-macos-arm64` / `tawl-X.Y.Z-macos-x86_64`: raw executable used by the updater.
- The same names with `.tar.gz`: executable, install/uninstall scripts, MIT license and short instructions.
- `LICENSE`: the MIT notice accompanying raw executable downloads.
- `SHA256SUMS`: digests of both raw executables, both archives and the license, computed after signing.
- `SIGNING-arm64.txt` / `SIGNING-x86_64.txt`: the actual signing result for each build.
- `tawl.rb`: generated Homebrew formula using the exact archive digests; it installs the binary and retains the license in `pkgshare`.

Keep the release assets immutable after publishing. A release version and its
checksums must identify one set of binaries.

## Signing

Without signing secrets, CI applies an **ad-hoc signature**. This does not
authenticate the developer and is **not notarization**. macOS may block a build
downloaded through a browser. No script removes quarantine or changes Gatekeeper.

For Developer ID signing, configure repository Actions secrets:

- `TAWL_SIGNING_CERTIFICATE_BASE64`: base64 of a `.p12` certificate and private key.
- `TAWL_SIGNING_CERTIFICATE_PASSWORD`: password for the `.p12` file.
- `TAWL_SIGNING_IDENTITY`: full `Developer ID Application: …` identity.

To also notarize, configure all three:

- `TAWL_APPLE_ID`
- `TAWL_APPLE_APP_PASSWORD`: an Apple app-specific password.
- `TAWL_APPLE_TEAM_ID`

The script creates a temporary keychain, signs with the hardened runtime,
submits a ZIP to Apple and waits for `Accepted`. It deletes the temporary
keychain and certificate afterward. A raw command-line executable cannot carry
a stapled ticket; Gatekeeper may need network access to find its notarization.
Developer ID and Apple service paths require these credentials and are not
covered by local tests without them.

## Homebrew tap

After reviewing the generated `tawl.rb`, place it at `Formula/tawl.rb` in the
default branch and publish the matching release. Do not substitute placeholder
checksums or source-build fallback URLs. Until the release and formula are
available, the tap installation is not ready.

```sh
brew tap phalegethon/tawl https://github.com/Phalegethon/tawl
brew install phalegethon/tawl/tawl
brew test phalegethon/tawl/tawl
```

The explicit URL is necessary because this tap shares the `tawl` repository
instead of a conventionally named `homebrew-tawl` repository. Homebrew owns those
installs; use `brew upgrade` / `brew uninstall`, not the standalone scripts.

Commit the generated formula to the default branch **before publishing**. The
`Published Homebrew smoke test` workflow runs on release publication, or manually
with a version input, on disposable Apple Silicon and Intel runners. It installs
the real public formula, checks the version, update metadata and one status sample,
then uninstalls. This does not modify the maintainer's local Homebrew installation.

## Local packaging and checks

```sh
make test test-distribution build
./scripts/package-release.sh --binary ./tawl --output ./work/release
```

Packaging refuses to overwrite existing assets. Use a fresh output directory
for a new candidate. `make install PREFIX='/absolute/test prefix'` installs the
locally built executable. `make uninstall PREFIX='/absolute/test prefix'`
removes only an owned standalone executable and its receipt. Tests use temporary
prefixes and compiled fixtures; end users do not need Python or a compiler to
install a prebuilt archive.
