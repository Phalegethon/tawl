#include "ProcessControl.h"
#include <assert.h>
#include <libproc.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
typedef struct { pid_t pid; int command, output; uint64_t start; } child_fixture;

static child_fixture spawn_fixture(const char *path, const char *mode) {
    int input[2], output[2];
    assert(pipe(input) == 0 && pipe(output) == 0);
    posix_spawn_file_actions_t actions;
    assert(posix_spawn_file_actions_init(&actions) == 0);
    assert(posix_spawn_file_actions_adddup2(&actions, input[0], STDIN_FILENO) == 0);
    assert(posix_spawn_file_actions_adddup2(&actions, output[1], STDOUT_FILENO) == 0);
    assert(posix_spawn_file_actions_addclose(&actions, input[1]) == 0);
    assert(posix_spawn_file_actions_addclose(&actions, output[0]) == 0);
    child_fixture child = {0};
    char *args[] = {(char *)path, (char *)mode, NULL};
    assert(posix_spawn(&child.pid, path, &actions, NULL, args, environ) == 0);
    posix_spawn_file_actions_destroy(&actions);
    close(input[0]); close(output[1]);
    child.command = input[1]; child.output = output[0];
    char ready = 0;
    assert(read(child.output, &ready, 1) == 1 && ready == 'R');
    struct proc_bsdinfo info = {0};
    assert(proc_pidinfo(child.pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info));
    child.start = info.pbi_start_tvsec * UINT64_C(1000000) + info.pbi_start_tvusec;
    return child;
}

static void finish_fixture(child_fixture child) {
    assert(write(child.command, "Q", 1) == 1);
    close(child.command); close(child.output);
    int status = 0;
    assert(waitpid(child.pid, &status, 0) == child.pid);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

int main(int argc, char **argv) {
    assert(argc == 4);
    signal(SIGPIPE, SIG_IGN);
    nb_process_control_ticket ticket = {0};
    assert(nb_process_control_prepare(0, 1, &ticket) == NB_CONTROL_INVALID);
    assert(nb_process_control_prepare(getpid(), 1, &ticket) == NB_CONTROL_PROTECTED);
    assert(nb_process_control_prepare(getppid(), 1, &ticket) == NB_CONTROL_PROTECTED);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_UNREADABLE);
    puts("PASS invalid / self / ancestor protection");

    child_fixture child = spawn_fixture(argv[1], "normal");
    assert(nb_process_control_prepare(child.pid, child.start + 1, &ticket) == NB_CONTROL_CHANGED);
    assert(nb_process_control_prepare(child.pid, child.start, &ticket) == NB_CONTROL_OK);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    nb_process_control_ticket modified = ticket;
    ++modified.audit_token[7];
    assert(nb_process_control_terminate(&modified) == NB_CONTROL_CHANGED);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    modified = ticket; modified.executable_path[1] = 'X';
    assert(nb_process_control_terminate(&modified) == NB_CONTROL_CHANGED);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    modified = ticket; ++modified.owner_uid;
    assert(nb_process_control_terminate(&modified) == NB_CONTROL_CHANGED);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    modified = ticket; modified.prepared_monotonic_seconds -= 31;
    assert(nb_process_control_terminate(&modified) == NB_CONTROL_EXPIRED);
    assert(nb_process_control_terminate(&modified) == NB_CONTROL_ALREADY_USED);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    puts("PASS stale start / generation / path / owner / expiry / single-use rejection");
    assert(nb_process_control_terminate(&ticket) == NB_CONTROL_OK);
    int status = 0;
    assert(waitpid(child.pid, &status, 0) == child.pid);
    close(child.command); close(child.output);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGTERM);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_EXITED);
    assert(nb_process_control_terminate(&ticket) == NB_CONTROL_ALREADY_USED);
    puts("PASS exact disposable child receives SIGTERM; exit observed");

    child = spawn_fixture(argv[1], "ignore");
    assert(nb_process_control_prepare(child.pid, child.start, &ticket) == NB_CONTROL_OK);
    assert(nb_process_control_terminate(&ticket) == NB_CONTROL_OK);
    usleep(30000);
    assert(nb_process_control_status(&ticket) == NB_PROCESS_ALIVE);
    finish_fixture(child);
    puts("PASS ignored SIGTERM stays alive; no force escalation");

    child = spawn_fixture(argv[1], "normal");
    assert(nb_process_control_prepare(child.pid, child.start, &ticket) == NB_CONTROL_OK);
    assert(write(child.command, "E", 1) == 1);
    char ready = 0;
    assert(read(child.output, &ready, 1) == 1 && ready == 'R');
    assert(nb_process_control_status(&ticket) == NB_PROCESS_REPLACED);
    assert(nb_process_control_terminate(&ticket) == NB_CONTROL_CHANGED);
    finish_fixture(child);
    puts("PASS same-PID exec generation change rejects old confirmation");

    child = spawn_fixture(argv[2], "normal");
    assert(nb_process_control_prepare(child.pid, child.start, &ticket) == NB_CONTROL_PROTECTED);
    finish_fixture(child);
    child = spawn_fixture(argv[3], "normal");
    assert(nb_process_control_prepare(child.pid, child.start, &ticket) == NB_CONTROL_PROTECTED);
    finish_fixture(child);
    puts("PASS unknown executable / database path protection");
    return 0;
}
