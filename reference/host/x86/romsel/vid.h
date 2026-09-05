/* vid.h - direct screen and keyboard access, no BIOS entry points.

   Output goes straight to the adapter's text buffer. Keystrokes are taken
   from the BIOS keystroke ring in the data area, which IRQ1 fills, rather
   than through INT 16H. Both are reads and writes of RAM and ports, so
   neither depends on any routine in the ROM being served. */

#ifndef VID_H
#define VID_H

typedef unsigned char  u8;
typedef unsigned int   u16;

#define VID_COLS    80
#define VID_ROWS    25

/* Attributes. */
#define A_NORM      0x07
#define A_BOLD      0x0F
#define A_SEL       0x70
#define A_DIM       0x08
#define A_WARN      0x0E
#define A_ERR       0x0C

void vid_init(void);
void vid_clear(u8 attr);
void vid_puts(u8 row, u8 col, const char *s, u8 attr);
void vid_putc(u8 row, u8 col, char c, u8 attr);
void vid_fill(u8 row, u8 col, u8 len, char c, u8 attr);
void vid_hex8(u8 row, u8 col, u8 v, u8 attr);
void vid_dec(u8 row, u8 col, u16 v, u8 attr);
void vid_cursor_off(void);
void vid_cursor_on(void);

/* Returns the BIOS-format key word, or 0 when the ring is empty. */
u16  kbd_get(void);
/* Waits for a keystroke. */
u16  kbd_wait(void);
/* Throws away anything already queued. */
void kbd_flush(void);

#define K_ESC       0x011B
#define K_ENTER     0x1C0D
#define K_UP        0x4800
#define K_DOWN      0x5000

#endif
