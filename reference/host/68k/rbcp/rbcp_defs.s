; rbcp_defs.s — RBCP protocol constants, bus mapping, and scratch RAM layout
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Include the platform rbcp_config.s before this file.
;
; This file is generic across 68K platforms.  Everything platform-specific
; is supplied by rbcp_config.s; everything derived from it lives here.

; ---------------------------------------------------------------------------
; Protocol version supported by this library
; ---------------------------------------------------------------------------
RBCP_SUPPORTED_MAJOR        EQU 0
RBCP_SUPPORTED_MINOR        EQU 1
RBCP_SUPPORTED_PATCH        EQU 1

; ===========================================================================
; BUS MAPPING
;
; RBCP is defined in terms of the address and data lines the *device*
; observes at the ROM socket.  On a 68K host those are not in general the
; CPU's own lines, so the library maps between the two using five constants
; supplied by rbcp_config.s.  Both directions are covered.
;
; --- Host-to-device (command) direction -----------------------------------
;
; Per the specification, a command byte is sent by reading at an address
; whose observed A0-A7 equal the byte's value, and successive command bytes
; advance the least-significant observed line by one.  The device's observed
; A0 is always the CPU address line immediately above the bus's byte-select
; lines, so:
;
;     cpu_addr(byte) = CMD_PAGE_ABS + (byte << BUS_SHIFT)
;
; where 1<<BUS_SHIFT is the CPU address stride of one bus cycle: 2 for a
; 16-bit bus, 4 for a 32-bit bus.
;
; --- Device-to-host (back-channel) direction ------------------------------
;
; The back-channel is a region of *device* bytes.  Region byte N appears at:
;
;     cpu_addr(N) = BCH_ABS
;                 + ((N >> DEV_SHIFT) << BUS_SHIFT)   ; which bus cycle
;                 + LANE_OFF                          ; which device on the bus
;                 + ((N & DEV_MASK) EOR ENDIAN_XOR)   ; which byte within it
;
; DEV_SHIFT/DEV_MASK describe the device's own width (0/0 for an 8-bit
; device, 1/1 for a x16 device).  LANE_OFF is the CPU byte offset of this
; device's lane within one bus cycle.  ENDIAN_XOR accounts for the 68K being
; big-endian while the specification assigns region byte offsets to data
; lines: it places the even region offset on D0-D7, which on a 68K is the
; *higher* CPU address of the pair.
;
; --- Supported configurations ---------------------------------------------
;
; Configuration                          BUS DEV DEV LANE ENDIAN
;                                        SHF SHF MSK  OFF   XOR
; One x16 device, 16-bit bus  (A500)      1   1   1    0     1
; Two 8-bit devices, 16-bit bus, hi lane  1   0   0    0     0
;                               lo lane   1   0   0    1     0
; Two x16 devices, 32-bit bus,  hi word   2   1   1    0     1
;                               lo word   2   1   1    2     1
; Four 8-bit devices, 32-bit bus, lane L  2   0   0    L     0
;
; Only the first row is exercised today.  The others are recorded because
; they are the shape the mapping must keep, not because they are tested.
;
; NOTE for multi-device configurations: address lines are shared, so every
; device on the bus decodes every knock and every command.  Each maintains
; its own complete back-channel header, and those headers interleave in CPU
; address space at the stride above — they are not merged.  Completion is
; therefore per-device and unsynchronised: a host must poll every lane's
; header before treating a command as complete.  The library as written
; polls one lane and is correct only for a single-device bus.
; ===========================================================================

RBCP_BUS_STRIDE     EQU (1<<CONFIG_RBCP_BUS_SHIFT)

; Intra-bus-cycle CPU byte offset for an even and an odd region offset.
; Computed arithmetically rather than with XOR so the expression does not
; depend on the assembler's choice of operator for exclusive-or.
; For x in {0,1} and e in {0,1}:  x EOR e  ==  x + e - 2*x*e
RBCP_INTRA_EVEN     EQU CONFIG_RBCP_ENDIAN_XOR
RBCP_INTRA_ODD      EQU (CONFIG_RBCP_DEV_MASK+CONFIG_RBCP_ENDIAN_XOR-(2*CONFIG_RBCP_DEV_MASK*CONFIG_RBCP_ENDIAN_XOR))

; ---------------------------------------------------------------------------
; Derived ROM geometry
; ---------------------------------------------------------------------------
CONFIG_ROM_SIZE     EQU (CONFIG_ROM_KB*1024)

; ---------------------------------------------------------------------------
; Derived RBCP parameters, as sent to the device
;
; RBCP_CMD_PAGE_REL — the command page: the observed address bits above A7.
;   The observed lines are the device's, so the CPU-relative offset must be
;   converted to a device bus-cycle index before taking the page number.
;
; RBCP_BCH_START — the back-channel start address as a *device byte* offset
;   within the slot, which is what ENTER_CMD_RESP takes.  Must be 4-byte
;   aligned; the assertion below enforces that at build time.
; ---------------------------------------------------------------------------
RBCP_CMD_PAGE_REL   EQU (((CONFIG_RBCP_CMD_PAGE_ABS-CONFIG_ROM_BASE)>>CONFIG_RBCP_BUS_SHIFT)>>8)
RBCP_BCH_START      EQU (((CONFIG_RBCP_BCH_ABS-CONFIG_ROM_BASE)>>CONFIG_RBCP_BUS_SHIFT)<<CONFIG_RBCP_DEV_SHIFT)

; CPU address span of the back-channel region, for reserving it in the image.
RBCP_BCH_CPU_SPAN   EQU ((CONFIG_RBCP_BCH_SIZE>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)

; CPU address span of one command page (256 device bus cycles).
RBCP_CMD_PAGE_SPAN  EQU (256<<CONFIG_RBCP_BUS_SHIFT)

; ---------------------------------------------------------------------------
; Completion / status values derived from config
; ---------------------------------------------------------------------------
RBCP_COMPLETE               EQU CONFIG_RBCP_COMPLETE
RBCP_PENDING                EQU ((~CONFIG_RBCP_COMPLETE)&$FF)
RBCP_STATUS_OK              EQU CONFIG_RBCP_STATUS_OK
RBCP_FAILED                 EQU ((~CONFIG_RBCP_STATUS_OK)&$FF)

; ---------------------------------------------------------------------------
; Knock sequence bytes: "!RBCP!"
; ---------------------------------------------------------------------------
RBCP_KNOCK_0                EQU $21     ; '!'
RBCP_KNOCK_1                EQU $52     ; 'R'
RBCP_KNOCK_2                EQU $42     ; 'B'
RBCP_KNOCK_3                EQU $43     ; 'C'
RBCP_KNOCK_4                EQU $50     ; 'P'
RBCP_KNOCK_5                EQU $21     ; '!'
RBCP_KNOCK_LEN              EQU 6

; ---------------------------------------------------------------------------
; Command groups
; ---------------------------------------------------------------------------
RBCP_GRP_CTRL               EQU $00
RBCP_GRP_READ               EQU $01
RBCP_GRP_MODIFY             EQU $02
RBCP_GRP_NV                 EQU $03
RBCP_GRP_RESET              EQU $AA

; ---------------------------------------------------------------------------
; Group 0x00 — Control
; ---------------------------------------------------------------------------
RBCP_CMD_NOP                EQU $00
RBCP_CMD_ENTER_CMD_RESP     EQU $01
RBCP_CMD_EXIT_CMD_RESP_ACK  EQU $02
RBCP_CMD_EXIT_SILENT        EQU $03
RBCP_CMD_SWITCH_AND_EXIT    EQU $04

; ---------------------------------------------------------------------------
; Group 0x01 — Read
; ---------------------------------------------------------------------------
RBCP_CMD_GET_FLASH_COUNT    EQU $00
RBCP_CMD_GET_FLASH_INFO     EQU $01
RBCP_CMD_GET_FLASH_INFO_ALL EQU $02
RBCP_CMD_GET_RAM_INFO_ALL   EQU $03
RBCP_CMD_GET_DEVICE_TYPE    EQU $04
RBCP_CMD_GET_DEVICE_VERSION EQU $05
RBCP_CMD_GET_PROTO_VERSION  EQU $06
RBCP_CMD_SLOT_PEEK          EQU $07

; ---------------------------------------------------------------------------
; Group 0x02 — Modify
; ---------------------------------------------------------------------------
RBCP_CMD_SLOT_POKE          EQU $00
RBCP_CMD_SWITCH_SLOT        EQU $01
RBCP_CMD_LOAD_SLOT          EQU $02
RBCP_CMD_SLOT_POKE_ALL      EQU $03

; ---------------------------------------------------------------------------
; Group 0x03 — NV Storage
; ---------------------------------------------------------------------------
RBCP_CMD_GET_NV_CAP         EQU $00
RBCP_CMD_NV_PEEK            EQU $01
RBCP_CMD_NV_POKE_BEGIN      EQU $02
RBCP_CMD_NV_POKE            EQU $03
RBCP_CMD_NV_POKE_COMMIT     EQU $04
RBCP_CMD_NV_POKE_DISCARD    EQU $05
RBCP_CMD_NV_POKE_COMMIT_BYTE EQU $06

; ---------------------------------------------------------------------------
; Group 0xAA — Reset
; ---------------------------------------------------------------------------
RBCP_CMD_RESET              EQU $AA

; ---------------------------------------------------------------------------
; Back-channel response header — CPU addresses
;
; Region layout (device byte offsets within the back-channel region):
;   +0  last command GROUP
;   +1  last command CMD
;   +2  token LSB
;   +3  token MSB
;   +4  progress
;   +5  response
;   +6  reserved (2 bytes)
;   +8  response data
;
; Each is mapped through the formula documented above.  Note that the two
; token bytes are NOT adjacent in CPU address space on a x16 device, and
; must never be read as a single word in any case: the specification
; guarantees atomicity only for individual byte writes, so a word read can
; catch a torn LSB/MSB pair.  The polling sequence reads the LSB alone.
; ---------------------------------------------------------------------------
RBCP_LASTCMD_GRP_ADDR EQU CONFIG_RBCP_BCH_ABS+(((0>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_EVEN)
RBCP_LASTCMD_CMD_ADDR EQU CONFIG_RBCP_BCH_ABS+(((1>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_ODD)
RBCP_TOKEN_LSB_ADDR   EQU CONFIG_RBCP_BCH_ABS+(((2>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_EVEN)
RBCP_TOKEN_MSB_ADDR   EQU CONFIG_RBCP_BCH_ABS+(((3>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_ODD)
RBCP_PROGRESS_ADDR    EQU CONFIG_RBCP_BCH_ABS+(((4>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_EVEN)
RBCP_RESPONSE_ADDR    EQU CONFIG_RBCP_BCH_ABS+(((5>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_ODD)

; Response data begins at region offset 8.  A CPU address for a *fixed* data
; offset can be formed with the same expression, but a linear index into the
; data section is NOT a linear CPU offset — a runtime mapper is required for
; variable-length reads.  That arrives with the commands that need it.
RBCP_DATA0_ADDR       EQU CONFIG_RBCP_BCH_ABS+(((8>>CONFIG_RBCP_DEV_SHIFT)<<CONFIG_RBCP_BUS_SHIFT)+CONFIG_RBCP_LANE_OFF+RBCP_INTRA_EVEN)

; ---------------------------------------------------------------------------
; Build-time assertions
; ---------------------------------------------------------------------------
    IFNE (RBCP_BCH_START&3)
        FAIL "CONFIG_RBCP_BCH_ABS does not give a 4-byte aligned device offset"
    ENDC
    IFEQ (CONFIG_RBCP_COMPLETE-$AA)
        FAIL "CONFIG_RBCP_COMPLETE must not be $AA"
    ENDC
    IFEQ (CONFIG_RBCP_STATUS_OK-$AA)
        FAIL "CONFIG_RBCP_STATUS_OK must not be $AA"
    ENDC

; ---------------------------------------------------------------------------
; Scratch RAM layout (CONFIG_RBCP_SCRATCH_BASE, 32 bytes total)
;
; The 68K has no zero page.  The RBCP library uses a fixed block of RAM as
; working storage, mirroring the 6502 zero-page convention.  Callers
; populate ARG slots before calling command helpers.
; ---------------------------------------------------------------------------
RBCP_GROUP      EQU CONFIG_RBCP_SCRATCH_BASE+0   ; command group byte
RBCP_CMD        EQU CONFIG_RBCP_SCRATCH_BASE+1   ; command byte
RBCP_SAVED_TOK  EQU CONFIG_RBCP_SCRATCH_BASE+2   ; saved token LSB
RBCP_LONG_POLL  EQU CONFIG_RBCP_SCRATCH_BASE+3   ; 0=normal poll, 1=long poll
RBCP_ARG_COUNT  EQU CONFIG_RBCP_SCRATCH_BASE+4   ; argument count for send
RBCP_ERROR_CODE EQU CONFIG_RBCP_SCRATCH_BASE+5   ; failure stage (1/2/3)
RBCP_RETRY_CNT  EQU CONFIG_RBCP_SCRATCH_BASE+6   ; retry counter
                                                  ; +7 reserved/padding
RBCP_ARG0       EQU CONFIG_RBCP_SCRATCH_BASE+8
RBCP_ARG1       EQU CONFIG_RBCP_SCRATCH_BASE+9
RBCP_ARG2       EQU CONFIG_RBCP_SCRATCH_BASE+10
RBCP_ARG3       EQU CONFIG_RBCP_SCRATCH_BASE+11
RBCP_ARG4       EQU CONFIG_RBCP_SCRATCH_BASE+12
RBCP_ARG5       EQU CONFIG_RBCP_SCRATCH_BASE+13
RBCP_ARG6       EQU CONFIG_RBCP_SCRATCH_BASE+14
RBCP_ARG7       EQU CONFIG_RBCP_SCRATCH_BASE+15
RBCP_ARG8       EQU CONFIG_RBCP_SCRATCH_BASE+16

; Error codes written to RBCP_ERROR_CODE
RBCP_ERR_NONE       EQU 0
RBCP_ERR_TOKEN      EQU 1                   ; token never incremented
RBCP_ERR_PROGRESS   EQU 2                   ; progress never reached complete
RBCP_ERR_RESPONSE   EQU 3                   ; device reported failure
