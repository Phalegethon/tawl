#include "ProcessControl.h"
#include <errno.h>
#include <libproc.h>
#include <mach/mach.h>
#include <signal.h>
#include <stddef.h>
#include <string.h>
#include <strings.h>
#include <sys/proc.h>
#include <sys/proc_info.h>
#include <time.h>
#include <unistd.h>

static double monotonic_seconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
    return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
}

static int read_bsd(pid_t pid, struct proc_bsdinfo *info) {
    memset(info, 0, sizeof(*info));
    errno = 0;
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info)) == sizeof(*info);
}

static uint64_t start_time(const struct proc_bsdinfo *info) {
    return info->pbi_start_tvsec * UINT64_C(1000000) + info->pbi_start_tvusec;
}

static int read_audit(pid_t pid, audit_token_t *token) {
    task_name_t task = MACH_PORT_NULL;
    if (task_name_for_pid(mach_task_self(), pid, &task) != KERN_SUCCESS) return 0;
    mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    kern_return_t result = task_info(task, TASK_AUDIT_TOKEN, (task_info_t)token, &count);
    mach_port_deallocate(mach_task_self(), task);
    return result == KERN_SUCCESS && count == TASK_AUDIT_TOKEN_COUNT &&
           token->val[5] == (uint32_t)pid;
}

/* Parent links are public short BSD metadata. Full BSD reads may be denied for
 * the root-owned login process between a shell and Terminal.app. Target identity
 * still requires the full BSD/audit/owner checks below. Unknown ancestry fails
 * closed separately from a target that is positively identified as an ancestor. */
static int protected_ancestor(pid_t target) {
    pid_t cursor = getpid();
    pid_t visited[256];
    for (int depth = 0; depth < 256; ++depth) {
        if (cursor == target) return NB_CONTROL_PROTECTED;
        if (cursor == 1) return NB_CONTROL_OK;
        if (cursor <= 0) return NB_CONTROL_ANCESTRY_UNAVAILABLE;
        for (int prior = 0; prior < depth; ++prior)
            if (visited[prior] == cursor) return NB_CONTROL_ANCESTRY_UNAVAILABLE;
        visited[depth] = cursor;
        struct proc_bsdshortinfo info = {0};
        if (proc_pidinfo(cursor, PROC_PIDT_SHORTBSDINFO, 0, &info, sizeof(info)) != sizeof(info) ||
            info.pbsi_pid != (uint32_t)cursor || info.pbsi_ppid == 0 ||
            info.pbsi_ppid > INT32_MAX || info.pbsi_ppid == (uint32_t)cursor)
            return NB_CONTROL_ANCESTRY_UNAVAILABLE;
        cursor = (pid_t)info.pbsi_ppid;
    }
    return NB_CONTROL_ANCESTRY_UNAVAILABLE;
}

static int protected_path(const char *path) {
    if (path[0] != '/' || !strstr(path, ".app/Contents/")) return 1;
    const char *system_prefixes[] = {
        "/System/", "/usr/", "/bin/", "/sbin/", "/Library/Apple/",
        "/private/var/db/", "/Library/SystemExtensions/"
    };
    for (size_t i = 0; i < sizeof(system_prefixes) / sizeof(system_prefixes[0]); ++i)
        if (strncmp(path, system_prefixes[i], strlen(system_prefixes[i])) == 0) return 1;
    /* Independent native barrier for known stateful infrastructure. The product
     * layer also applies category/bundle policy, including unrecognized cases. */
    const char *protected_fragments[] = {
        "postgres", "mysqld", "mariadb", "mongod", "redis-server", "qemu",
        "virtualization", "docker.app/", "parallels", "vmware", "virtualbox",
        "com.apple."
    };
    for (size_t i = 0; i < sizeof(protected_fragments) / sizeof(protected_fragments[0]); ++i)
        if (strcasestr(path, protected_fragments[i])) return 1;
    return 0;
}

static int protected_owner(const struct proc_bsdinfo *info) {
    uid_t uid = getuid();
    return uid == 0 || geteuid() != uid || info->pbi_uid != uid ||
           info->pbi_ruid != uid || info->pbi_svuid != uid ||
           (info->pbi_flags & (PROC_FLAG_SYSTEM | PROC_FLAG_PSUGID)) != 0;
}

int nb_process_control_prepare(int32_t pid, uint64_t expected_start_microseconds,
                               nb_process_control_ticket *out) {
    if (!out) return NB_CONTROL_INVALID;
    memset(out, 0, sizeof(*out));
    if (pid <= 1 || expected_start_microseconds == 0) return NB_CONTROL_INVALID;
    int ancestry = protected_ancestor(pid);
    if (ancestry != NB_CONTROL_OK) return ancestry;
    struct proc_bsdinfo before, after;
    if (!read_bsd(pid, &before)) return NB_CONTROL_UNAVAILABLE;
    if (start_time(&before) != expected_start_microseconds ||
        before.pbi_status == SZOMB || (before.pbi_flags & PROC_FLAG_INEXIT)) return NB_CONTROL_CHANGED;
    if (protected_owner(&before)) return NB_CONTROL_PROTECTED;
    audit_token_t token = {{0}}, after_token = {{0}};
    if (!read_audit(pid, &token)) return NB_CONTROL_UNAVAILABLE;
    char path[4096] = {0};
    if (proc_pidpath_audittoken(&token, path, sizeof(path)) <= 0) return NB_CONTROL_UNAVAILABLE;
    if (protected_path(path)) return NB_CONTROL_PROTECTED;
    if (!read_bsd(pid, &after) || !read_audit(pid, &after_token)) return NB_CONTROL_UNAVAILABLE;
    if (start_time(&after) != expected_start_microseconds ||
        memcmp(&token, &after_token, sizeof(token)) != 0 ||
        before.pbi_ppid != after.pbi_ppid || after.pbi_status == SZOMB ||
        (after.pbi_flags & PROC_FLAG_INEXIT)) return NB_CONTROL_CHANGED;
    if (protected_owner(&after) || token.val[1] != getuid() || token.val[3] != getuid())
        return NB_CONTROL_PROTECTED;
    double now = monotonic_seconds();
    if (now < 0) return NB_CONTROL_UNAVAILABLE;
    out->pid = pid;
    out->parent_pid = (int32_t)after.pbi_ppid;
    out->owner_uid = getuid();
    out->start_microseconds = expected_start_microseconds;
    out->prepared_monotonic_seconds = now;
    memcpy(out->audit_token, &token, sizeof(token));
    strlcpy(out->executable_path, path, sizeof(out->executable_path));
    strlcpy(out->name, after.pbi_name[0] ? after.pbi_name : after.pbi_comm, sizeof(out->name));
    out->valid = 1;
    return NB_CONTROL_OK;
}

int nb_process_control_terminate(nb_process_control_ticket *ticket) {
    if (!ticket) return NB_CONTROL_INVALID;
    if (ticket->valid != 1) return NB_CONTROL_ALREADY_USED;
    ticket->valid = 0;
    double now = monotonic_seconds();
    double elapsed = now - ticket->prepared_monotonic_seconds;
    if (now < 0 || !(elapsed >= 0 && elapsed <= 30)) return NB_CONTROL_EXPIRED;
    nb_process_control_ticket current;
    int result = nb_process_control_prepare(ticket->pid, ticket->start_microseconds, &current);
    if (result != NB_CONTROL_OK) return result;
    if (ticket->owner_uid != current.owner_uid || ticket->parent_pid != current.parent_pid ||
        memcmp(ticket->audit_token, current.audit_token, sizeof(ticket->audit_token)) != 0 ||
        strncmp(ticket->executable_path, current.executable_path, sizeof(ticket->executable_path)) != 0)
        return NB_CONTROL_CHANGED;
    audit_token_t token;
    memcpy(&token, ticket->audit_token, sizeof(token));
    /* XNU performs its own PID-generation lookup and credential checks here.
     * Never substitute kill(pid), proc_terminate (may SIGKILL), or a process group. */
    result = proc_signal_with_audittoken(&token, SIGTERM);
    if (result == 0) return NB_CONTROL_OK;
    if (result == ESRCH || result == ENOENT) return NB_CONTROL_CHANGED;
    if (result == EPERM || result == EACCES) return NB_CONTROL_DENIED;
    return NB_CONTROL_SIGNAL_FAILED;
}

int nb_process_control_status(const nb_process_control_ticket *ticket) {
    if (!ticket || ticket->pid <= 1 || ticket->start_microseconds == 0) return NB_PROCESS_UNREADABLE;
    struct proc_bsdinfo info;
    if (!read_bsd(ticket->pid, &info)) {
        return errno == ESRCH || errno == ENOENT ? NB_PROCESS_EXITED : NB_PROCESS_UNREADABLE;
    }
    if (start_time(&info) != ticket->start_microseconds) return NB_PROCESS_REPLACED;
    if (info.pbi_status == SZOMB || (info.pbi_flags & PROC_FLAG_INEXIT)) return NB_PROCESS_EXITED;
    audit_token_t token;
    if (!read_audit(ticket->pid, &token)) return NB_PROCESS_UNREADABLE;
    if (memcmp(ticket->audit_token, &token, sizeof(token)) != 0) return NB_PROCESS_REPLACED;
    char path[4096] = {0};
    if (proc_pidpath_audittoken(&token, path, sizeof(path)) <= 0) return NB_PROCESS_UNREADABLE;
    if (strncmp(ticket->executable_path, path, sizeof(path)) != 0) return NB_PROCESS_REPLACED;
    return NB_PROCESS_ALIVE;
}
