; rbcp_defs.s — RBCP protocol constants and zero-page address definitions
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; No platform-specific references. Use rbcp_config.s to configure platform-
; specific settings.
;
; The stock C64 kernal uses $FB–$FE as temporaries during its own startup,
; but we are pre-kernal so the entire $E0–$FF range is safe to use.
; (BASIC and the kernal have not run yet; zero page is uninitialised.)

.include "rbcp_config.s"

; ---------------------------------------------------------------------------
; Supported protocol version by this library
; ---------------------------------------------------------------------------

RBCP_SUPPORTED_PROTOCOL_MAJOR = 0
RBCP_SUPPORTED_PROTOCOL_MINOR = 1
RBCP_SUPPORTED_PROTOCOL_PATCH = 0

; ---------------------------------------------------------------------------
; ROM base address (C64: $E000)
; ---------------------------------------------------------------------------

RBCP_BASE_HI    = CONFIG_ROM_BASE_HI

; ---------------------------------------------------------------------------
; High byte of ROM address for RBCP command reads.
; ---------------------------------------------------------------------------
RBCP_CMD_HI     = CONFIG_RBCP_CMD_PAGE

; ---------------------------------------------------------------------------
; Poll timeouts (0 = no timeout), max 255
; ---------------------------------------------------------------------------

RBCP_POLL_TIMEOUT = CONFIG_RBCP_POLL_TIMEOUT
RBCP_NV_POLL_TIMEOUT = CONFIG_RBCP_NV_POLL_TIMEOUT

; SET_AUX with a hold does not answer until the hold has elapsed, so it waits
; on its own timeout rather than the one an NV commit uses.  The two bound
; unrelated things: how long a device takes to write flash, and how long a host
; asked a pin to stay put.
;
; A config written before this constant existed does not have to be edited: it
; falls back to what such a config already gave SET_AUX.
.ifdef CONFIG_RBCP_AUX_POLL_TIMEOUT
RBCP_AUX_POLL_TIMEOUT = CONFIG_RBCP_AUX_POLL_TIMEOUT
.else
RBCP_AUX_POLL_TIMEOUT = CONFIG_RBCP_NV_POLL_TIMEOUT
.endif

; ---------------------------------------------------------------------------
; Command retries on failure (0 = no retries), max 255
; ---------------------------------------------------------------------------
RBCP_TIMEOUT_RETRIES = CONFIG_RBCP_TIMEOUT_RETRIES

; ---------------------------------------------------------------------------
; Zero-page addresses — must match the declarations in rbcp.s
; ---------------------------------------------------------------------------

RBCP_ZP_BASE    = CONFIG_RBCP_ZP_BASE   ; base of RBCP library ZP block

rbcp_zp_0  = RBCP_ZP_BASE + 0  ; general purpose / loop counter lo
rbcp_zp_1  = RBCP_ZP_BASE + 1  ; general purpose / loop counter hi
rbcp_zp_2  = RBCP_ZP_BASE + 2  ; saved token LSB
rbcp_zp_3  = RBCP_ZP_BASE + 3  ; used by pause routine and to indicate to issue_cmd to perform a longer poll
rbcp_zp_4  = RBCP_ZP_BASE + 4  ; scratch / 16-bit counter hi
rbcp_zp_5  = RBCP_ZP_BASE + 5  ; scratch (also used for error code on failure)
rbcp_zp_6  = RBCP_ZP_BASE + 6  ; Used for retry tracking

RBCP_ARG_OFFSET = 7
RBCP_ARG_BASE   = CONFIG_RBCP_ZP_BASE + RBCP_ARG_OFFSET   ; base of argument buffer ZP block

rbcp_arg0  = RBCP_ARG_BASE + 0
rbcp_arg1  = RBCP_ARG_BASE + 1
rbcp_arg2  = RBCP_ARG_BASE + 2
rbcp_arg3  = RBCP_ARG_BASE + 3
rbcp_arg4  = RBCP_ARG_BASE + 4
rbcp_arg5  = RBCP_ARG_BASE + 5
rbcp_arg6  = RBCP_ARG_BASE + 6
rbcp_arg7  = RBCP_ARG_BASE + 7
rbcp_arg8  = RBCP_ARG_BASE + 8

.assert CONFIG_RBCP_ZP_LENGTH >= 16, error, "RBCP requires at least 16 bytes of zero page"
.assert CONFIG_RBCP_ZP_BASE + CONFIG_RBCP_ZP_LENGTH <= $100, error, "RBCP zero page block exceeds page size"

; ---------------------------------------------------------------------------
; Knock byte sequence: "!RBCP!"
;
; The knock byte sequence is NOT defined by the protocol, and must be agreed
; in advanced by the device and host implementations.
;
; It is currently hardcoded in this reference implementation.
; ---------------------------------------------------------------------------

RBCP_KNOCK_0    = $21       ; '!'
RBCP_KNOCK_1    = $52       ; 'R'
RBCP_KNOCK_2    = $42       ; 'B'
RBCP_KNOCK_3    = $43       ; 'C'
RBCP_KNOCK_4    = $50       ; 'P'
RBCP_KNOCK_5    = $21       ; '!'

; ---------------------------------------------------------------------------
; Protocol default values
; ---------------------------------------------------------------------------

RBCP_COMPLETE   = CONFIG_RBCP_COMPLETE              ; progress: command finished
RBCP_PENDING    = (~CONFIG_RBCP_COMPLETE) & $FF     ; progress: still processing
RBCP_STATUS_OK  = CONFIG_RBCP_STATUS_OK             ; response: success
RBCP_FAILED     = (~CONFIG_RBCP_STATUS_OK) & $FF    ; response: failure

; ---------------------------------------------------------------------------
; Command GROUP and CMD values
; ---------------------------------------------------------------------------

RBCP_GRP_CTRL                       = $00
RBCP_CMD_NOP                        = $00
RBCP_CMD_ENTER_CMD_RESP             = $01
RBCP_CMD_EXIT_CMD_RESP_ACK          = $02
RBCP_CMD_EXIT_CMD_RESP_SILENT       = $03
RBCP_CMD_SWITCH_AND_EXIT            = $04

RBCP_GRP_READ                       = $01
RBCP_CMD_GET_FLASH_SLOT_COUNT       = $00
RBCP_CMD_GET_FLASH_SLOT_INFO        = $01
RBCP_CMD_GET_FLASH_SLOT_INFO_ALL    = $02
RBCP_CMD_GET_RAM_SLOT_INFO_ALL      = $03
RBCP_CMD_GET_DEVICE_TYPE            = $04
RBCP_CMD_GET_DEVICE_VERSION         = $05
RBCP_CMD_GET_PROTOCOL_VERSION       = $06
RBCP_CMD_SLOT_PEEK                  = $07

RBCP_GRP_MODIFY                     = $02
RBCP_CMD_SLOT_POKE                  = $00
RBCP_CMD_SWITCH_SLOT                = $01
RBCP_CMD_LOAD_SLOT                  = $02
RBCP_CMD_SLOT_POKE_ALL_BYTE         = $03

RBCP_GRP_NV                         = $03
RBCP_CMD_GET_NV_CAPABILITY          = $00
RBCP_CMD_NV_PEEK                    = $01
RBCP_CMD_NV_POKE_BEGIN              = $02
RBCP_CMD_NV_POKE                    = $03
RBCP_CMD_NV_POKE_COMMIT             = $04
RBCP_CMD_NV_POKE_DISCARD            = $05
RBCP_CMD_NV_POKE_COMMIT_BYTE        = $06

RBCP_GRP_PIPES                      = $04
RBCP_CMD_GET_PIPE_CAPABILITY        = $00
RBCP_CMD_GET_PIPE_INFO              = $01
RBCP_CMD_PIPE_WRITE                 = $02

; Largest payload PIPE_WRITE carries, and so the largest valid count.
RBCP_PIPE_WRITE_MAX                 = 4

RBCP_GRP_AUX                        = $05
RBCP_CMD_GET_AUX_CAPABILITY         = $00
RBCP_CMD_GET_AUX_GROUP_INFO         = $01
RBCP_CMD_GET_AUX_PIN_INFO           = $02
RBCP_CMD_SET_AUX                    = $03
RBCP_CMD_SET_AUX_AND_EXIT           = $04
RBCP_CMD_SET_AUX_SWITCH_EXIT        = $05

RBCP_GRP_RESET                      = $AA
RBCP_CMD_RESET                      = $AA

; ---------------------------------------------------------------------------
; Back-channel region absolute addresses
; Response header at base:
;   +$00  last command  (2 bytes)
;   +$02  token         (2 bytes LE; LSB at +$02)
;   +$04  progress      (1 byte)
;   +$05  response      (1 byte)
;   +$06  reserved      (2 bytes)
;   +$08  data section  (512 bytes)
; ---------------------------------------------------------------------------

RBCP_TOKEN_LSB_ADDR  = CONFIG_RBCP_BCH_BASE + $02
RBCP_PROGRESS_ADDR   = CONFIG_RBCP_BCH_BASE + $04
RBCP_RESPONSE_ADDR   = CONFIG_RBCP_BCH_BASE + $05
RBCP_DATA_ADDR       = CONFIG_RBCP_BCH_BASE + $08

; GET_NV_CAPABILITY response field offsets (relative to RBCP_DATA_ADDR)
RBCP_NV_CAP_SIZE_LO  = 0
RBCP_NV_CAP_SIZE_HI  = 1
RBCP_NV_CAP_WRITABLE = 2

; GET_PIPE_CAPABILITY response field offsets (relative to RBCP_DATA_ADDR)
RBCP_PIPE_CAP_COUNT  = 0

; GET_PIPE_INFO response field offsets (relative to RBCP_DATA_ADDR)
RBCP_PIPE_INFO_TYPE    = 0
RBCP_PIPE_INFO_FLAGS   = 1
RBCP_PIPE_INFO_FREE    = 2      ; OUT space, saturating at $FF
RBCP_PIPE_INFO_WAITING = 3      ; IN bytes readable, saturating at $FF
RBCP_PIPE_INFO_FAR_END = 4

; GET_PIPE_INFO flag bits.  At least one direction bit is always set.
RBCP_PIPE_FLAG_OUT          = $01   ; pipe carries OUT, host to device
RBCP_PIPE_FLAG_IN           = $02   ; pipe carries IN, device to host
RBCP_PIPE_FLAG_ATTACH_KNOWN = $04   ; device answers whether the far end is attached
RBCP_PIPE_FLAG_ATTACHED     = $08   ; far end is attached; read only with ATTACH_KNOWN set

; Pipe types
RBCP_PIPE_TYPE_RAW   = $00

; Far end types
RBCP_FAR_END_UNSPEC  = $00
RBCP_FAR_END_USB_CDC = $01
RBCP_FAR_END_NETWORK = $02
RBCP_FAR_END_SERIAL  = $03      ; physical serial port

; GET_AUX_CAPABILITY response field offsets (relative to RBCP_DATA_ADDR)
RBCP_AUX_CAP_GROUPS   = 0
RBCP_AUX_CAP_MAX_HOLD = 1       ; in units of 10ms, zero for no timed holds

; GET_AUX_GROUP_INFO response field offsets (relative to RBCP_DATA_ADDR)
RBCP_AUX_GROUP_TYPE   = 0
RBCP_AUX_GROUP_PINS   = 1       ; zero means 256

; GET_AUX_PIN_INFO response field offsets (relative to RBCP_DATA_ADDR)
RBCP_AUX_PIN_FLAGS    = 0
RBCP_AUX_PIN_LEVEL    = 1
RBCP_AUX_PIN_DRIVEN   = 2

; GET_AUX_PIN_INFO flag bits
RBCP_AUX_FLAG_DRIVABLE = $01    ; SET_AUX may drive this pin
RBCP_AUX_FLAG_READABLE = $02    ; level and driven carry a real answer

; Auxiliary pin states, for the state and after arguments of SET_AUX
RBCP_AUX_LOW         = $00
RBCP_AUX_HIGH        = $01
RBCP_AUX_RELEASE     = $02

; Auxiliary pin group types
RBCP_AUX_TYPE_NONE   = $00
RBCP_AUX_TYPE_GPIO   = $01

; SET_AUX_SWITCH_EXIT flags — bit 0 picks the order, the rest must be zero
RBCP_AUX_PIN_FIRST   = $00
RBCP_AUX_SLOT_FIRST  = $01
