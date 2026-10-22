"""Filesystem integration checks; only tests/build tools need Python and clang."""
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(platform.system() == "Darwin", "macOS distribution")
class DistributionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixtures = tempfile.TemporaryDirectory(prefix="tawl fixtures ")
        cls.fixture_dir = Path(cls.fixtures.name).resolve()
        source = cls.fixture_dir / "fixture.c"
        source.write_text('#include <stdio.h>\nint main(void) { puts("tawl 0.1.0"); return 0; }\n')
        cls.binary = cls.fixture_dir / "tawl fixture"
        subprocess.run(["cc", str(source), "-o", str(cls.binary)], check=True, capture_output=True)
        source.write_text('#include <stdio.h>\nint main(void) { puts("tawl 0.1.1"); return 0; }\n')
        cls.updated_binary = cls.fixture_dir / "updated tawl fixture"
        subprocess.run(["cc", str(source), "-o", str(cls.updated_binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixtures.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="tawl install ")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.prefix = self.directory / "prefix with spaces"

    def run_script(self, name, *args, expected=0, env=None, cwd=None):
        result = subprocess.run(["/bin/bash", str(ROOT / "scripts" / name), *map(str, args)],
                                text=True, capture_output=True, env=env, cwd=cwd)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def install(self, **kwargs):
        return self.run_script("install.sh", "--prefix", self.prefix, "--binary", self.binary, **kwargs)

    def test_install_spaces_creates_executable_receipt_and_path_instruction(self):
        result = self.install()
        target = self.prefix / "bin/tawl"
        self.assertEqual(subprocess.check_output([target, "--version"], text=True).strip(), "tawl 0.1.0")
        self.assertEqual(hashlib.sha256(target.read_bytes()).digest(), hashlib.sha256(self.binary.read_bytes()).digest())
        receipt = json.loads((self.prefix / "share/tawl/install.json").read_text())
        self.assertEqual(receipt, {"schemaVersion": 1, "method": "standalone", "repository": "Phalegethon/tawl"})
        self.assertIn("export PATH=", result.stdout)
        self.assertIn("$PATH", result.stdout)

    def test_install_refuses_unowned_binary_and_preserves_bytes(self):
        target = self.prefix / "bin/tawl"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"unrelated executable")
        self.install(expected=1)
        self.assertEqual(target.read_bytes(), b"unrelated executable")
        self.assertFalse((self.prefix / "share/tawl/install.json").exists())

    def test_install_refuses_symlink_directory(self):
        self.prefix.mkdir()
        elsewhere = self.directory / "elsewhere"
        elsewhere.mkdir()
        (self.prefix / "bin").symlink_to(elsewhere, target_is_directory=True)
        self.install(expected=1)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_install_refuses_symlink_target(self):
        target = self.prefix / "bin/tawl"
        target.parent.mkdir(parents=True)
        victim = self.directory / "victim"
        victim.write_text("preserve")
        target.symlink_to(victim)
        self.install(expected=1)
        self.assertEqual(victim.read_text(), "preserve")

    def test_invalid_source_is_not_executed(self):
        source = self.directory / "script"
        sentinel = self.directory / "executed"
        source.write_text(f"#!/bin/sh\ntouch '{sentinel}'\necho 'tawl 0.1.0'\n")
        source.chmod(0o755)
        self.run_script("install.sh", "--prefix", self.prefix, "--binary", source, expected=1)
        self.assertFalse(sentinel.exists())

    def test_owned_reinstall_and_uninstall_preserve_user_records(self):
        self.install()
        records = self.prefix / "share/tawl/my-recording.tawl"
        records.write_bytes(b"user recording")
        self.install()
        self.run_script("uninstall.sh", "--prefix", self.prefix)
        self.assertFalse((self.prefix / "bin/tawl").exists())
        self.assertFalse((self.prefix / "share/tawl/install.json").exists())
        self.assertEqual(records.read_bytes(), b"user recording")

    def test_upgrade_replaces_atomically_without_mutating_open_binary(self):
        self.install()
        target = self.prefix / "bin/tawl"
        original_bytes = target.read_bytes()
        with target.open("rb") as prior_binary:
            self.run_script("install.sh", "--prefix", self.prefix, "--binary", self.updated_binary)
            self.assertEqual(prior_binary.read(), original_bytes)
        self.assertEqual(subprocess.check_output([target, "--version"], text=True).strip(), "tawl 0.1.1")

    def test_uninstall_refuses_wrong_repository_receipt(self):
        self.install()
        receipt = self.prefix / "share/tawl/install.json"
        receipt.write_text('{"schemaVersion":1,"method":"standalone","repository":"other/tool"}')
        self.run_script("uninstall.sh", "--prefix", self.prefix, expected=1)
        self.assertTrue((self.prefix / "bin/tawl").exists())
        self.assertTrue(receipt.exists())

    def test_uninstall_refuses_changed_non_macho_binary(self):
        self.install()
        target = self.prefix / "bin/tawl"
        target.write_text("unrelated replacement")
        self.run_script("uninstall.sh", "--prefix", self.prefix, expected=1)
        self.assertEqual(target.read_text(), "unrelated replacement")

    def test_package_names_from_binary_version_and_matches_checksums(self):
        output = self.directory / "release files"
        self.run_script("package-release.sh", "--binary", self.binary, "--output", output)
        arch = platform.machine()
        stem = f"tawl-0.1.0-macos-{arch}"
        self.assertEqual((output / stem).read_bytes(), self.binary.read_bytes())
        with tarfile.open(output / f"{stem}.tar.gz") as archive:
            names = set(archive.getnames())
            self.assertTrue({"tawl", "install.sh", "uninstall.sh", "README.txt", "LICENSE"} <= names)
            self.assertEqual(archive.extractfile("LICENSE").read(), (ROOT / "LICENSE").read_bytes())
        for line in (output / "SHA256SUMS").read_text().splitlines():
            digest, filename = line.split("  ", 1)
            self.assertEqual(digest, hashlib.sha256((output / filename).read_bytes()).hexdigest())

    def test_formula_uses_archive_digests_and_retains_mit_notice(self):
        sums = self.directory / "SHA256SUMS"
        sums.write_text("c" * 64 + "  tawl-1.2.3-macos-arm64\n" +
                        "d" * 64 + "  tawl-1.2.3-macos-x86_64\n" +
                        "a" * 64 + "  tawl-1.2.3-macos-arm64.tar.gz\n" +
                        "b" * 64 + "  tawl-1.2.3-macos-x86_64.tar.gz\n")
        formula = self.directory / "tawl.rb"
        self.run_script("generate-formula.sh", "--version", "1.2.3", "--checksums", sums,
                        "--output", formula)
        body = formula.read_text()
        self.assertIn("/v1.2.3/tawl-1.2.3-macos-arm64.tar.gz", body)
        self.assertIn("/v1.2.3/tawl-1.2.3-macos-x86_64.tar.gz", body)
        self.assertIn('sha256 "' + "a" * 64 + '"', body)
        self.assertIn('sha256 "' + "b" * 64 + '"', body)
        self.assertIn('license "MIT"', body)
        self.assertIn('bin.install "tawl"', body)
        self.assertIn('pkgshare.install "LICENSE"', body)
        subprocess.run(["ruby", "-c", str(formula)], check=True, capture_output=True)

    @unittest.skipUnless(shutil.which("brew"), "Homebrew DSL validation requires brew")
    def test_shipped_and_generated_formula_load_in_homebrew(self):
        sums = self.directory / "SHA256SUMS"
        sums.write_text("a" * 64 + "  tawl-1.2.3-macos-arm64.tar.gz\n" +
                        "b" * 64 + "  tawl-1.2.3-macos-x86_64.tar.gz\n")
        generated = self.directory / "tawl.rb"
        self.run_script("generate-formula.sh", "--version", "1.2.3", "--checksums", sums,
                        "--output", generated)
        # Ruby syntax checks alone cannot detect invalid Homebrew DSL combinations.
        ruby = '''require "formula"
load ARGV.fetch(0)
f = Tawl.new("tawl", Pathname(ARGV.fetch(0)), :stable)
abort "macOS must be supported" unless f.supports_macos?
abort "Linux must be rejected" if f.supports_linux?
abort "macOS 15 minimum missing" unless f.requirements.any? { |r|
  r.is_a?(MacOSRequirement) && r.version.to_s == "15"
}
'''
        for formula in (ROOT / "Formula/tawl.rb", generated):
            with self.subTest(formula=formula):
                result = subprocess.run(["brew", "ruby", "-e", ruby, str(formula)],
                                        text=True, capture_output=True,
                                        env=dict(os.environ, HOMEBREW_NO_AUTO_UPDATE="1",
                                                 HOMEBREW_NO_ANALYTICS="1"))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_formula_refuses_missing_architecture_and_preserves_previous_file(self):
        sums = self.directory / "SHA256SUMS"
        sums.write_text("a" * 64 + "  tawl-1.2.3-macos-arm64.tar.gz\n")
        formula = self.directory / "tawl.rb"
        formula.write_text("preserve previous formula")
        self.run_script("generate-formula.sh", "--version", "1.2.3", "--checksums", sums,
                        "--output", formula, expected=1)
        self.assertEqual(formula.read_text(), "preserve previous formula")

    def test_signing_without_credentials_is_explicitly_ad_hoc_and_runnable(self):
        binary = self.directory / "signed fixture"
        shutil.copy2(self.binary, binary)
        status = self.directory / "signing.txt"
        self.run_script("sign-release.sh", "--binary", binary, "--status-file", status)
        self.assertIn("ad-hoc", status.read_text())
        self.assertIn("not notarized", status.read_text())
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", str(binary)], check=True, capture_output=True)
        self.assertEqual(subprocess.check_output([binary, "--version"], text=True).strip(), "tawl 0.1.0")

    def release_environment(self, tag_commit, draft=True):
        mocks = self.directory / "commands"
        mocks.mkdir()
        git = mocks / "git"
        git.write_text('#!/bin/bash\ncase "$1" in\n'
                       'ls-remote) [[ -z "$MOCK_TAG_COMMIT" ]] || printf "%s\\trefs/tags/v0.1.0\\n" "$MOCK_TAG_COMMIT" ;;\n'
                       'rev-parse) printf "%s\\n" "$MOCK_TAG_COMMIT" ;;\n'
                       'fetch) exit 0 ;;\nesac\n')
        gh = mocks / "gh"
        gh.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$MOCK_LOG"\n'
                      'if [[ "$1 $2" == "release view" ]]; then printf \'{"isDraft":%s}\\n\' "$MOCK_IS_DRAFT"; fi\n')
        git.chmod(0o755)
        gh.chmod(0o755)
        assets = self.directory / "assets"
        assets.mkdir()
        for name in ["SHA256SUMS", "tawl.rb", "LICENSE", "release-notes.md", "SIGNING-arm64.txt", "SIGNING-x86_64.txt",
                     "tawl-0.1.0-macos-arm64", "tawl-0.1.0-macos-arm64.tar.gz",
                     "tawl-0.1.0-macos-x86_64", "tawl-0.1.0-macos-x86_64.tar.gz"]:
            (assets / name).write_text("fixture")
        log = self.directory / "api.log"
        environment = {**os.environ, "PATH": f"{mocks}:{os.environ['PATH']}",
                       "MOCK_TAG_COMMIT": tag_commit, "MOCK_LOG": str(log),
                       "MOCK_IS_DRAFT": "true" if draft else "false"}
        return assets, log, environment

    def test_draft_release_refuses_assets_from_different_tag_commit(self):
        assets, log, environment = self.release_environment("a" * 40)
        self.run_script("prepare-draft-release.sh", "--tag", "v0.1.0", "--commit", "b" * 40,
                        "--assets", assets, expected=1, env=environment)
        self.assertFalse(log.exists(), "No GitHub mutation is allowed when the tag points elsewhere")

    def test_draft_release_sets_target_for_untagged_existing_draft(self):
        assets, log, environment = self.release_environment("")
        self.run_script("prepare-draft-release.sh", "--tag", "v0.1.0", "--commit", "b" * 40,
                        "--assets", assets, env=environment)
        calls = log.read_text()
        self.assertIn("release edit v0.1.0 --draft --target " + "b" * 40, calls)
        self.assertIn("release upload v0.1.0", calls)
        self.assertIn(str(assets / "LICENSE"), calls)

    def test_draft_release_never_mutates_published_release(self):
        assets, log, environment = self.release_environment("a" * 40, draft=False)
        self.run_script("prepare-draft-release.sh", "--tag", "v0.1.0", "--commit", "a" * 40,
                        "--assets", assets, expected=1, env=environment)
        calls = log.read_text()
        self.assertNotIn("release edit", calls)
        self.assertNotIn("release upload", calls)

    def annotated_remote_with_lightweight_checkout_tag(self, different_commit=False):
        def git(*arguments, cwd=None):
            result = subprocess.run(["git", *map(str, arguments)], cwd=cwd,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()

        remote = self.directory / "remote.git"
        source = self.directory / "source"
        checkout = self.directory / "checkout"
        git("init", "--bare", remote)
        git("init", "--initial-branch=main", source)
        git("config", "user.name", "Distribution Test", cwd=source)
        git("config", "user.email", "distribution-test@example.invalid", cwd=source)
        git("config", "core.hooksPath", "/dev/null", cwd=source)
        git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Fixture release", cwd=source)
        release_commit = git("rev-parse", "HEAD", cwd=source)
        git("-c", "tag.gpgsign=false", "tag", "-a", "v0.1.0", "-m", "Annotated release", cwd=source)
        git("push", remote, "HEAD:refs/heads/main", "refs/tags/v0.1.0", cwd=source)
        if different_commit:
            git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-m", "Different build", cwd=source)
            git("push", remote, "HEAD:refs/heads/main", cwd=source)
        git("clone", "--no-tags", "--branch", "main", remote, checkout)
        build_commit = git("rev-parse", "HEAD", cwd=checkout)
        git("update-ref", "refs/tags/v0.1.0", build_commit, cwd=checkout)
        self.assertEqual(git("cat-file", "-t", "refs/tags/v0.1.0", cwd=checkout), "commit")
        self.assertEqual(git("--git-dir", remote, "cat-file", "-t", "refs/tags/v0.1.0"), "tag")
        return checkout, build_commit, release_commit, git

    def test_annotated_remote_tag_accepts_matching_lightweight_checkout_tag_without_replacing_it(self):
        assets, log, environment = self.release_environment("")
        (self.directory / "commands/git").unlink()  # Exercise real local Git; GitHub remains offline.
        checkout, build_commit, release_commit, git = self.annotated_remote_with_lightweight_checkout_tag()
        self.assertEqual(build_commit, release_commit)
        self.run_script("prepare-draft-release.sh", "--tag", "v0.1.0", "--commit", build_commit,
                        "--assets", assets, env=environment, cwd=checkout)
        self.assertIn("release upload v0.1.0", log.read_text())
        self.assertEqual(git("cat-file", "-t", "refs/tags/v0.1.0", cwd=checkout), "commit")
        self.assertEqual(git("rev-parse", "refs/tags/v0.1.0", cwd=checkout), build_commit)

    def test_annotated_remote_tag_rejects_different_build_without_replacing_local_tag(self):
        assets, log, environment = self.release_environment("")
        (self.directory / "commands/git").unlink()
        checkout, build_commit, release_commit, git = self.annotated_remote_with_lightweight_checkout_tag(True)
        self.assertNotEqual(build_commit, release_commit)
        result = self.run_script("prepare-draft-release.sh", "--tag", "v0.1.0", "--commit", build_commit,
                                 "--assets", assets, expected=1, env=environment, cwd=checkout)
        self.assertIn("existing tag does not point to the commit", result.stderr)
        self.assertFalse(log.exists())
        self.assertEqual(git("cat-file", "-t", "refs/tags/v0.1.0", cwd=checkout), "commit")
        self.assertEqual(git("rev-parse", "refs/tags/v0.1.0", cwd=checkout), build_commit)


if __name__ == "__main__":
    unittest.main()
