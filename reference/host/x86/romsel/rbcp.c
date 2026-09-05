/* rbcp.c - ROM Bus Control Protocol host layer for 8088 real mode.

   Nothing here calls the BIOS or DOS. Between the knock and the exit the
   only ROM reads this module makes are command bytes on the command page and
   back-channel reads, which is what the protocol requires: any other read of
   the served image in that window is taken as a command byte. */

#include <i86.h>
#include <conio.h>
#include "rbcp.h"

u8 rb_ram_count   = 0;
u8 rb_ram_active  = 0xFF;
u8 rb_boot_flash  = 0xFF;
u8 rb_boot_ram    = 0xFF;
u8 rb_proto_major = 0;
u8 rb_proto_minor = 0;
u8 rb_proto_patch = 0;

/* Values the device writes into the progress and response fields. Chosen
   against the bytes already at those offsets, so a stale value cannot read
   as a completion. */
u8 rb_complete  = 0xBB;
u8 rb_status_ok = 0xCC;

/* The bytes the back-channel displaces, kept so they can be put back. */
static u8 rb_saved[CFG_BCH_SIZE];
static int rb_have_saved = 0;

#define CMD_BASE  ((u16)(((u16)CFG_CMD_PAGE) * 256U * CFG_STRIDE))
#define BCH_BASE  ((u16)(((u16)CFG_BCH_OFF) * CFG_STRIDE))

#define HDR_LASTCMD  0
#define HDR_TOKEN    2
#define HDR_PROGRESS 4
#define HDR_RESPONSE 5

/* ------------------------------------------------------------------ */
/* Bus access                                                          */
/* ------------------------------------------------------------------ */

/* volatile keeps the compiler from folding, reordering or dropping a read.
   Each of these is exactly one bus cycle on an 8088. */
static volatile u8 rb_sink;

#define ROMP(off) ((volatile u8 __far *)MK_FP(CFG_ROM_SEG, (u16)(off)))

static void rd_off(u16 off)
{
    rb_sink = *ROMP(off);
}

static void send_byte(u8 b)
{
    rd_off((u16)(CMD_BASE + (u16)b * CFG_STRIDE));
}

static u8 bch(u16 n)
{
    return *ROMP(BCH_BASE + n * CFG_STRIDE);
}

/* ------------------------------------------------------------------ */
/* Timing, from PIT channel 0                                          */
/* ------------------------------------------------------------------ */

/* Channel 0 is clocked at 1.193182 MHz. In mode 3, which is how every PC
   BIOS leaves it, the count register steps by two per clock, so 2386 steps
   is a millisecond. In mode 2 it steps by one and the same figure is two
   milliseconds. Both readings are safe here: every use of this is either a
   settling delay, where waiting longer costs nothing, or a timeout, where a
   longer one only delays an error the caller is going to report anyway. */
#define PIT_PER_MS  2386U

static u16 pit_read(void)
{
    u16 lo, hi;
    outp(0x43, 0x00);           /* latch channel 0 */
    lo = (u16)inp(0x40);
    hi = (u16)inp(0x40);
    return (u16)(lo | (hi << 8));
}

/* A deadline, carried across the counter's wrap. Sampling must be more
   frequent than one wrap, which a polling loop always is. */
typedef struct {
    u16 prev;
    u32 acc;
    u32 limit;
} deadline;

static void dl_start(deadline *d, u16 ms)
{
    d->prev  = pit_read();
    d->acc   = 0;
    d->limit = (u32)ms * PIT_PER_MS;
}

static int dl_expired(deadline *d)
{
    u16 now = pit_read();
    d->acc += (u32)(u16)(d->prev - now);   /* the counter runs down */
    d->prev = now;
    return d->acc >= d->limit;
}

void rbcp_delay_ms(u16 ms)
{
    deadline d;
    dl_start(&d, ms);
    while (!dl_expired(&d))
        ;
}

/* ------------------------------------------------------------------ */
/* Framing                                                             */
/* ------------------------------------------------------------------ */

static void knock(void)
{
    send_byte(0x21);            /* ! */
    send_byte(0x52);            /* R */
    send_byte(0x42);            /* B */
    send_byte(0x43);            /* C */
    send_byte(0x50);            /* P */
    send_byte(0x21);            /* ! */
}

static void send_cmd(u8 group, u8 cmd, const u8 *args, u8 n)
{
    u8 i;
    send_byte(group);
    send_byte(cmd);
    for (i = 0; i < n; i++)
        send_byte(args[i]);
}

/* save_token, send, poll token, poll progress, read response. No knock:
   in command-response mode one knock opens the whole session. */
/* Reading the timer costs three port accesses, which on this bus is several
   times what a back-channel read costs. Writing a whole image is thousands of
   these, so the deadline is consulted once every so many spins rather than on
   each one. The counter's wrap is 27 ms away and a batch of spins is well
   under that, so the accumulator still tracks. */
#define POLL_BATCH  32

static int issue(u8 group, u8 cmd, const u8 *args, u8 n, u16 ms)
{
    deadline d;
    u8 spins;
    u8 tok0 = bch(HDR_TOKEN);

    send_cmd(group, cmd, args, n);

    dl_start(&d, ms);
    spins = 0;
    while (bch(HDR_TOKEN) == tok0) {
        if (++spins >= POLL_BATCH) {
            spins = 0;
            if (dl_expired(&d))
                return RB_NO_TOKEN;
        }
    }

    dl_start(&d, ms);
    spins = 0;
    while (bch(HDR_PROGRESS) != rb_complete) {
        if (++spins >= POLL_BATCH) {
            spins = 0;
            if (dl_expired(&d))
                return RB_NO_PROGRESS;
        }
    }

    return (bch(HDR_RESPONSE) == rb_status_ok) ? RB_OK : RB_FAILED;
}

/* ------------------------------------------------------------------ */
/* Session                                                             */
/* ------------------------------------------------------------------ */

void rbcp_save_region(void)
{
    u16 i;
    /* A linear sweep cannot be mistaken for a knock: it produces consecutive
       low address bytes and the knock is six specific non-consecutive ones. */
    for (i = 0; i < CFG_BCH_SIZE; i++)
        rb_saved[i] = bch(i);
    rb_have_saved = 1;
}

u8 rbcp_bch_byte(u16 n)
{
    return bch(n);
}

/* The reset sequence from the specification. Command mode throughout, so
   there is nothing to poll and each step is followed by a wait. */
void rbcp_reset(void)
{
    u8 i;

    for (i = 0; i < 5; i++) {           /* flush any part-collected command */
        send_byte(RB_G_RESET);
        send_byte(RB_RESET_CMD);
    }
    rbcp_delay_ms(CFG_RESET_MS);

    send_byte(RB_G_RESET);              /* reset a now-idle device */
    send_byte(RB_RESET_CMD);
    rbcp_delay_ms(CFG_RESET_MS);

    knock();                            /* again, if it was in command mode */
    send_byte(RB_G_RESET);
    send_byte(RB_RESET_CMD);
    rbcp_delay_ms(CFG_RESET_MS);
}

/* Picks a value for a boolean header field that neither matches the byte
   already there nor its inverse, so a stale byte cannot read as a result.
   0xAA is prohibited by the protocol. */
static u8 pick_bool(u8 preferred, u8 current)
{
    static const u8 candidates[] = { 0xBB, 0xCC, 0x5A, 0x69, 0x96, 0x3C, 0xC3 };
    u8 i;

    if (preferred != current && (u8)(~preferred) != current && preferred != 0xAA)
        return preferred;

    for (i = 0; i < sizeof(candidates); i++) {
        u8 c = candidates[i];
        if (c != current && (u8)(~c) != current && c != 0xAA)
            return c;
    }
    return 0xBB;                        /* unreachable with this table */
}

/* Whether the device implements the commands this program would like but can
   do without. Three of them arrived in 0.1.2: GET_BOOT_SLOT_INFO,
   LOAD_AND_EXIT and EXIT_CMD_RESP_RESTORE.

   Issuing one of those to a device that does not know it is not harmless. A
   command the device has no definition for takes no argument bytes off the
   wire, so the arguments that follow are read as the next command frame. For
   a nine-argument command such as EXIT_CMD_RESP_RESTORE that is nine bytes of
   whatever was in the ROM being decoded as commands the host never issued. */
static int at_least_012(void)
{
    if (rb_proto_major != 0)
        return 1;
    if (rb_proto_minor != 1)
        return 0;           /* 0.0.x, or a 0.2.x this was not written for */
    return rb_proto_patch >= 2;
}

int rbcp_open(void)
{
    u8 args[9];
    u8 tok0;
    deadline d;
    u32 bch_addr = (u32)CFG_BCH_OFF;

    rbcp_reset();

    rb_complete  = pick_bool(0xBB, bch(HDR_PROGRESS));
    rb_status_ok = pick_bool(0xCC, bch(HDR_RESPONSE));

    args[0] = (u8)(CFG_CMD_PAGE & 0xFF);
    args[1] = (u8)((CFG_CMD_PAGE >> 8) & 0xFF);
    args[2] = (u8)(bch_addr & 0xFF);
    args[3] = (u8)((bch_addr >> 8) & 0xFF);
    args[4] = (u8)((bch_addr >> 16) & 0xFF);
    args[5] = (u8)(CFG_BCH_SIZE & 0xFF);
    args[6] = (u8)((CFG_BCH_SIZE >> 8) & 0xFF);
    args[7] = rb_complete;
    args[8] = rb_status_ok;

    /* The token must be snapshotted before the command: the device does not
       initialise it on entry, it increments whatever is already there. */
    tok0 = bch(HDR_TOKEN);

    knock();
    send_cmd(RB_G_CONTROL, RB_C_ENTER_CMD_RESP, args, 9);

    dl_start(&d, CFG_CMD_MS);
    while (bch(HDR_TOKEN) == tok0) {
        if (dl_expired(&d))
            return RB_NO_TOKEN;         /* discarded, or nothing is there */
    }

    dl_start(&d, CFG_CMD_MS);
    while (bch(HDR_PROGRESS) != rb_complete) {
        if (dl_expired(&d))
            return RB_NO_PROGRESS;
    }

    return (bch(HDR_RESPONSE) == rb_status_ok) ? RB_OK : RB_FAILED;
}

/* A single-byte write outside command-response mode. Command mode gives every
   command its own session, so this knocks first and waits afterwards rather
   than polling something that is not being maintained. */
static void cmd_mode_poke(u8 byte, u32 addr, u8 slot)
{
    u8 args[5];
    args[0] = byte;
    args[1] = (u8)(addr & 0xFF);
    args[2] = (u8)((addr >> 8) & 0xFF);
    args[3] = (u8)((addr >> 16) & 0xFF);
    args[4] = slot;
    knock();
    send_cmd(RB_G_MODIFY, RB_M_SLOT_POKE, args, 5);
    rbcp_delay_ms(CFG_RESET_MS);
}

int rbcp_close_restore(void)
{
    u8 args[9];
    u16 i;
    int clean = 1;

    /* Reloading the active slot from flash would put the whole region back in
       one command, but only where the slot still holds the image that flash
       slot contains, which nothing on the device can confirm. Writing back
       the bytes that were read is exact and depends on nothing.

       Each poke dirties only the header, which the exit then covers with the
       bytes that belong there. */
    if (!rb_have_saved || rb_ram_active == 0xFF || rb_ram_active == 0xAA) {
        /* Nothing to write back with. The exit below still puts the header
           right, so only the data section of the region stays displaced. */
        clean = 0;
    } else {
        for (i = 8; i < CFG_BCH_SIZE; i++) {
            u32 addr = (u32)CFG_BCH_OFF + i;

            /* Only the bytes the device actually wrote need putting back, and
               the tail of the region beyond the longest response it sent is
               usually untouched. Every command skipped here is time the
               machine spends with interrupts disabled and does not have to. */
            if (bch(i) == rb_saved[i])
                continue;

            if (rbcp_slot_poke(rb_saved[i], addr, rb_ram_active) != RB_OK) {
                clean = 0;
                break;
            }
        }
    }

    if (!rb_have_saved) {
        send_cmd(RB_G_CONTROL, RB_C_EXIT_SILENT, 0, 0);
        rbcp_delay_ms(CFG_RESET_MS);
        return 0;
    }

    if (at_least_012()) {
        /* One command puts the header back and leaves at the same time. */
        for (i = 0; i < 8; i++)
            args[i] = rb_saved[i];
        args[8] = 8;
        send_cmd(RB_G_CONTROL, RB_C_EXIT_RESTORE, args, 9);
        rbcp_delay_ms(CFG_RESET_MS);
        return clean;
    }

    /* Without that command the header cannot be put back from inside the
       session, because every write updates it again. Leave first, which the
       silent exit does without touching it, and write the eight bytes in
       command mode, where the device maintains no back-channel at all.

       Each of those is its own session and there is nothing to poll, so each
       carries its own knock and its own wait. */
    send_cmd(RB_G_CONTROL, RB_C_EXIT_SILENT, 0, 0);
    rbcp_delay_ms(CFG_RESET_MS);

    if (rb_ram_active == 0xFF || rb_ram_active == 0xAA)
        return 0;

    for (i = 0; i < 8; i++)
        cmd_mode_poke(rb_saved[i], (u32)CFG_BCH_OFF + i, rb_ram_active);

    return clean;
}

void rbcp_exit_silent(void)
{
    send_cmd(RB_G_CONTROL, RB_C_EXIT_SILENT, 0, 0);
    rbcp_delay_ms(CFG_RESET_MS);
}

/* LOAD_SLOT issued in command mode, for loading over the slot the processor
   is reading. Doing it here rather than with LOAD_AND_EXIT means the device
   maintains no back-channel while the copy runs, so the image that lands is
   the flash image and nothing writes a response header into it. */
void rbcp_load_slot_cmd_mode(u8 ram_slot, u8 flash_slot)
{
    u8 args[2];
    args[0] = ram_slot;
    args[1] = flash_slot;
    knock();
    send_cmd(RB_G_MODIFY, RB_M_LOAD_SLOT, args, 2);
}

/* ------------------------------------------------------------------ */
/* Commands                                                            */
/* ------------------------------------------------------------------ */

int rbcp_get_protocol_version(void)
{
    int r = issue(RB_G_READ, RB_R_PROTOCOL_VERSION, 0, 0, CFG_CMD_MS);
    if (r == RB_OK) {
        rb_proto_major = bch(8);
        rb_proto_minor = bch(9);
        rb_proto_patch = bch(10);
    }
    return r;
}

/* Both of these are 24 bytes of null-terminated ASCII at the start of the
   response data section. The device version is the implementation's own, and
   is not the protocol revision it implements: a plugin numbered one way may
   report another from GET_PROTOCOL_VERSION, and it is the latter that says
   which commands may be issued. */
static int get_ascii(u8 cmd, char *buf, u8 len)
{
    u8 i;
    int r = issue(RB_G_READ, cmd, 0, 0, CFG_CMD_MS);

    buf[0] = 0;
    if (r != RB_OK)
        return r;

    for (i = 0; i < len - 1 && i < 24; i++) {
        u8 c = bch((u16)(8 + i));
        if (c == 0)
            break;
        buf[i] = (c >= 0x20 && c < 0x7F) ? (char)c : '.';
    }
    buf[i] = 0;
    return RB_OK;
}

int rbcp_get_device_type(char *buf, u8 len)
{
    return get_ascii(RB_R_DEVICE_TYPE, buf, len);
}

int rbcp_get_device_version(char *buf, u8 len)
{
    return get_ascii(RB_R_DEVICE_VERSION, buf, len);
}

int rbcp_get_ram_slot_info(void)
{
    int r = issue(RB_G_READ, RB_R_RAM_SLOT_INFO_ALL, 0, 0, CFG_CMD_MS);
    if (r == RB_OK) {
        rb_ram_count  = bch(8);
        rb_ram_active = bch(9);
    }
    return r;
}

int rbcp_get_boot_slot_info(void)
{
    int r;

    /* Older than the command. The fields keep the value the protocol itself
       uses for a device that does not know, which is what this is. */
    if (!at_least_012())
        return RB_OK;

    r = issue(RB_G_READ, RB_R_BOOT_SLOT_INFO, 0, 0, CFG_CMD_MS);
    if (r == RB_OK) {
        rb_boot_flash = bch(8);
        rb_boot_ram   = bch(9);
    }
    return r;
}

int rbcp_get_flash_slot_info_all(u8 *total, u8 *whole, u8 *buf, u16 buflen)
{
    u16 i;
    int r = issue(RB_G_READ, RB_R_FLASH_SLOT_INFO_ALL, 0, 0, CFG_CMD_MS);
    if (r != RB_OK)
        return r;

    *total = bch(8);
    *whole = bch(9);
    /* bch(10) is the partial-record flag, which a caller reading whole
       records only has no use for. */

    for (i = 0; i < buflen && (u16)(12 + i) < CFG_BCH_SIZE; i++)
        buf[i] = bch((u16)(12 + i));

    return RB_OK;
}

int rbcp_load_slot(u8 ram_slot, u8 flash_slot)
{
    u8 args[2];
    args[0] = ram_slot;
    args[1] = flash_slot;
    return issue(RB_G_MODIFY, RB_M_LOAD_SLOT, args, 2, CFG_LOAD_MS);
}

/* Writes a whole image into a RAM slot, a byte to a command, reporting
   progress as it goes so a machine spending half a minute on this does not
   look like one that has stopped.

   The slot must not be the active one. The back-channel this polls is a
   region of the active slot, so writing over that slot would take the polling
   window out from under the loop, quite apart from what it would do to the
   image the processor is reading. */
int rbcp_write_image(const u8 *img, u16 len, u8 slot, rbcp_progress_fn report)
{
    u16 i;

    if (slot == 0xFF || slot == 0xAA || slot == rb_ram_active)
        return RB_FAILED;

    for (i = 0; i < len; i++) {
        int r = rbcp_slot_poke(img[i], (u32)i, slot);
        if (r != RB_OK)
            return r;

        /* Often enough to look continuous, rarely enough not to be felt. */
        if (report && (i & 0x7F) == 0x7F)
            report(i + 1, len);
    }

    if (report)
        report(len, len);

    return RB_OK;
}

int rbcp_slot_poke(u8 byte, u32 addr, u8 slot)
{
    u8 args[5];
    args[0] = byte;
    args[1] = (u8)(addr & 0xFF);
    args[2] = (u8)((addr >> 8) & 0xFF);
    args[3] = (u8)((addr >> 16) & 0xFF);
    args[4] = slot;
    return issue(RB_G_MODIFY, RB_M_SLOT_POKE, args, 5, CFG_CMD_MS);
}

/* Terminal. The device begins serving the new slot at once and writes no
   response, so the back-channel must not be read after this returns. */
void rbcp_switch_and_exit(u8 ram_slot)
{
    u8 args[1];
    args[0] = ram_slot;
    send_cmd(RB_G_CONTROL, RB_C_SWITCH_AND_EXIT, args, 1);
}
