; rbcp_defs.s — RBCP protocol constants, bus mapping, and scratch RAM layout
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Include the platform rbcp_config.s before this file.
;
; This file is generic across 68K platforms.  Everything platform-specific
; is supplied by rbcp_config.s.  Everything derived from it lives here.

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
; Only the first row is exercised.
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
;   aligned.  The assertion below enforces that at build time.
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
RBCP_CMD_LOAD_AND_EXIT      EQU $05

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
; Group 0x04 — Pipes
; ---------------------------------------------------------------------------
RBCP_GRP_PIPES              EQU $04
RBCP_CMD_GET_PIPE_CAP       EQU $00
RBCP_CMD_GET_PIPE_INFO      EQU $01
RBCP_CMD_PIPE_WRITE         EQU $02
RBCP_CMD_PIPE_READ          EQU $03
RBCP_PIPE_WRITE_MAX         EQU 4

; ---------------------------------------------------------------------------
; Group 0x05 — Auxiliary I/O
;
; Device pins the host can drive and read.  A pin is addressed by its group
; and its number within that group.  The comments above the auxiliary helpers
; in rbcp.s explain the model.
; ---------------------------------------------------------------------------
RBCP_GRP_AUX                EQU $05
RBCP_CMD_GET_AUX_CAP        EQU $00
RBCP_CMD_GET_AUX_GROUP_INFO EQU $01
RBCP_CMD_GET_AUX_PIN_INFO   EQU $02
RBCP_CMD_SET_AUX            EQU $03
RBCP_CMD_SET_AUX_AND_EXIT   EQU $04
RBCP_CMD_SET_AUX_SWITCH_EXIT EQU $05

; ---------------------------------------------------------------------------
; Group 0x06 — LEDs
; ---------------------------------------------------------------------------
RBCP_GRP_LEDS               EQU $06
RBCP_CMD_GET_LED_CAP        EQU $00
RBCP_CMD_GET_LED_INFO       EQU $01
RBCP_CMD_GET_LED_MODE_INFO  EQU $02
RBCP_CMD_SET_LED            EQU $03

; ---------------------------------------------------------------------------
; Group 0xAA — Reset
; ---------------------------------------------------------------------------
RBCP_CMD_RESET              EQU $AA

; ---------------------------------------------------------------------------
; Response data-section field offsets, relative to the start of the data
; section (region byte 8).  They index a linear buffer rbcp_read_data has
; un-swapped, so they are the same numbers the specification gives.
; ---------------------------------------------------------------------------
; GET_RAM_SLOT_INFO_ALL
RBCP_RAM_TOTAL             EQU 0
RBCP_RAM_ACTIVE            EQU 1
RBCP_RAM_ROM_TYPE          EQU 2
; GET_FLASH_SLOT_INFO record
RBCP_FLASH_ROM_TYPE        EQU 0
RBCP_FLASH_NAME            EQU 1
; GET_FLASH_SLOT_INFO_ALL preamble, then records in slot order
RBCP_FLASH_ALL_TOTAL       EQU 0        ; slots the device has
RBCP_FLASH_ALL_WHOLE       EQU 1        ; complete records that follow
RBCP_FLASH_ALL_PARTIAL     EQU 2        ; 1 where a truncated record follows
RBCP_FLASH_ALL_RECORDS     EQU 4        ; first record
RBCP_FLASH_RECORD_SIZE     EQU 32       ; a GET_FLASH_INFO record
; GET_NV_CAPABILITY
RBCP_NV_CAP_SIZE_LO        EQU 0
RBCP_NV_CAP_SIZE_HI        EQU 1
RBCP_NV_CAP_WRITABLE       EQU 2
RBCP_NV_CAP_NOSLOT         EQU 3        ; bits 0-3 are N, and 2^N bytes stay
                                        ; unchanged by a write with no slot
                                        ; provided.  N = 0 means no such write.
                                        ; Bit 7 is which end of NV storage they
                                        ; sit at, 0 start and 1 end.

; The RAM slot argument that provides the device no slot at all.  A device that
; offers it writes the last few bytes of NV storage without a staging slot,
; and loses the rest of NV storage doing so.
RBCP_NV_SLOT_NONE          EQU $FE
; GET_PIPE_CAPABILITY
RBCP_PIPE_CAP_COUNT        EQU 0
; GET_PIPE_INFO
RBCP_PIPE_INFO_TYPE        EQU 0
RBCP_PIPE_INFO_FLAGS       EQU 1
RBCP_PIPE_INFO_FREE        EQU 2        ; OUT space, saturating at $FF
RBCP_PIPE_INFO_WAITING     EQU 3        ; IN bytes readable, saturating at $FF
RBCP_PIPE_INFO_FAR_END     EQU 4
; GET_PIPE_INFO flag bits.  At least one direction bit is always set.
RBCP_PIPE_FLAG_OUT          EQU $01     ; carries OUT, host to device
RBCP_PIPE_FLAG_IN           EQU $02     ; carries IN, device to host
RBCP_PIPE_FLAG_ATTACH_KNOWN EQU $04     ; device answers whether the far end is
                                        ; attached
RBCP_PIPE_FLAG_ATTACHED     EQU $08     ; far end attached.  Read it only
                                        ; with ATTACH_KNOWN set
; PIPE_READ
RBCP_PIPE_READ_COUNT       EQU 0        ; bytes returned, where FULL is clear
RBCP_PIPE_READ_FLAGS       EQU 1
RBCP_PIPE_READ_WAITING     EQU 2        ; IN bytes left, saturating at $FF
RBCP_PIPE_READ_DATA        EQU 8        ; the bytes themselves
; PIPE_READ flag bits
RBCP_PIPE_READ_FLAG_OVERRUN EQU $01     ; bytes were thrown away unread
RBCP_PIPE_READ_FLAG_FULL    EQU $02     ; the whole count asked for came back
; Pipe types
RBCP_PIPE_TYPE_RAW         EQU $00
; Far end types
RBCP_FAR_END_UNSPEC        EQU $00
RBCP_FAR_END_USB_CDC       EQU $01
RBCP_FAR_END_NETWORK       EQU $02
RBCP_FAR_END_SERIAL        EQU $03      ; physical serial port
; GET_AUX_CAPABILITY
RBCP_AUX_CAP_GROUPS        EQU 0
RBCP_AUX_CAP_MAX_HOLD      EQU 1        ; 10ms units, 0 for no timed holds
; GET_AUX_GROUP_INFO
RBCP_AUX_GROUP_TYPE        EQU 0
RBCP_AUX_GROUP_PINS        EQU 1        ; zero means 256
; GET_AUX_PIN_INFO
RBCP_AUX_PIN_FLAGS         EQU 0
RBCP_AUX_PIN_LEVEL         EQU 1
RBCP_AUX_PIN_DRIVEN        EQU 2
; GET_AUX_PIN_INFO flag bits
RBCP_AUX_FLAG_DRIVABLE     EQU $01      ; SET_AUX may drive this pin
RBCP_AUX_FLAG_READABLE     EQU $02      ; level and driven carry a real answer
; Auxiliary pin states, for the state and after arguments of SET_AUX
RBCP_AUX_LOW               EQU $00
RBCP_AUX_HIGH              EQU $01
RBCP_AUX_RELEASE           EQU $02
; Auxiliary pin group types
RBCP_AUX_TYPE_NONE         EQU $00
RBCP_AUX_TYPE_GPIO         EQU $01
; SET_AUX_SWITCH_EXIT flags — bit 0 picks the order, the rest must be zero
RBCP_AUX_PIN_FIRST         EQU $00
RBCP_AUX_SLOT_FIRST        EQU $01
; GET_LED_CAPABILITY
RBCP_LED_CAP_COUNT         EQU 0
; GET_LED_INFO
RBCP_LED_INFO_TYPE         EQU 0
RBCP_LED_INFO_MODE         EQU 1
; GET_LED_MODE_INFO
RBCP_LED_MODE_FLAGS        EQU 0
RBCP_LED_MODE_MIN_PERIOD   EQU 1        ; 100ms units
; GET_LED_MODE_INFO flag bits
RBCP_LED_MODE_TAKES_PERIOD EQU $01
; LED types and modes
RBCP_LED_TYPE_MONO         EQU $00
RBCP_LED_TYPE_RGB          EQU $01
RBCP_LED_OFF               EQU $00
RBCP_LED_ON                EQU $01
RBCP_LED_BLINK             EQU $02
RBCP_LED_BREATHE           EQU $03
RBCP_LED_CYCLE             EQU $04
RBCP_LED_BEACON            EQU $05

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
; data section is NOT a linear CPU offset.  rbcp_read_data in rbcp.s walks it
; a byte at a time.
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
RBCP_POLL_KIND  EQU CONFIG_RBCP_SCRATCH_BASE+3   ; which progress timeout
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

; Values written to RBCP_POLL_KIND, picking the progress timeout
RBCP_POLL_NORMAL    EQU 0
RBCP_POLL_NV        EQU 1
RBCP_POLL_AUX       EQU 2

; Error codes written to RBCP_ERROR_CODE
RBCP_ERR_NONE       EQU 0
RBCP_ERR_TOKEN      EQU 1                   ; token never incremented
RBCP_ERR_PROGRESS   EQU 2                   ; progress never reached complete
RBCP_ERR_RESPONSE   EQU 3                   ; device reported failure
