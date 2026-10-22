/* Exercise the production protection boundary with a Terminal-like ancestry.
 * Only kernel reads and getpid are replaced; no process is signalled. */
#include <assert.h>
#include <errno.h>
#include <libproc.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <unistd.h>

enum { VALID, UNREADABLE, WRONG_PID, SHORT_RESULT, SELF_LOOP, CYCLE,
       ZERO_PARENT, NEGATIVE_PARENT, TOO_DEEP };
static int scenario = VALID;
static pid_t ancestry_getpid(void) { return 9000; }

static int ancestry_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int size) {
    (void)arg;
    /* Tawl -> shell -> root login -> Terminal -> launchd. Full BSD on root
     * login is denied just as it is on root-owned processes on the live Mac. */
    int parent = pid == 9000 ? 9001 : pid == 9001 ? 9002 :
                 pid == 9002 ? 9003 : pid == 9003 ? 1 : -1;
    if (scenario == TOO_DEEP && pid >= 9000 && pid < 10000) parent = pid + 1;
    if (parent < 0) { errno = ESRCH; return 0; }
    if (flavor == PROC_PIDTBSDINFO) {
        if (pid == 9002) { errno = EPERM; return 0; }
        assert(size == sizeof(struct proc_bsdinfo));
        struct proc_bsdinfo info = {0};
        info.pbi_pid = pid; info.pbi_ppid = parent;
        memcpy(buffer, &info, sizeof(info));
        return sizeof(info);
    }
    assert(flavor == PROC_PIDT_SHORTBSDINFO);
    assert(size == sizeof(struct proc_bsdshortinfo));
    struct proc_bsdshortinfo info = {0};
    info.pbsi_pid = pid; info.pbsi_ppid = parent;
    if (pid == 9002) {
        if (scenario == UNREADABLE) { errno = EPERM; return 0; }
        if (scenario == WRONG_PID) info.pbsi_pid = 42;
        if (scenario == SELF_LOOP) info.pbsi_ppid = pid;
        if (scenario == CYCLE) info.pbsi_ppid = 9000;
        if (scenario == ZERO_PARENT) info.pbsi_ppid = 0;
        if (scenario == NEGATIVE_PARENT) info.pbsi_ppid = UINT32_MAX;
    }
    memcpy(buffer, &info, sizeof(info));
    return pid == 9002 && scenario == SHORT_RESULT ? sizeof(info) - 1 : sizeof(info);
}

#define getpid ancestry_getpid
#define proc_pidinfo ancestry_pidinfo
#include "../../Sources/CTawl/process_control.c"
#undef getpid
#undef proc_pidinfo

int main(void) {
    nb_process_control_ticket ticket = {0};
    /* An unrelated target must get as far as its own identity read, which this
     * fixture intentionally leaves unavailable. It must not be 'protected'. */
    assert(nb_process_control_prepare(43005, 1, &ticket) == NB_CONTROL_UNAVAILABLE);
    assert(ticket.valid == 0);
    puts("PASS root login full-BSD denial does not protect unrelated targets");

    const int ancestors[] = {9000, 9001, 9002, 9003};
    for (unsigned i = 0; i < sizeof(ancestors) / sizeof(ancestors[0]); ++i) {
        assert(nb_process_control_prepare(ancestors[i], 1, &ticket) == NB_CONTROL_PROTECTED);
        assert(ticket.valid == 0);
    }
    puts("PASS self, shell, root login and terminal beyond root stay protected");

    for (scenario = UNREADABLE; scenario <= TOO_DEEP; ++scenario) {
        assert(nb_process_control_prepare(43005, 1, &ticket) == NB_CONTROL_ANCESTRY_UNAVAILABLE);
        assert(ticket.valid == 0);
    }
    puts("PASS unreadable, wrong PID, partial, invalid, cyclic and deep ancestry fail closed");
    return 0;
}
