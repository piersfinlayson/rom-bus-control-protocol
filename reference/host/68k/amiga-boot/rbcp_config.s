; rbcp_config.s — RBCP configuration for the Amiga Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Target: Amiga A500 (68000, 16-bit bus) with a single word-organised (x16)
; Kickstart ROM.  Both 256 KB and 512 KB Kickstart sizes are supported.
; Change CONFIG_ROM_KB below and everything else follows.
;
; CONFIG_BUS_WIDTH 32 targets a 32-bit Amiga, the A1200 for example, with a
; pair of x16 devices each serving half of a 512 KB Kickstart.  `make BUS=32`
; sets it.
; CONFIG_DEV_KB is then each device's size, 256 for a 27C200 or 512 for a
; 27C400.

    ifnd CONFIG_BUS_WIDTH
CONFIG_BUS_WIDTH            EQU 16              ; 16 or 32
    endc

; Every loop count is multiplied by CONFIG_LOOP_SCALE, because a 32-bit Amiga
; runs a loop faster than the A500.  MAME runs the RBCP poll loop up to 9.1
; times as fast, on an A4000.
    ifeq CONFIG_BUS_WIDTH-32
CONFIG_LOOP_SCALE           EQU 10
    else
CONFIG_LOOP_SCALE           EQU 1
    endc

; ---------------------------------------------------------------------------
; ROM geometry
;
; The Amiga maps its Kickstart ROM at the top of the 16 MB address space, so
; the base address falls out of the size.  256 KB gives $FC0000, 512 KB gives
; $F80000.  The Makefile reads CONFIG_ROM_KB from this file to size-check the
; output image, so keep the "EQU <number>" form on that line.
; ---------------------------------------------------------------------------
    ifnd CONFIG_ROM_KB
CONFIG_ROM_KB               EQU 256             ; 256 or 512
    endc
CONFIG_ROM_BASE             EQU ($1000000-(CONFIG_ROM_KB*1024))

; A 27C400 has one more address line than half a Kickstart uses, A17 on
; pin 1.  The A1200 wires it to CPU A19, which is high from $F80000 to
; $FFFFFF, so the CPU reads the top half of each device.
    ifeq CONFIG_BUS_WIDTH-32
    ifnd CONFIG_DEV_KB
CONFIG_DEV_KB               EQU 256             ; 256 or 512
    endc
CONFIG_RBCP_DEV_BASE        EQU ($1000000-(CONFIG_DEV_KB*1024*2))
    endc

; ---------------------------------------------------------------------------
; Bus mapping — see the BUS MAPPING commentary in rbcp_defs.s
;
; One x16 device on a 16-bit bus:
;   BUS_SHIFT  1  one device bus cycle is 2 CPU address bytes
;   DEV_SHIFT  1  the device supplies 2 bytes per bus cycle
;   DEV_MASK   1  region offset bit 0 selects within the pair
;   LANE_OFF   0  the device occupies the whole bus width
;   ENDIAN_XOR 1  the specification puts the even region offset on D0-D7,
;                 which on a big-endian 68K is the HIGHER CPU address of the
;                 pair — so the two bytes of every device word appear at the
;                 opposite CPU addresses to their region offsets
;
; The Amiga reads Kickstart as 16-bit words, so the device observes the ROM's
; word address lines and one command byte advances the CPU address by 2.
;
; Two x16 devices on a 32-bit bus differ in:
;   BUS_SHIFT  2  one device bus cycle is 4 CPU address bytes
;   DEVICES    2  the high word's device at LANE_OFF, the low word's 2 CPU
;                 bytes on
; ---------------------------------------------------------------------------
    ifeq CONFIG_BUS_WIDTH-32
CONFIG_RBCP_BUS_SHIFT       EQU 2
CONFIG_RBCP_DEVICES         EQU 2
    else
CONFIG_RBCP_BUS_SHIFT       EQU 1
    endc
CONFIG_RBCP_DEV_SHIFT       EQU 1
CONFIG_RBCP_DEV_MASK        EQU 1
CONFIG_RBCP_LANE_OFF        EQU 0
CONFIG_RBCP_ENDIAN_XOR      EQU 1

; ---------------------------------------------------------------------------
; ROM image layout
;
;   CONFIG_ROM_BASE .. $FFFBFF   application code and data
;   $FFFC00 .. $FFFDFF           back-channel region  (512 bytes, zeroed)
;   $FFFE00 .. $FFFFFF           command page         (512 bytes, zeroed)
;
; On a 32-bit bus each region spans twice the CPU bytes, so the back-channel
; starts at $FFF800 and the command page at $FFFC00.
;
; Both regions sit at the very top of the image so the application area is
; unencumbered, and both are identical for 256 KB and 512 KB because the ROM
; is top-aligned.  The device-side values (the command page number and the
; back-channel start offset) differ between the two sizes, and rbcp_defs.s
; derives them from CONFIG_RBCP_DEV_BASE.
;
; One command page spans 256 device bus cycles = 256 << BUS_SHIFT CPU bytes.
; The back-channel spans (SIZE >> DEV_SHIFT) << BUS_SHIFT CPU bytes, which
; for a x16 device on a 16-bit bus happens to equal SIZE — but does not in
; general, so it is written out rather than assumed.
; ---------------------------------------------------------------------------
CONFIG_RBCP_BCH_SIZE        EQU 512             ; DEVICE bytes, incl. header

CONFIG_RBCP_CMD_PAGE_ABS    EQU ($1000000-(256<<CONFIG_RBCP_BUS_SHIFT))
CONFIG_RBCP_BCH_ABS         EQU (CONFIG_RBCP_CMD_PAGE_ABS-((CONFIG_RBCP_BCH_SIZE>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT))

; ---------------------------------------------------------------------------
; Complete and status-OK sentinel values
;
; The back-channel region is zeroed in the ROM image, so $00 is what sits at
; the progress and response locations before the device takes them over.
; Neither $BB/$44 nor $CC/$33 collides with that.  Neither may be $AA.
; ---------------------------------------------------------------------------
CONFIG_RBCP_COMPLETE        EQU $BB             ; inverse $44 = pending
CONFIG_RBCP_STATUS_OK       EQU $CC             ; inverse $33 = failed

; ---------------------------------------------------------------------------
; Timeouts and retries — counts of a poll, and 0 = forever.
;
; One turn of the poll loop in rbcp.s is 46 cycles, 6.5us at 7.09MHz, so a
; count here is that many 6.5us turns.  The times are an A500's, and on every
; MAME machine the 32-bit build's last at least as long.  Somebody is watching the menu
; while these run, so a device that has stopped answering has to be given up
; on while they are still willing to wait.
; ---------------------------------------------------------------------------
CONFIG_RBCP_POLL_TIMEOUT    EQU $0000FFFF*CONFIG_LOOP_SCALE ; 0.43s, and LOAD_SLOT polls on it
CONFIG_RBCP_NV_POLL_TIMEOUT EQU $00080000*CONFIG_LOOP_SCALE ; 3.4s, against a flash erase of ms
CONFIG_RBCP_TIMEOUT_RETRIES EQU 3
CONFIG_RBCP_CMD_PAUSE       EQU $100*CONFIG_LOOP_SCALE      ; inter-command gap, cmd mode

; SET_AUX with a hold waits on its own timeout rather than the NV one, because
; the two bound unrelated things.  A hold runs to 2.55 seconds and the device
; answers only once it has elapsed.
CONFIG_RBCP_AUX_POLL_TIMEOUT EQU $000C0000*CONFIG_LOOP_SCALE ; 5.1s, over the longest hold

; ---------------------------------------------------------------------------
; Scratch RAM used by the RBCP library — 32 bytes of chip RAM, clear of the
; exception vector table.
; ---------------------------------------------------------------------------
CONFIG_RBCP_SCRATCH_BASE    EQU $00001000
CONFIG_RBCP_SCRATCH_SIZE    EQU 32

; ---------------------------------------------------------------------------
; Un-swap buffer for the response data section
;
; rbcp_read_data copies a run of device bytes out of the back-channel data
; section into this linear chip RAM buffer, undoing the word-ROM byte
; transposition, so response records and strings are read with a plain
; incrementing pointer — exactly as an 8-bit host reads them in place.  One
; 32-byte slot record is the largest thing read, so 48 bytes covers every
; response with room to spare.  It sits in the application variable area, so
; the 68000 reaches it with absolute short addressing — see the chip RAM
; layout in amiga_defs.s.
; ---------------------------------------------------------------------------
CONFIG_RBCP_DATA_BUF        EQU $00002200
CONFIG_RBCP_DATA_BUF_SIZE   EQU 48
