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
; High byte of ROM address for RBCP command reads. Calculated from the above.
; ---------------------------------------------------------------------------
RBCP_CMD_HI     = CONFIG_RBCP_READ_HI

; ---------------------------------------------------------------------------
; Poll timeout  (0 = no timeout), max 255
; ---------------------------------------------------------------------------

RBCP_POLL_TIMEOUT = CONFIG_RBCP_POLL_TIMEOUT

; ---------------------------------------------------------------------------
; Zero-page addresses — must match the declarations in rbcp.s
; ---------------------------------------------------------------------------

RBCP_ZP_BASE    = CONFIG_RBCP_ZP_BASE   ; base of RBCP library ZP block

rbcp_zp_0  = RBCP_ZP_BASE + 0  ; general purpose / loop counter lo
rbcp_zp_1  = RBCP_ZP_BASE + 1  ; general purpose / loop counter hi
rbcp_zp_2  = RBCP_ZP_BASE + 2  ; saved token LSB
rbcp_zp_3  = RBCP_ZP_BASE + 3  ; current token LSB / 16-bit counter lo
rbcp_zp_4  = RBCP_ZP_BASE + 4  ; scratch / 16-bit counter hi
rbcp_zp_5  = RBCP_ZP_BASE + 5  ; scratch

RBCP_ARG_OFFSET = 8
RBCP_ARG_BASE   = CONFIG_RBCP_ZP_BASE + RBCP_ARG_OFFSET   ; base of argument buffer ZP block

rbcp_arg0  = RBCP_ARG_BASE + 0
rbcp_arg1  = RBCP_ARG_BASE + 1
rbcp_arg2  = RBCP_ARG_BASE + 2
rbcp_arg3  = RBCP_ARG_BASE + 3
rbcp_arg4  = RBCP_ARG_BASE + 4

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
; CONFIG_CMD_RESP location and size table indices
; ---------------------------------------------------------------------------

RBCP_LOCATION_START     = $00       ; back-channel at start of slot
RBCP_LOCATION_END       = $01       ; back-channel at end of slot

RBCP_SIZE_8             = $00       ; header only (0 bytes data)
RBCP_SIZE_16            = $01
RBCP_SIZE_32            = $02
RBCP_SIZE_64            = $03
RBCP_SIZE_128           = $04
RBCP_SIZE_256           = $05
RBCP_SIZE_512           = $06
RBCP_SIZE_1024          = $07
RBCP_SIZE_2048          = $08
RBCP_SIZE_4096          = $09
RBCP_SIZE_8192          = $0A
RBCP_SIZE_16384         = $0B
RBCP_SIZE_32768         = $0C

; ---------------------------------------------------------------------------
; Command GROUP and CMD values
; ---------------------------------------------------------------------------

RBCP_GRP_CTRL                       = $00
RBCP_CMD_NOP                        = $00
RBCP_CMD_CONFIG_CMD_RESP            = $01
RBCP_CMD_ENTER_CMD_RESP             = $02
RBCP_CMD_CONFIG_AND_ENTER_CMD_RESP  = $03
RBCP_CMD_EXIT_CMD_RESP_ACK          = $04
RBCP_CMD_EXIT_CMD_RESP_SILENT       = $05
RBCP_CMD_SWITCH_AND_EXIT            = $06

RBCP_GRP_READ                       = $01
RBCP_CMD_GET_FLASH_SLOT_COUNT       = $00
RBCP_CMD_GET_FLASH_SLOT_INFO        = $01
RBCP_CMD_GET_FLASH_SLOT_INFO_ALL    = $02
RBCP_CMD_GET_RAM_SLOT_INFO_ALL      = $03
RBCP_CMD_GET_DEVICE_TYPE            = $04
RBCP_CMD_GET_DEVICE_VERSION         = $05
RBCP_CMD_GET_PROTOCOL_VERSION       = $06

RBCP_GRP_MODIFY                     = $02
RBCP_CMD_SLOT_POKE                  = $00
RBCP_CMD_SWITCH_SLOT                = $01
RBCP_CMD_LOAD_SLOT                  = $02
RBCP_CMD_SLOT_POKE_ALL_BYTE         = $03

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

RBCP_TOKEN_LSB_ADDR  = RBCP_BASE_HI * $100 + $02
RBCP_PROGRESS_ADDR   = RBCP_BASE_HI * $100 + $04
RBCP_RESPONSE_ADDR   = RBCP_BASE_HI * $100 + $05
RBCP_DATA_ADDR       = RBCP_BASE_HI * $100 + $08
