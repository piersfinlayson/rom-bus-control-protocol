; rbcp_config.s — RBCP configuration for the Amiga Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Target: Amiga A500 (68000, 16-bit bus) with a single word-organised (x16)
; Kickstart ROM.  Both 256 KB and 512 KB Kickstart sizes are supported;
; change CONFIG_ROM_KB below and everything else follows.

; ---------------------------------------------------------------------------
; ROM geometry
;
; The Amiga maps its Kickstart ROM at the top of the 16 MB address space, so
; the base address falls out of the size.  256 KB gives $FC0000, 512 KB gives
; $F80000.  The Makefile reads CONFIG_ROM_KB from this file to size-check the
; output image, so keep the "EQU <number>" form on that line.
; ---------------------------------------------------------------------------
CONFIG_ROM_KB               EQU 256             ; 256 or 512
CONFIG_ROM_BASE             EQU ($1000000-(CONFIG_ROM_KB*1024))

; ---------------------------------------------------------------------------
; Bus mapping — see the BUS MAPPING commentary in rbcp_defs.s
;
; One x16 device on a 16-bit bus:
;   BUS_SHIFT  1  one device bus cycle is 2 CPU address bytes
;   DEV_SHIFT  1  the device supplies 2 bytes per bus cycle
;   DEV_MASK   1  ...so region offset bit 0 selects within the pair
;   LANE_OFF   0  the device occupies the whole bus width
;   ENDIAN_XOR 1  the specification puts the even region offset on D0-D7,
;                 which on a big-endian 68K is the HIGHER CPU address of the
;                 pair — so the two bytes of every device word appear at the
;                 opposite CPU addresses to their region offsets
;
; The Amiga reads Kickstart as 16-bit words, so the device observes the ROM's
; word address lines and one command byte advances the CPU address by 2.
; ---------------------------------------------------------------------------
CONFIG_RBCP_BUS_SHIFT       EQU 1
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
; Both regions sit at the very top of the image so the application area is
; unencumbered, and both are identical for 256 KB and 512 KB because the ROM
; is top-aligned.  The device-side values (the command page number and the
; back-channel start offset) differ between the two sizes, and rbcp_defs.s
; derives them from CONFIG_ROM_BASE.
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
; Timeouts and retries — arbitrary loop counts, no fixed unit.  0 = forever.
; ---------------------------------------------------------------------------
CONFIG_RBCP_POLL_TIMEOUT    EQU $0000FFFF
CONFIG_RBCP_NV_POLL_TIMEOUT EQU $00FFFFFF       ; flash erase takes ms
CONFIG_RBCP_TIMEOUT_RETRIES EQU 3
CONFIG_RBCP_CMD_PAUSE       EQU $100            ; inter-command gap, cmd mode

; ---------------------------------------------------------------------------
; Scratch RAM used by the RBCP library — 32 bytes of chip RAM, clear of the
; exception vector table.
; ---------------------------------------------------------------------------
CONFIG_RBCP_SCRATCH_BASE    EQU $00001000
CONFIG_RBCP_SCRATCH_SIZE    EQU 32
