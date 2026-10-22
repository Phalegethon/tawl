# Confirmed process closure — native safety boundary

October 22, 2026. This applies only to one user-selected process with verified ownership and application identity. No bulk termination, process-tree signalling, `SIGKILL`, privilege escalation or automatic background closure.

## Identity-bound operation

Swift validates live/fresh measurement, ownership, application identity and explicit confirmation. During preparation, C retains PID, OS start time, user, parent, executable path and audit token. The path's application family is matched again to the confirmation's application. Preparation lasts 30 seconds and is single-use; every submission attempt consumes it.

Native information is reread before sending. Changed identity, ownership, path or parent rejects the request. The final call is `proc_signal_with_audittoken(..., SIGTERM)`. There is no `kill(pid, ...)` fallback that targets only a numeric PID. An unreadable audit token leaves the operation blocked.

The token obtained through standard macOS SDK `task_name_for_pid` and `task_info(TASK_AUDIT_TOKEN)` also carries the PID generation. XNU's `proc_find_audit_token` checks that generation when acquiring the process reference, preventing PID reuse or a new executable under the same PID from redirecting old consent to a new target. [Apple XNU process identity](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_proc.c), [audit token retrieval](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/task.c).

`proc_signal_with_audittoken` returns zero on success and an errno value on failure. `proc_terminate` and `proc_terminate_with_audittoken` are not used: the OS may choose `SIGKILL` for processes it considers eligible for sudden termination. Here the signal is explicitly fixed to `SIGTERM`. [Apple libproc wrapper](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c), [XNU signal versus terminate behavior](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/proc_info.c).

## Protected targets

PID 0/1, TAWL itself and its ancestry; root, other users or changed privileges; OS paths/system processes; and unverifiable application paths cannot be terminated. Known database and virtualization processes are protected both by product classification and native path checks. Classification does not claim perfect knowledge of every program. The terminal allows MANUAL selection of an eligible application process without a recommendation. Advice never substitutes for authorization, and disappearing advice does not cancel explicit selection. The C API alone is not a recommendation engine.

## Outcome and limits

Signal acceptance does not establish exit. A separate read-only check reports the same identity as running, exited, changed or unreadable. Zombies count as exited. An unchanged PID with a changed executable produces “identity changed”; it does not establish closure of the entire application.

`SIGTERM` is not the macOS application's Quit command and does not guarantee a save prompt. Unsaved work may be lost. Stopping a helper can affect a tab, window or whole application; the application may restart it. A process may ignore the signal. TAWL never escalates to force termination.

## Validation

- `sh Tests/Native/test_process_control.sh` sends real SIGTERM only to its own application-like children with a 20-second failsafe. It covers start/token/path/user changes, timeout, repeated submission, self/ancestor protection, same-PID exec, ignored SIGTERM and protected paths.
- The Swift adapter tests application matching, cancellation, single submission and exit observation using its own compiled disposable application fixture. Existing user applications are not targets.
- A separate read-only check confirmed audit-token preparation on three existing user-application processes; none received a signal.

This checkpoint built with macOS SDK 27.0 and a macOS 15 deployment floor. No added installation, private SDK header, private proc_info constant, entitlement or administrator permission was used. Permission differences on other macOS versions fail closed at runtime.

October 22 manual-selection correction: the earlier “block without recommendation” rule kept users out of closure when an application total was large but every helper stayed below 2 GiB. Recommendation was separated from permission. A new real PTY test uses its own low-footprint application without advice: x → MANUAL → impact/confirmation → one SIGTERM → verified exit → comparison → four-chart HTML. Resources come from real system readings; no decrease is guaranteed or asserted.

## Terminal.app ancestry checks

Investigation of the Terminal.app/Warp difference found that native preparation treated a denied full BSD read anywhere in the ancestor chain as `PROTECTED` for every target. On a live root process, `PROC_PIDTBSDINFO` returned EPERM while `PROC_PIDT_SHORTBSDINFO` remained readable. A Terminal-like monitor → shell → root login → Terminal → launchd chain reproduced the old false block of an unrelated target.

Ancestor traversal now uses short BSD metadata only, validating full returned size, PID, valid parent, loops and depth. An unreadable chain still blocks but reports `ANCESTRY_UNAVAILABLE`. Full BSD, user, audit-token, application-path and single-use consent checks for the target are unchanged. Swift shows native preparation rejection as red BLOCKED with retry.

`Tests/Native/process_ancestry_test.c` covers the root bridge, actual ancestors and malformed/missing chains; the runner executes nine native test groups. Apple's [proc_info.h](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/sys/proc_info.h) defines the short BSD structure and operation. The user's original live Terminal.app chain was not captured, so its exact rejection point was not directly measured.
