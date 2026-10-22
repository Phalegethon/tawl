#!/usr/bin/env python3
"""Prove a Homebrew-installed release opens its real live TUI from outside Git.

The default monitor probe never builds, installs, changes PATH, or uses fixtures.
The opt-in --confirm-update mode is restricted to disposable GitHub runners and
confirms the installed updater's prompt. Both modes save results.json and bounded
terminal.ansi even on failure. Native macOS ARM/Intel, Python standard library only.
"""

import argparse
import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time


WIDTH, HEIGHT = 140, 40
MAX_OUTPUT_BYTES = 2 * 1024 * 1024
FRAME_START = b"\x1b[1;1H"
ALT_ENTER, ALT_EXIT = b"\x1b[?1049h", b"\x1b[?1049l"
CSI = re.compile(rb"\x1b\[[0-?]*[ -/]*[@-~]")
ROW = re.compile(rb"\x1b\[(\d+);1H")


class ProbeFailure(Exception):
    pass


def require(condition, message):
    # Do not use assert: python -O must not turn a failed probe into success.
    if not condition:
        raise ProbeFailure(message)


def within(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def command(argv, cwd, env):
    result = subprocess.run(argv, cwd=cwd, env=env, capture_output=True,
                            text=True, timeout=10, check=False)
    require(result.returncode == 0,
            f"{argv!r} exited {result.returncode}: {result.stderr[:1000].strip()}")
    return result.stdout.strip()


def installed_binary(args, cwd, env, expected_version):
    shell = lambda script: command(["/bin/zsh", "-f", "-c", script], cwd, env)
    require("PATH" in env, "An inherited PATH is required")
    require(shell('printf "%s" "$PATH"') == env["PATH"],
            "zsh changed the inherited PATH")
    resolved = shell("command -v tawl")
    expected_bin = Path(args.brew_prefix).absolute() / "bin" / "tawl"
    require(resolved == str(expected_bin),
            f"command -v tawl resolved {resolved!r}, expected {str(expected_bin)!r}")
    binary = Path(resolved).resolve(strict=True)
    cellar = (Path(args.brew_prefix) / "Cellar" / "tawl").resolve()
    require(within(binary, cellar) and binary.is_file(),
            f"Installed binary {binary} is not under {cellar}")
    version = shell("tawl --version")
    require(version == f"tawl {expected_version}",
            f"Unexpected version: {version!r}")
    machine = command(["/usr/bin/uname", "-m"], cwd, env)
    require(machine == args.expected_architecture,
            f"Runner uname is {machine}, expected {args.expected_architecture}")
    translated = subprocess.run(
        ["/usr/sbin/sysctl", "-in", "sysctl.proc_translated"], cwd=cwd,
        env=env, capture_output=True, text=True, timeout=10, check=False)
    require(translated.stdout.strip() != "1", "Rosetta execution is not native runner evidence")
    file_info = command(["/usr/bin/file", "-L", resolved], cwd, env)
    require("Mach-O" in file_info and "executable" in file_info,
            f"Expected an installed Mach-O executable: {file_info}")
    architectures = command(["/usr/bin/lipo", "-archs", resolved], cwd, env).split()
    require(args.expected_architecture in architectures,
            f"Installed architectures {architectures} lack {args.expected_architecture}")
    receipt_path = binary.parent.parent / "INSTALL_RECEIPT.json"
    receipt = json.loads(receipt_path.read_text())
    tap = receipt.get("source", {}).get("tap")
    require(tap == "phalegethon/tawl", f"Unexpected installation receipt tap: {tap!r}")
    return dict(command_path=resolved, binary_realpath=str(binary), version=version,
                runner_architecture=machine, binary_architectures=architectures,
                file=file_info, path_unmodified=True, rosetta=False,
                receipt=str(receipt_path), receipt_tap=tap)


def complete_frames(data):
    """Decode complete positioned frames, never counting PTY read boundaries."""
    frames = []
    for raw in data.split(FRAME_START)[1:]:
        matches = list(ROW.finditer(FRAME_START + raw))
        if [int(match[1]) for match in matches] != list(range(1, HEIGHT + 1)):
            continue
        rows = []
        whole = FRAME_START + raw
        for index, match in enumerate(matches):
            end = matches[index + 1].start() if index + 1 < len(matches) else len(whole)
            # Invalid UTF-8 means a read split a character; wait for more bytes.
            try:
                rows.append(CSI.sub(b"", whole[match.end():end]).decode("utf-8"))
            except UnicodeDecodeError:
                break
        if len(rows) == HEIGHT and len(rows[-1]) >= WIDTH:
            frames.append(rows)
    return frames


def frame_evidence(rows):
    header = rows[0]
    require(re.search(r"\bTAWL\s+/ LIVE\b", header), "Live TAWL header missing")
    require("SESSION MEMORY" in header, "Expected unrecorded live session")
    timestamp = re.search(r"\b(\d{2}:\d{2}:\d{2})\b", header)
    require(timestamp is not None, "Live sample timestamp missing")
    panels = "\n".join(rows[3:]).split("╭ APPLICATIONS", 1)[0]
    require("╭ CPU · " in panels, "CPU hardware panel missing")
    require("MEMORY " in panels, "Memory health panel missing")
    processes = re.search(r"(\d+)/(\d+) processes", rows[1])
    require(processes is not None and 0 < int(processes[1]) <= int(processes[2]),
            "Real collector did not render readable processes")
    count = re.search(r"\b(\d+) samples\b", "\n".join(rows[-4:]))
    require(count is not None, "Session sample count missing")
    return dict(sample_count=int(count[1]), timestamp=timestamp[1],
                readable_processes=int(processes[1]), total_processes=int(processes[2]),
                live_header=True, cpu_panel=True, memory_panel=True)


def run_terminal(cwd, env, summary, output, confirm_update=False):
    master, slave = pty.openpty()
    child = None
    started = time.monotonic()
    baseline = None

    def drain(seconds=0.1, enforce_limit=True):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], min(0.05, max(0, deadline - time.monotonic())))
            if not ready:
                continue
            try:
                chunk = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    return
                raise
            if not chunk:
                return
            remaining = MAX_OUTPUT_BYTES - len(output)
            output.extend(chunk[:remaining])
            if len(chunk) > remaining:
                summary["ansi_truncated"] = True
                if enforce_limit:
                    raise ProbeFailure("Terminal output exceeded the 2 MiB evidence limit")

    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", HEIGHT, WIDTH, 0, 0))
        baseline = termios.tcgetattr(slave)
        child = subprocess.Popen(summary["shell"],
                                 cwd=cwd, env=env, stdin=slave, stdout=slave,
                                 stderr=slave, start_new_session=True, close_fds=True)
        summary["child_pid"] = child.pid
        if confirm_update:
            prompt_deadline = started + 120
            while b"[y/N]" not in output and time.monotonic() < prompt_deadline:
                drain()
                require(child.poll() is None, "Updater exited before its confirmation prompt")
            require(b"[y/N]" in output, "Updater confirmation prompt did not arrive within 120 seconds")
            summary["confirmation_prompt_observed"] = True
            os.write(master, b"y\r")
            summary["keys_sent"] = ["y", "Enter"]
            quit_deadline = started + 900
        else:
            evidence = []
            seen = 0
            deadline = started + 30
            while time.monotonic() < deadline:
                drain()
                frames = complete_frames(bytes(output))
                for rows in frames[seen:]:
                    entry = frame_evidence(rows)
                    entry["observed_after_seconds"] = round(time.monotonic() - started, 3)
                    if evidence:
                        require(entry["sample_count"] >= evidence[-1]["sample_count"],
                                "Session sample count moved backwards")
                    if not evidence or entry["sample_count"] > evidence[-1]["sample_count"]:
                        evidence.append(entry)
                    seen += 1
                summary["rendered_frames"] = seen
                summary["samples"] = evidence
                require(child.poll() is None, "Installed TUI exited before q was sent")
                if len(evidence) >= 3:
                    break
            require(len(evidence) >= 3, "Timed out waiting for three advancing live samples")
            require(len({entry["timestamp"] for entry in evidence}) >= 3,
                    "Sample timestamps did not advance")
            require(time.monotonic() - started >= 3,
                    "Live samples arrived implausibly quickly for the default interval")
            summary["raw_mode_observed"] = not bool(termios.tcgetattr(slave)[3] & (termios.ICANON | termios.ECHO))
            require(summary["raw_mode_observed"], "TUI never enabled raw terminal input")
            require(ALT_ENTER in output and ALT_EXIT not in output,
                    "TUI did not remain in the alternate screen before q")
            os.write(master, b"q")
            summary["keys_sent"] = ["q"]
            quit_deadline = time.monotonic() + 5
        while child.poll() is None and time.monotonic() < quit_deadline:
            drain()
        require(child.poll() is not None,
                "Updater exceeded 900 seconds" if confirm_update else "TUI did not exit within 5 seconds of q")
        drain(0.2)
        summary["exit_code"] = child.returncode
        summary["termios_restored"] = termios.tcgetattr(slave) == baseline
        require(child.returncode == 0, f"Installed command exited {child.returncode}")
        if not confirm_update:
            summary["alternate_screen_entered"] = output.count(ALT_ENTER) == 1
            summary["alternate_screen_exited"] = output.count(ALT_EXIT) == 1
            require(summary["alternate_screen_entered"] and summary["alternate_screen_exited"],
                    "Expected exactly one alternate-screen entry and exit")
            require(output.find(ALT_EXIT) > output.rfind(FRAME_START),
                    "Alternate screen was not restored after the final frame")
        require(summary["termios_restored"], "Installed command did not restore original termios")
    finally:
        # Signal this test's new process group, never a workload selected from
        # the TUI. Swift Process may detach brew into another group: on update
        # failure the disposable runner must be discarded, not reused for more
        # package mutations. Drain while waiting to avoid pipe stalls.
        if child is not None and child.poll() is None:
            summary["forced_cleanup"] = True
            if confirm_update:
                summary["detached_update_descendants_cleanup_verified"] = False
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                drain(enforce_limit=False)
                # Reap an exited leader before signalling remaining members;
                # macOS reports EPERM for a process group with only a zombie.
                child.poll()
            try:
                # The leader may have exited while an updater descendant is
                # still alive; the dedicated process group remains ours.
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            child.wait(timeout=3)
        if child is not None:
            drain(0.1, enforce_limit=False)
            summary.setdefault("exit_code", child.returncode)
        if baseline is not None:
            summary.setdefault("termios_restored", termios.tcgetattr(slave) == baseline)
        os.close(master)
        os.close(slave)
        summary["duration_seconds"] = round(time.monotonic() - started, 3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--expected-architecture", required=True, choices=("arm64", "x86_64"))
    parser.add_argument("--brew-prefix", required=True)
    parser.add_argument("--output", required=True, type=Path, help="Evidence directory")
    parser.add_argument("--confirm-update", action="store_true",
                        help="Confirm tawl update on a disposable GitHub-hosted runner")
    parser.add_argument("--previous-version", help="Required installed version before --confirm-update")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    summary = dict(status="failed", expected_version=args.expected_version,
                   expected_architecture=args.expected_architecture,
                   brew_prefix=args.brew_prefix, mode="update" if args.confirm_update else "monitor",
                   shell=["/bin/zsh", "-f", "-c", "exec tawl update" if args.confirm_update else "exec tawl"],
                   terminal=dict(columns=WIDTH, rows=HEIGHT, term="xterm-256color"),
                   keys_sent=[], samples=[], ansi_truncated=False, forced_cleanup=False)
    output = bytearray()
    exit_code = 1
    try:
        require(sys.platform == "darwin", "Installed TUI probe requires macOS")
        require(Path(args.brew_prefix).is_absolute(), "--brew-prefix must be absolute")
        if args.confirm_update:
            require(os.environ.get("GITHUB_ACTIONS") == "true" and
                    os.environ.get("RUNNER_ENVIRONMENT") == "github-hosted",
                    "--confirm-update requires a disposable GitHub-hosted Actions runner")
            require(bool(args.previous_version), "--confirm-update requires --previous-version")
            require(args.previous_version != args.expected_version,
                    "Update proof requires different previous and expected versions")
            summary["previous_version"] = args.previous_version
        else:
            require(args.previous_version is None, "--previous-version requires --confirm-update")
        env = os.environ.copy()
        for name in ("TAWL_LANG", "NO_COLOR"):
            env.pop(name, None)
        env.update(TERM="xterm-256color", TAWL_NO_UPDATE_CHECK="1")
        summary["environment"] = dict(unset=["TAWL_LANG", "NO_COLOR"],
                                      TERM=env["TERM"], TAWL_NO_UPDATE_CHECK="1")
        checkout = Path(__file__).resolve().parents[2]
        # Explicit /private/tmp prevents TMPDIR from placing the run in checkout.
        with tempfile.TemporaryDirectory(prefix="tawl-installed-", dir="/private/tmp") as temporary:
            cwd = Path(temporary).resolve()
            require(not within(cwd, checkout), "Probe cwd must be outside the checkout")
            summary.update(cwd=str(cwd), outside_checkout=True)
            summary["installation"] = installed_binary(
                args, cwd, env, args.previous_version if args.confirm_update else args.expected_version)
            run_terminal(cwd, env, summary, output, confirm_update=args.confirm_update)
            if args.confirm_update:
                summary["installation_after_update"] = installed_binary(args, cwd, env, args.expected_version)
        summary["status"] = "passed"
        exit_code = 0
    except (Exception, KeyboardInterrupt) as error:
        summary["error"] = f"{type(error).__name__}: {error}"
    finally:
        summary["ansi_bytes"] = len(output)
        summary["artifacts"] = dict(ansi=str(args.output / "terminal.ansi"),
                                    json=str(args.output / "results.json"))
        (args.output / "terminal.ansi").write_bytes(output)
        (args.output / "results.json").write_text(json.dumps(summary, indent=2) + "\n")
        print(json.dumps(summary, indent=2))
    return exit_code


if __name__ == "__main__":
    def interrupted(signum, _frame):
        raise ProbeFailure(f"Interrupted by signal {signum}")

    # Cancellation still executes the PTY's finally block and writes failure
    # artifacts. SIGINT already raises KeyboardInterrupt and uses the same path.
    signal.signal(signal.SIGTERM, interrupted)
    sys.exit(main())
