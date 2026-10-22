#include "TerminalSupport.h"
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

static struct termios saved_terminal;
static struct sigaction saved_signals[5];
static const int signal_numbers[5] = { SIGINT, SIGTERM, SIGQUIT, SIGTSTP, SIGHUP };
static volatile sig_atomic_t stop_requested = 0;
static int active = 0;
static void request_stop(int signal_number) { (void)signal_number; stop_requested = 1; }
int tawl_terminal_is_tty(void) { return isatty(STDIN_FILENO) && isatty(STDOUT_FILENO); }
int tawl_terminal_begin(void) {
    if (active || !tawl_terminal_is_tty() || tcgetattr(STDIN_FILENO, &saved_terminal) != 0) return -1;
    struct termios raw = saved_terminal;
    raw.c_iflag &= ~(BRKINT | ICRNL | IGNCR | INLCR | INPCK | ISTRIP | IXON);
    raw.c_oflag &= ~OPOST;
    raw.c_cflag |= CS8;
    raw.c_lflag &= ~(ECHO | ICANON | IEXTEN);
    raw.c_cc[VMIN] = 0; raw.c_cc[VTIME] = 0;
    if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0) return -1;
    stop_requested = 0; active = 1;
    struct sigaction action;
    memset(&action, 0, sizeof(action)); action.sa_handler = request_stop; sigemptyset(&action.sa_mask);
    for (int i = 0; i < 5; ++i) sigaction(signal_numbers[i], &action, &saved_signals[i]);
    static int registered = 0;
    if (!registered) { atexit(tawl_terminal_end); registered = 1; }
    /* Preserve xterm private modes when supported. The alternate screen keeps
       shell history intact; mouse reporting routes the wheel into the TUI.
       Bracketed paste lets the input decoder discard pasted action keys.
       No host scrollbar or persistent terminal preferences are modified. */
    const char *begin = "\033[?7;25;1000;1006;2004s\033[?1049h\033[?7l\033[?25l"
                        "\033[?1000h\033[?1006h\033[?2004h\033[2J\033[H";
    (void)write(STDOUT_FILENO, begin, strlen(begin));
    return 0;
}
void tawl_terminal_end(void) {
    if (!active) return;
    active = 0;
    (void)tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved_terminal);
    /* Defaults also recover terminals which ignore XTSAVE/XTRESTORE. */
    const char *end = "\033[?2004l\033[?1006l\033[?1000l\033[?7h\033[0m\033[?25h\033[?1049l"
                      "\033[?7;25;1000;1006;2004r";
    (void)write(STDOUT_FILENO, end, strlen(end));
    for (int i = 0; i < 5; ++i) sigaction(signal_numbers[i], &saved_signals[i], NULL);
}
int tawl_terminal_stopped(void) { return stop_requested != 0; }
void tawl_terminal_size(int32_t *columns, int32_t *rows) {
    struct winsize size;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col && size.ws_row) {
        *columns = size.ws_col; *rows = size.ws_row;
    }
}
int tawl_terminal_read(uint8_t *buffer, int32_t capacity, int32_t timeout_ms) {
    struct pollfd descriptor = { STDIN_FILENO, POLLIN, 0 };
    int ready = poll(&descriptor, 1, timeout_ms);
    if (stop_requested) return -1;
    if (ready < 0) return errno == EINTR ? 0 : -1;
    if (ready == 0) return 0;
    if (descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)) return -1;
    ssize_t count = read(STDIN_FILENO, buffer, (size_t)capacity);
    if (count == 0) return -1;
    return count < 0 ? (errno == EINTR || errno == EAGAIN ? 0 : -1) : (int)count;
}
