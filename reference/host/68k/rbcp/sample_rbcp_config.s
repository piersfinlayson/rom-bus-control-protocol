; sample_rbcp_config.s — annotated sample RBCP configuration for a 68K host
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Copy this into your application directory as rbcp_config.s and edit it.
; Include it before rbcp_defs.s, which derives everything else from it.
;
; The values here describe an Amiga A500: a 68000 with a 16-bit bus and a
; single word-organised (x16) 256 KB Kickstart ROM.

; ---------------------------------------------------------------------------
; ROM geometry
;
; CONFIG_ROM_BASE is the CPU address the ROM is mapped at, and CONFIG_ROM_KB
; its size.  On the Amiga the ROM is top-aligned in the 16 MB address space,
; so the base follows from the size; on other systems set it directly.
; ---------------------------------------------------------------------------
CONFIG_ROM_KB               EQU 256
CONFIG_ROM_BASE             EQU ($1000000-(CONFIG_ROM_KB*1024))

; ===========================================================================
; BUS MAPPING
;
; These five constants describe how the device sits on the host's bus.  They
; are the only place the host's width, the device's width, and the host's
; byte order enter the library.  See the BUS MAPPING commentary in
; rbcp_defs.s for the two formulae they feed.
;
; BUS_SHIFT   log2 of the CPU address stride of one device bus cycle.
;             1 for a 16-bit bus, 2 for a 32-bit bus.  This is what makes a
;             command byte advance the CPU address by more than one: the
;             device's observed A0 is the CPU line just above the bus's
;             byte-select lines.
;
; DEV_SHIFT   log2 of the number of bytes the device supplies per bus cycle.
;             0 for an 8-bit device, 1 for a x16 device.
;
; DEV_MASK    (1 << DEV_SHIFT) - 1.
;
; LANE_OFF    CPU byte offset of this device's lane within one bus cycle.
;             0 for a device that occupies the full bus width.
;
; ENDIAN_XOR  1 where the host's byte order within a bus cycle is opposite
;             to the specification's data-line assignment, 0 otherwise.
;             The specification places the even back-channel offset on
;             D0-D7; on a big-endian 68K that is the HIGHER CPU address of a
;             16-bit pair, so a x16 device needs 1 here.  An 8-bit device
;             has no intra-cycle ordering, so it needs 0.
;
; Configurations:
;
;                                          BUS DEV DEV LANE ENDIAN
;                                          SHF SHF MSK  OFF   XOR
;   One x16 device, 16-bit bus  (A500)      1   1   1    0     1
;   Two 8-bit devices, 16-bit bus, hi lane  1   0   0    0     0
;                                 lo lane   1   0   0    1     0
;   Two x16 devices, 32-bit bus,  hi word   2   1   1    0     1
;                                 lo word   2   1   1    2     1
;   Four 8-bit devices, 32-bit bus, lane L  2   0   0    L     0
;
; Only the first is exercised today.  Note that on a multi-device bus the
; address lines are shared, so every device decodes every knock and every
; command, and each maintains its OWN complete back-channel header — the
; headers interleave in CPU address space at the bus stride, they do not
; merge.  A host on such a bus must poll every lane's header before treating
; a command as complete; this library polls one.
; ===========================================================================
CONFIG_RBCP_BUS_SHIFT       EQU 1
CONFIG_RBCP_DEV_SHIFT       EQU 1
CONFIG_RBCP_DEV_MASK        EQU 1
CONFIG_RBCP_LANE_OFF        EQU 0
CONFIG_RBCP_ENDIAN_XOR      EQU 1

; ---------------------------------------------------------------------------
; Command page and back-channel placement
;
; Both are given as CPU addresses; rbcp_defs.s converts them into the device
; terms that ENTER_CMD_RESP actually takes — a command page number counted in
; device bus cycles, and a back-channel start counted in device bytes.  The
; two are not the same numbers, which is the point of doing it here once.
;
; A command page spans 256 device bus cycles.  The back-channel spans
; (SIZE >> DEV_SHIFT) << BUS_SHIFT CPU bytes.  Placing them at the top of the
; image keeps the application area contiguous, and keeps the command page out
; of the way of ordinary ROM reads.
;
; CONFIG_RBCP_BCH_SIZE is in DEVICE bytes and includes the 8-byte response
; header.  The resulting start offset must be 4-byte aligned; rbcp_defs.s
; asserts this at build time.
; ---------------------------------------------------------------------------
CONFIG_RBCP_BCH_SIZE        EQU 512

CONFIG_RBCP_CMD_PAGE_ABS    EQU ($1000000-(256<<CONFIG_RBCP_BUS_SHIFT))
CONFIG_RBCP_BCH_ABS         EQU (CONFIG_RBCP_CMD_PAGE_ABS-((CONFIG_RBCP_BCH_SIZE>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT))

; ---------------------------------------------------------------------------
; Complete and status-OK sentinel values
;
; RBCP uses these AND their bitwise inverses, so both must be absent from the
; progress and response locations of the ROM image.  Reserving the region and
; zero-filling it, as the sample application does, makes that automatic.
; Neither value may be $AA — rbcp_defs.s asserts this at build time.
; ---------------------------------------------------------------------------
CONFIG_RBCP_COMPLETE        EQU $BB             ; inverse $44 = pending
CONFIG_RBCP_STATUS_OK       EQU $CC             ; inverse $33 = failed

; ---------------------------------------------------------------------------
; Timeouts and retries — arbitrary 32-bit loop counts, no fixed unit.
; 0 = wait forever.
; ---------------------------------------------------------------------------
CONFIG_RBCP_POLL_TIMEOUT    EQU $0000FFFF
CONFIG_RBCP_NV_POLL_TIMEOUT EQU $00FFFFFF       ; flash erase takes ms
CONFIG_RBCP_TIMEOUT_RETRIES EQU 3

; Blind delay after a command sent in command mode, where there is no
; back-channel to tell the host when the device is ready for the next one.
CONFIG_RBCP_CMD_PAUSE       EQU $100

; ---------------------------------------------------------------------------
; Scratch RAM used by the library — the 68K has no zero page, so a fixed
; block stands in for the 6502 ZP convention.  32 bytes, clear of the
; exception vector table, and in RAM the ROM switch cannot disturb.
; ---------------------------------------------------------------------------
CONFIG_RBCP_SCRATCH_BASE    EQU $00001000
CONFIG_RBCP_SCRATCH_SIZE    EQU 32
