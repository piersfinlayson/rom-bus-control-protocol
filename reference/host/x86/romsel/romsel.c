/* romsel.c - pick which image a One ROM serves in the BIOS socket of an
   8088 machine, then reset into it.

   The choice takes effect at once and lasts until the machine loses power,
   at which point the device reloads whatever flash slot it boots from. That
   is the escape hatch: an image that hangs cannot be made permanent.

   Nothing here calls a BIOS routine. The screen is written directly, keys
   come out of the data area ring, and delays come from the interval timer.
   The image being switched to need not be a BIOS at all. */

#include <string.h>
#include <fcntl.h>
#include <io.h>
#include <i86.h>
#include <conio.h>
#include "rbcp.h"
#include "vid.h"

#define REC_SIZE    32
#define NAME_MAX    31

/* Records start 12 bytes into the back-channel: the 8-byte response header
   then the 4-byte preamble. */
#define REC_CAPACITY  ((CFG_BCH_SIZE - 12) / REC_SIZE)

#define PATH_SEP    92          /* backslash */

/* Rows 8 upwards, stopping short of the message line. */
#define LIST_FIRST_ROW  8
#define LIST_ROWS       11

static u8   slot_total;
static u8   slot_whole;
static u8   slot_rec[CFG_MAX_SLOTS * REC_SIZE];
static char name_buf[NAME_MAX + 1];
static char dev_type[25];
static char dev_ver[25];

/* An image read from disk, held in memory because the session that writes it
   runs with interrupts disabled and DOS cannot be called there. */
static u8   file_img[CFG_ROM_SIZE];
static char file_name[16];
static int  have_file = 0;

static int  opt_list = 0;
static int  opt_noconfirm = 0;
static int  opt_dump = 0;
static int  opt_noparity = 0;

/* Cleared where a session could not put every displaced byte back. */
static int  image_clean = 1;

static void draw_header(void);

/* ------------------------------------------------------------------ */
/* Machine control                                                     */
/* ------------------------------------------------------------------ */

/* Port A0H bit 7 gates the non-maskable interrupt, and port 61H bits 5 and 4
   gate the two things that raise one: the I/O channel check and the system
   board parity check. Both are zero to enable and one to disable.

   Masking at A0H alone is not enough. It stops the processor seeing an NMI
   but not the parity flag latching, and it does not clear a flag that has
   latched, so unmasking fires whatever was recorded while the session ran.
   Setting bit 4 both disables the check and clears the flag, which is the
   sequence the BIOS itself uses. */

#define PPI_B       0x61
#define PB_IOCHK    0x20
#define PB_PARITY   0x10
#define NMI_MASK    0xA0

static u8 saved_ppi_b = 0;

static void nmi_off(void)
{
    /* Read and write back, never write a constant: the same port holds the
       keyboard clock and enable lines and the timer 2 gate. */
    saved_ppi_b = (u8)inp(PPI_B);
    outp(PPI_B, (u8)(saved_ppi_b | PB_IOCHK | PB_PARITY));
    outp(NMI_MASK, 0x00);
}

static void nmi_on(void)
{
    u8 v = (u8)inp(PPI_B);

    /* Clear anything that latched during the session, then put the two bits
       back the way they were found. */
    outp(PPI_B, (u8)(v | PB_IOCHK | PB_PARITY));
    if (!opt_noparity)
        outp(PPI_B, (u8)((v & ~(PB_IOCHK | PB_PARITY)) |
                         (saved_ppi_b & (PB_IOCHK | PB_PARITY))));

    outp(NMI_MASK, 0x80);
}

static void ints_off(void) { _asm { cli } }
static void ints_on(void)  { _asm { sti } }

/* Clears the warm boot flag so a BIOS runs its full power-on path rather
   than trusting what the previous one left in memory, then jumps to the
   address the processor starts at out of reset. A diagnostic image ignores
   the flag, which costs nothing. */
static void cold_boot(void)
{
    _asm {
        cli
        xor     ax, ax
        mov     es, ax
        mov     word ptr es:[472h], 0
        mov     ax, 0FFFFh
        push    ax
        xor     ax, ax
        push    ax
        retf
    }
}

/* ------------------------------------------------------------------ */
/* Slot records                                                        */
/* ------------------------------------------------------------------ */

static const char *rom_type_name(u8 t)
{
    switch (t) {
        case 0x02: return "2364";
        case 0x03: return "23128";
        case 0x04: return "23256";
        case 0x09: return "2732";
        case 0x0A: return "2764";
        case 0x0B: return "27128";
        case 0x0C: return "27256";
        case 0x0D: return "27512";
        case 0x1B: return "28C64";
        case 0x1C: return "28C256";
        case 0xFF: return "none";
        default:   return "?";
    }
}

static const char *slot_name(u8 i)
{
    const u8 *rec = slot_rec + (u16)i * REC_SIZE;
    u8 n;

    for (n = 0; n < NAME_MAX; n++) {
        u8 c = rec[1 + n];
        if (c == 0)
            break;
        /* The screen is a fixed grid, so anything not printable would leave
           a hole in the line rather than be skipped. */
        name_buf[n] = (c >= 0x20 && c < 0x7F) ? (char)c : '.';
    }
    name_buf[n] = 0;

    if (n == 0)
        return "(unnamed)";
    return name_buf;
}

static u8 slot_type(u8 i)
{
    return slot_rec[(u16)i * REC_SIZE];
}

/* ------------------------------------------------------------------ */
/* Screen                                                              */
/* ------------------------------------------------------------------ */

static void status(const char *s)
{
    vid_fill(23, 2, 76, ' ', A_NORM);
    vid_puts(23, 2, s, A_NORM);
}

static void status_attr(const char *s, u8 attr)
{
    vid_fill(23, 2, 76, ' ', A_NORM);
    vid_puts(23, 2, s, attr);
}

static void frame(void)
{
    vid_clear(A_NORM);
    vid_fill(0, 0, 80, ' ', A_SEL);
    vid_puts(0, 2, "ROMSEL " CFG_VERSION " - One ROM image selector", A_SEL);
    vid_fill(24, 0, 80, ' ', A_SEL);
    vid_puts(24, 2, "UP/DOWN or 0-9 select   ENTER boot   ESC quit", A_SEL);
}

static const char *err_text(int r)
{
    switch (r) {
        case RB_FAILED:      return "Device refused the command.";
        case RB_NO_TOKEN:    return "No answer. Check the ROM window, stride and command page.";
        case RB_NO_PROGRESS: return "Command received but never completed.";
        default:             return "Unknown error.";
    }
}

static void fatal(const char *what, int r)
{
    status_attr(what, A_ERR);
    vid_puts(21, 2, err_text(r), A_ERR);
    vid_puts(19, 2, "Nothing was changed. Press any key.", A_NORM);
    kbd_flush();
    kbd_wait();
}

/* ------------------------------------------------------------------ */
/* Phase one - read the device, put the image back                      */
/* ------------------------------------------------------------------ */

static int scan(void)
{
    int r;

    ints_off();
    nmi_off();

    /* Read the bytes the back-channel will sit on before anything knocks,
       while the device is still idle. */
    rbcp_save_region();

    r = rbcp_open();
    if (r != RB_OK) {
        nmi_on();
        ints_on();
        return r;
    }

    /* The version comes first because the exit path is chosen from it, and a
       device that will not report one is treated as the older kind, which is
       the safe direction to be wrong in.

       Only two of these are worth failing over. The boot slot is a courtesy,
       reported by devices from 0.1.2 onward and simply unknown on the rest,
       and nothing here needs it. A failure past this point still has to leave
       command-response mode and put the displaced bytes back, so the result is
       kept and the exit runs either way. */
    rbcp_get_protocol_version();

    r = rbcp_get_ram_slot_info();
    if (r == RB_OK) {
        rbcp_get_boot_slot_info();
        r = rbcp_get_flash_slot_info_all(&slot_total, &slot_whole,
                                         slot_rec, sizeof(slot_rec));
    }

    image_clean = rbcp_close_restore();

    nmi_on();
    ints_on();
    return r;
}

/* ------------------------------------------------------------------ */
/* Dump - what the settings are and what came back                      */
/* ------------------------------------------------------------------ */

/* Bring-up needs to tell apart a device that never heard the knock from one
   that heard it and refused, and both of those from an empty socket. The
   region bytes before and after the attempt say which: unchanged means
   nothing is listening, changed means something is. */

static void hex16(u8 row, u8 col, u16 v, u8 attr)
{
    vid_hex8(row, col, (u8)(v >> 8), attr);
    vid_hex8(row, (u8)(col + 2), (u8)(v & 0xFF), attr);
}

static void hexline(u8 row, const char *label, const u8 *b)
{
    u8 i;
    vid_puts(row, 4, label, A_DIM);
    for (i = 0; i < 16; i++)
        vid_hex8(row, (u8)(20 + i * 3), b[i], A_NORM);
}

static void probe_dump(void)
{
    u8 before[16], after[16];
    u8 i;
    int r;

    frame();
    status("Probing...");

    ints_off();
    nmi_off();

    rbcp_save_region();
    for (i = 0; i < 16; i++)
        before[i] = rbcp_bch_byte(i);

    r = rbcp_open();

    for (i = 0; i < 16; i++)
        after[i] = rbcp_bch_byte(i);

    if (r == RB_OK) {
        rbcp_get_protocol_version();
        rbcp_get_device_type(dev_type, sizeof(dev_type));
        rbcp_get_device_version(dev_ver, sizeof(dev_ver));
        rbcp_get_ram_slot_info();
        rbcp_get_boot_slot_info();
        rbcp_get_flash_slot_info_all(&slot_total, &slot_whole,
                                     slot_rec, sizeof(slot_rec));
        image_clean = rbcp_close_restore();
    } else {
        /* ENTER_CMD_RESP never completed, so nothing was displaced. Leave the
           device idle rather than part way through a frame. */
        rbcp_reset();
    }

    nmi_on();
    ints_on();

    vid_puts(2, 2, "Settings", A_BOLD);

    vid_puts(3, 4, "ROM window", A_DIM);
    hex16(3, 20, CFG_ROM_SEG, A_NORM);
    vid_puts(3, 24, ":0000  size", A_DIM);
    hex16(3, 36, CFG_ROM_SIZE, A_NORM);

    vid_puts(4, 4, "Command page", A_DIM);
    vid_hex8(4, 20, CFG_CMD_PAGE, A_NORM);
    vid_puts(4, 24, "stride", A_DIM);
    vid_dec(4, 36, CFG_STRIDE, A_NORM);

    vid_puts(5, 4, "Back-channel", A_DIM);
    hex16(5, 20, CFG_BCH_OFF, A_NORM);
    vid_puts(5, 24, "size", A_DIM);
    hex16(5, 36, CFG_BCH_SIZE, A_NORM);

    vid_puts(6, 4, "complete/OK", A_DIM);
    vid_hex8(6, 20, rb_complete, A_NORM);
    vid_hex8(6, 23, rb_status_ok, A_NORM);

    vid_puts(8, 2, "Region, first 16 bytes", A_BOLD);
    hexline(9,  "before", before);
    hexline(10, "after ", after);

    if (r == RB_OK) {
        vid_puts(12, 2, "Command-response mode entered.", A_NORM);

        vid_puts(13, 4, "Device", A_DIM);
        vid_puts(13, 20, dev_type, A_NORM);
        vid_puts(13, 46, dev_ver, A_NORM);

        vid_puts(14, 4, "Protocol", A_DIM);
        vid_dec(14, 20, rb_proto_major, A_NORM);
        vid_putc(14, 21, '.', A_NORM);
        vid_dec(14, 22, rb_proto_minor, A_NORM);
        vid_putc(14, 23, '.', A_NORM);
        vid_dec(14, 24, rb_proto_patch, A_NORM);
        if (rb_proto_major == 0 && rb_proto_minor == 1 && rb_proto_patch < 2)
            vid_puts(14, 28, "pre-0.1.2, older exit path in use", A_WARN);

        vid_puts(15, 4, "RAM slots", A_DIM);
        vid_dec(15, 20, rb_ram_count, A_NORM);
        vid_puts(15, 26, "active", A_DIM);
        vid_dec(15, 34, rb_ram_active, A_NORM);

        vid_puts(16, 4, "Flash slots", A_DIM);
        vid_dec(16, 20, slot_total, A_NORM);
        vid_puts(16, 26, "records", A_DIM);
        vid_dec(16, 34, slot_whole, A_NORM);

        vid_puts(17, 4, "Boot flash slot", A_DIM);
        if (rb_boot_flash == 0xFF)
            vid_puts(17, 20, "not reported", A_DIM);
        else
            vid_dec(17, 20, rb_boot_flash, A_NORM);
    } else {
        vid_puts(12, 2, err_text(r), A_ERR);
        vid_puts(14, 2, "If the two lines above match, nothing decoded the "
                        "knock: check the", A_NORM);
        vid_puts(15, 2, "ROM window and the command page against where this "
                        "machine maps the", A_NORM);
        vid_puts(16, 2, "socket. If they differ, the device is listening and "
                        "refused the", A_NORM);
        vid_puts(17, 2, "settings above.", A_NORM);
    }

    status("Press any key.");
    kbd_flush();
    kbd_wait();
}

/* ------------------------------------------------------------------ */
/* Phase two - switch and reset. Does not return on success.            */
/* ------------------------------------------------------------------ */

static int commit(u8 flash_slot)
{
    u8 target;
    int r;

    ints_off();
    nmi_off();

    r = rbcp_open();
    if (r != RB_OK) {
        nmi_on();
        ints_on();
        return r;
    }

    if (rb_ram_count >= 2) {
        /* Load into a slot nothing is reading, then switch. The image on the
           bus goes from wholly the old one to wholly the new one in a single
           step, so the reset jump cannot land in a half-copied image. */
        target = (rb_ram_active == 0) ? 1 : 0;

        r = rbcp_load_slot(target, flash_slot);
        if (r != RB_OK) {
            image_clean = rbcp_close_restore();
            nmi_on();
            ints_on();
            return r;
        }

        rbcp_switch_and_exit(target);
        rbcp_delay_ms(CFG_SWITCH_MS);
    } else {
        /* One RAM slot, so the copy has to run over the image the processor
           is reading. Leave command-response mode first: with no back-channel
           being maintained, nothing writes a response header into the image
           that is about to be booted. Command mode has nothing to poll, so
           the wait has to cover the whole copy. */
        rbcp_exit_silent();
        rbcp_load_slot_cmd_mode(rb_ram_active, flash_slot);
        rbcp_delay_ms(CFG_LOAD_MS);
    }

    cold_boot();
    return RB_OK;               /* not reached */
}

/* ------------------------------------------------------------------ */
/* An image from disk                                                   */
/* ------------------------------------------------------------------ */

/* Reads the file whole, before any session, and tiles it if it is shorter
   than the socket. A short image that is not tiled leaves nothing at the
   reset vector for the jump to land on, which is the same reason the device
   programmer has a size=dup. */
static const char *load_file(const char *path)
{
    int  fd;
    long sz;
    int  got;
    u16  i, n;

    fd = open(path, O_RDONLY | O_BINARY);
    if (fd < 0)
        return "Cannot open that file.";

    sz = filelength(fd);
    if (sz <= 0) {
        close(fd);
        return "That file is empty.";
    }
    if (sz > (long)CFG_ROM_SIZE) {
        close(fd);
        return "That file is larger than the socket.";
    }
    if ((u16)CFG_ROM_SIZE % (u16)sz) {
        close(fd);
        return "That size does not divide into the socket.";
    }

    n = (u16)sz;
    got = read(fd, file_img, n);
    close(fd);

    if (got != (int)n)
        return "Short read.";

    for (i = n; i < CFG_ROM_SIZE; i++)     /* tile a short image to fill */
        file_img[i] = file_img[i - n];

    /* Remember the name alone, for a menu line that has to fit. */
    {
        const char *base = path;
        const char *p;
        for (p = path; *p; p++)
            if (*p == PATH_SEP || *p == '/' || *p == ':')
                base = p + 1;
        for (i = 0; i < sizeof(file_name) - 1 && base[i]; i++)
            file_name[i] = base[i];
        file_name[i] = 0;
    }

    have_file = 1;
    return 0;
}

/* Drawn from inside the session. Writing to video memory is a write to RAM,
   which is why this is allowed where a BIOS call would not be. */
static void progress(u16 done, u16 total)
{
    u16 cells = (u16)((u32)done * 60 / total);
    u8  i;

    for (i = 0; i < 60; i++)
        vid_putc(21, (u8)(10 + i), (char)(i < cells ? 0xDB : 0xB0),
                 i < cells ? A_BOLD : A_DIM);
}

/* Writes the image from disk into a spare RAM slot and boots it. Does not
   return on success. */
static int commit_file(void)
{
    u8  target;
    int r;

    if (rb_ram_count < 2)
        return RB_FAILED;

    ints_off();
    nmi_off();

    r = rbcp_open();
    if (r != RB_OK) {
        nmi_on();
        ints_on();
        return r;
    }

    target = (u8)((rb_ram_active == 0) ? 1 : 0);

    r = rbcp_write_image(file_img, CFG_ROM_SIZE, target, progress);
    if (r != RB_OK) {
        image_clean = rbcp_close_restore();
        nmi_on();
        ints_on();
        return r;
    }

    rbcp_switch_and_exit(target);
    rbcp_delay_ms(CFG_SWITCH_MS);

    cold_boot();
    return RB_OK;               /* not reached */
}

/* ------------------------------------------------------------------ */
/* Menu                                                                */
/* ------------------------------------------------------------------ */

static void draw_header(void)
{
    vid_puts(2, 2, "Device protocol", A_DIM);
    vid_dec(2, 20, rb_proto_major, A_NORM);
    vid_putc(2, 21, '.', A_NORM);
    vid_dec(2, 22, rb_proto_minor, A_NORM);
    vid_putc(2, 23, '.', A_NORM);
    vid_dec(2, 24, rb_proto_patch, A_NORM);

    vid_puts(3, 2, "RAM slots", A_DIM);
    vid_dec(3, 20, rb_ram_count, A_NORM);
    vid_puts(3, 24, "active", A_DIM);
    vid_dec(3, 31, rb_ram_active, A_NORM);

    vid_puts(4, 2, "Booted from flash", A_DIM);
    if (rb_boot_flash == 0xFF)
        vid_puts(4, 20, "unknown", A_WARN);
    else
        vid_dec(4, 20, rb_boot_flash, A_NORM);

    if (rb_ram_count < 2)
        vid_puts(5, 2, "One RAM slot: the new image is copied over the "
                       "running one.", A_WARN);

    if (!image_clean)
        vid_puts(6, 2, "Served image not fully restored. Power cycle rather "
                       "than warm boot.", A_ERR);
}

/* The list is the device's flash slots, and then the file from the command
   line if there was one. That last entry is not a slot on the device and has
   no number there, so it is keyed on F. */
static u8 entry_count(u8 count)
{
    return (u8)(count + (have_file ? 1 : 0));
}

static void draw_slots(u8 count, u8 sel)
{
    u8 i;

    vid_puts(7, 2, "Slot  Type      Name", A_DIM);

    for (i = 0; i < count; i++) {
        u8 row  = (u8)(LIST_FIRST_ROW + i);
        u8 attr = (i == sel) ? A_SEL : A_NORM;

        vid_fill(row, 2, 74, ' ', attr);
        vid_dec(row, 3, i, attr);
        vid_puts(row, 8, rom_type_name(slot_type(i)), attr);
        vid_puts(row, 18, slot_name(i), attr);

        if (i == rb_boot_flash)
            vid_puts(row, 60, "(boot)", attr);
    }

    if (have_file) {
        u8 row  = (u8)(LIST_FIRST_ROW + count);
        u8 attr = (count == sel) ? A_SEL : A_NORM;

        vid_fill(row, 2, 74, ' ', attr);
        vid_putc(row, 3, 'F', attr);
        vid_puts(row, 8, "file", attr);
        vid_puts(row, 18, file_name, attr);
        vid_puts(row, 60, "(from disk)", attr);
    }
}

static int confirm(u8 count, u8 sel)
{
    u16 k;

    vid_fill(21, 2, 76, ' ', A_WARN);
    if (have_file && sel == count) {
        vid_puts(21, 2, "Write and boot ", A_WARN);
        vid_puts(21, 18, file_name, A_WARN);
    } else {
        vid_puts(21, 2, "Reset into slot ", A_WARN);
        vid_dec(21, 18, sel, A_WARN);
        vid_puts(21, 21, slot_name(sel), A_WARN);
    }
    status_attr("Y to reset now, any other key to go back. "
                "Close your files first.", A_WARN);

    kbd_flush();
    k = kbd_wait();
    vid_fill(21, 2, 76, ' ', A_NORM);

    return ((k & 0xFF) == 'y' || (k & 0xFF) == 'Y');
}

static void menu(u8 count)
{
    u8 total = entry_count(count);
    u8 sel   = (rb_boot_flash < count) ? rb_boot_flash : 0;

    draw_header();
    kbd_flush();

    for (;;) {
        u16 k;
        u8  c;

        draw_slots(count, sel);
        status(have_file ? "Select an image. F is the file from disk."
                         : "Select an image.");

        k = kbd_wait();

        if (k == K_ESC)
            return;

        if (k == K_UP) {
            sel = (u8)((sel == 0) ? total - 1 : sel - 1);
            continue;
        }
        if (k == K_DOWN) {
            sel = (u8)((sel + 1 >= total) ? 0 : sel + 1);
            continue;
        }

        c = (u8)(k & 0xFF);
        if (c >= '0' && c <= '9' && (u8)(c - '0') < count) {
            sel = (u8)(c - '0');
            continue;
        }
        if (have_file && (c == 'f' || c == 'F')) {
            sel = count;
            continue;
        }

        if (k == K_ENTER) {
            int r;

            if (have_file && sel == count && rb_ram_count < 2) {
                status_attr("Writing an image needs a device with two RAM "
                            "slots. This one has one.", A_ERR);
                kbd_wait();
                continue;
            }

            if (!opt_noconfirm && !confirm(count, sel))
                continue;

            if (have_file && sel == count) {
                status("Writing the image. This takes a moment.");
                r = commit_file();
                vid_fill(21, 2, 76, ' ', A_NORM);
                fatal("Write failed.", r);
            } else {
                status("Switching...");
                r = commit(sel);
                fatal("Switch failed.", r);
            }
            /* Only reached when the boot did not happen. */
            return;
        }
    }
}

/* ------------------------------------------------------------------ */

static void usage(void)
{
    frame();
    vid_puts(3,  2, "ROMSEL - choose which One ROM image this machine boots.", A_BOLD);
    vid_puts(4,  2, "  ROMSEL [image.rom] [switches]", A_DIM);
    vid_puts(6,  2, "  /L   list the slots and quit", A_NORM);
    vid_puts(7,  2, "  /D   show the settings and what the device sent back", A_NORM);
    vid_puts(8,  2, "  /P   leave parity and I/O checking off on exit", A_NORM);
    vid_puts(9,  2, "  /Y   skip the confirmation", A_NORM);
    vid_puts(10, 2, "  /?   this text", A_NORM);
    vid_puts(12, 2, "Name an image file and it joins the menu as entry F, to be", A_NORM);
    vid_puts(13, 2, "written into a spare RAM slot without being flashed. That", A_NORM);
    vid_puts(14, 2, "needs a device with two or more RAM slots.", A_NORM);
    vid_puts(16, 2, "The choice takes effect immediately and the machine resets", A_NORM);
    vid_puts(17, 2, "into it. It lasts until power is removed.", A_NORM);
    status("Press any key.");
    kbd_flush();
    kbd_wait();
}

int main(int argc, char **argv)
{
    int i, r;
    u8  count;
    const char *file_err = 0;

    for (i = 1; i < argc; i++) {
        char c;
        if (argv[i][0] != '/' && argv[i][0] != '-') {
            file_err = load_file(argv[i]);
            continue;
        }
        c = argv[i][1];
        if (c >= 'a' && c <= 'z')
            c = (char)(c - 32);
        if (c == 'L')
            opt_list = 1;
        else if (c == 'Y')
            opt_noconfirm = 1;
        else if (c == 'D')
            opt_dump = 1;
        else if (c == 'P')
            opt_noparity = 1;
        else {
            vid_init();
            usage();
            vid_clear(A_NORM);
            vid_cursor_on();
            return 0;
        }
    }

    vid_init();
    vid_cursor_off();

    if (file_err) {
        frame();
        vid_puts(10, 2, file_err, A_ERR);
        vid_puts(12, 2, "Give the path to an image no larger than the socket, "
                        "whose size", A_NORM);
        vid_puts(13, 2, "divides into it. A shorter one is repeated to fill.", A_NORM);
        status("Press any key.");
        kbd_flush();
        kbd_wait();
        vid_clear(A_NORM);
        vid_cursor_on();
        return 1;
    }

    if (opt_dump) {
        probe_dump();
        vid_clear(A_NORM);
        vid_cursor_on();
        return image_clean ? 0 : 2;
    }

    frame();
    status("Probing the device...");

    r = scan();
    if (r != RB_OK) {
        fatal("No usable device in the ROM socket.", r);
        vid_clear(A_NORM);
        vid_cursor_on();
        return 1;
    }

    /* The device returns as many whole records as the back-channel holds, so
       what can be shown is bounded by the region size as well as by the
       buffer and by the rows the list has to itself. */
    count = slot_whole;
    if (count > REC_CAPACITY)
        count = REC_CAPACITY;
    if (count > CFG_MAX_SLOTS)
        count = CFG_MAX_SLOTS;
    if (count > LIST_ROWS)
        count = LIST_ROWS;

    if (count == 0) {
        status_attr("The device reports no flash slots.", A_ERR);
        kbd_flush();
        kbd_wait();
        vid_clear(A_NORM);
        vid_cursor_on();
        return 1;
    }

    if (opt_list) {
        draw_header();
        draw_slots(count, 0xFF);
        status("Press any key.");
        kbd_flush();
        kbd_wait();
    } else {
        menu(count);
    }

    if (!image_clean) {
        /* Worth stopping for. The machine is running on an image with bytes
           in it that do not belong, which a warm boot would checksum. */
        vid_clear(A_NORM);
        vid_puts(10, 2, "The served image was not fully restored.", A_ERR);
        vid_puts(12, 2, "It is safe to keep using the machine, but power it "
                        "off rather than", A_NORM);
        vid_puts(13, 2, "warm booting it: a BIOS checksums its own ROM at "
                        "power-on and this", A_NORM);
        vid_puts(14, 2, "one would now fail that test.", A_NORM);
        status("Press any key.");
        kbd_flush();
        kbd_wait();
    }

    vid_clear(A_NORM);
    vid_cursor_on();
    return image_clean ? 0 : 2;
}
