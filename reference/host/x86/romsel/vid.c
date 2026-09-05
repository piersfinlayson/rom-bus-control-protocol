/* vid.c - direct screen and keyboard access, no BIOS entry points. */

#include <i86.h>
#include <conio.h>
#include "vid.h"

static u16 vid_seg  = 0xB800;
static u16 crtc_base = 0x3D4;

#define BDA(off) ((volatile u16 __far *)MK_FP(0x40, (off)))

#define CELL(r, c) ((u16 __far *)MK_FP(vid_seg, (u16)(((u16)(r) * VID_COLS + (c)) * 2)))

void vid_init(void)
{
    /* Equipment word, bits 5 and 4. Both set means the monochrome adapter.
       This is a read of the data area, not a call into the ROM. */
    u16 equip = *BDA(0x10);

    if ((equip & 0x0030) == 0x0030) {
        vid_seg   = 0xB000;
        crtc_base = 0x3B4;
    } else {
        vid_seg   = 0xB800;
        crtc_base = 0x3D4;
    }
}

void vid_clear(u8 attr)
{
    u16 __far *p = CELL(0, 0);
    u16 blank = (u16)(((u16)attr << 8) | ' ');
    u16 i;

    for (i = 0; i < VID_COLS * VID_ROWS; i++)
        p[i] = blank;
}

void vid_putc(u8 row, u8 col, char c, u8 attr)
{
    if (row >= VID_ROWS || col >= VID_COLS)
        return;
    *CELL(row, col) = (u16)(((u16)attr << 8) | (u8)c);
}

void vid_puts(u8 row, u8 col, const char *s, u8 attr)
{
    while (*s && col < VID_COLS) {
        vid_putc(row, col, *s, attr);
        s++;
        col++;
    }
}

void vid_fill(u8 row, u8 col, u8 len, char c, u8 attr)
{
    while (len-- && col < VID_COLS) {
        vid_putc(row, col, c, attr);
        col++;
    }
}

void vid_hex8(u8 row, u8 col, u8 v, u8 attr)
{
    static const char digits[] = "0123456789ABCDEF";
    vid_putc(row, col,     digits[(v >> 4) & 0x0F], attr);
    vid_putc(row, col + 1, digits[v & 0x0F], attr);
}

void vid_dec(u8 row, u8 col, u16 v, u8 attr)
{
    char buf[6];
    int n = 0;

    if (v == 0) {
        vid_putc(row, col, '0', attr);
        return;
    }
    while (v && n < 5) {
        buf[n++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (n--) {
        vid_putc(row, col, buf[n], attr);
        col++;
    }
}

/* The CRTC cursor start register. Bit 5 of the start-scanline value blanks
   the cursor on both the 6845 and everything that clones it. */
void vid_cursor_off(void)
{
    outp(crtc_base, 0x0A);
    outp(crtc_base + 1, 0x20);
}

void vid_cursor_on(void)
{
    outp(crtc_base, 0x0A);
    outp(crtc_base + 1, (vid_seg == 0xB000) ? 0x0B : 0x06);
    outp(crtc_base, 0x0B);
    outp(crtc_base + 1, (vid_seg == 0xB000) ? 0x0C : 0x07);
}

/* ------------------------------------------------------------------ */
/* Keystrokes, taken from the ring in the data area                     */
/* ------------------------------------------------------------------ */

/* IRQ1 writes the tail, a consumer writes the head. Nothing else consumes
   from this ring while the menu is up, so the head is ours, but the update
   is still made with interrupts off: the ROM's own handler reads the head to
   decide whether the ring is full. */

static void ring_bounds(u16 *start, u16 *end)
{
    *start = *BDA(0x80);
    *end   = *BDA(0x82);

    /* Every BIOS that predates those two words puts the ring at the same
       fixed place. */
    if (*start == 0 || *end == 0 || *end <= *start) {
        *start = 0x001E;
        *end   = 0x003E;
    }
}

u16 kbd_get(void)
{
    u16 head, tail, start, end, key;

    head = *BDA(0x1A);
    tail = *BDA(0x1C);
    if (head == tail)
        return 0;

    ring_bounds(&start, &end);

    key = *(volatile u16 __far *)MK_FP(0x40, head);

    head += 2;
    if (head >= end)
        head = start;

    _asm { cli }
    *BDA(0x1A) = head;
    _asm { sti }

    return key;
}

u16 kbd_wait(void)
{
    u16 k;
    do {
        k = kbd_get();
    } while (k == 0);
    return k;
}

void kbd_flush(void)
{
    while (kbd_get() != 0)
        ;
}
