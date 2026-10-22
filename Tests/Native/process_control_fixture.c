/* Disposable child for the process-control test only. No unrelated process is used. */
#include <signal.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    alarm(20); /* Failsafe if the test parent crashes or leaves an inherited pipe. */
    if (argc > 1 && strcmp(argv[1], "ignore") == 0) signal(SIGTERM, SIG_IGN);
    char ready = 'R';
    if (write(STDOUT_FILENO, &ready, 1) != 1) return 2;
    char command;
    while (read(STDIN_FILENO, &command, 1) == 1) {
        if (command == 'E') {
            execl(argv[0], argv[0], "normal", (char *)0);
            return 3;
        }
        if (command == 'Q') return 0;
    }
    return 0;
}
