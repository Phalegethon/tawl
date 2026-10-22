#ifndef TAWL_TERMINAL_SUPPORT_H
#define TAWL_TERMINAL_SUPPORT_H
#include <stdint.h>
int tawl_terminal_is_tty(void);
int tawl_terminal_begin(void);
void tawl_terminal_end(void);
int tawl_terminal_stopped(void);
void tawl_terminal_size(int32_t *columns, int32_t *rows);
int tawl_terminal_read(uint8_t *buffer, int32_t capacity, int32_t timeout_ms);
#endif
