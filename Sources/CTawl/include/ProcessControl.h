#ifndef NB_PROCESS_CONTROL_H
#define NB_PROCESS_CONTROL_H

#include <stdint.h>

enum {
    NB_CONTROL_OK = 0,
    NB_CONTROL_INVALID = 1,
    NB_CONTROL_PROTECTED = 2,
    NB_CONTROL_UNAVAILABLE = 3,
    NB_CONTROL_CHANGED = 4,
    NB_CONTROL_EXPIRED = 5,
    NB_CONTROL_DENIED = 6,
    NB_CONTROL_SIGNAL_FAILED = 7,
    NB_CONTROL_ALREADY_USED = 8,
    NB_CONTROL_ANCESTRY_UNAVAILABLE = 9
};

enum {
    NB_PROCESS_ALIVE = 0,
    NB_PROCESS_EXITED = 1,
    NB_PROCESS_REPLACED = 2,
    NB_PROCESS_UNREADABLE = 3
};

/* A single-use, short-lived process identity captured before a user confirmation.
 * Consumers must not synthesize or modify fields; prepare fills the entire ticket.
 * The Swift layer additionally validates application attribution and recommendations.
 */
typedef struct {
    int32_t pid, parent_pid;
    uint32_t owner_uid;
    uint64_t start_microseconds;
    double prepared_monotonic_seconds;
    uint32_t audit_token[8];
    char executable_path[4096], name[64];
    int32_t valid;
} nb_process_control_ticket;

/* Read-only. No PID-only fallback when an audit token cannot be obtained. */
int nb_process_control_prepare(int32_t pid, uint64_t expected_start_microseconds,
                               nb_process_control_ticket *out);
/* Sends only SIGTERM to the captured process generation, after all live checks.
 * A successful result means the signal was accepted, not that the process exited.
 * Every call consumes the ticket, including denied/failed attempts.
 */
int nb_process_control_terminate(nb_process_control_ticket *ticket);
/* Read-only and usable after a ticket is consumed. Zombies count as exited. */
int nb_process_control_status(const nb_process_control_ticket *ticket);

#endif
