; rbcp_defs.s — RBCP protocol constants and zero-page address definitions
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
; RBCP specification version 0.1.0
;
; No platform-specific references. To port to another 6502 platform change
; RBCP_BASE_HI, RBCP_BASE_LO and the three derived addresses.
;
; Zero-page layout ($E0–$FF):
;   $E0–$E4   rbcp_arg0–rbcp_arg4   RBCP command argument buffer
;   $E5–$EA   spare
;   $EB–$EE   zp_ptr_lo, zp_ptr_hi, zp_tmp0, zp_tmp1  (boot/hw scratch)
;   $EF       spare
;   $FB–$FF   rbcp_zp_0–rbcp_zp_4   RBCP library working registers
;
; The stock C64 kernal uses $FB–$FE as temporaries during its own startup,
; but we are pre-kernal so the entire $E0–$FF range is safe to use.
; (BASIC and the kernal have not run yet; zero page is uninitialised.)

; ---------------------------------------------------------------------------
; ROM base address (C64: $E000)
; ---------------------------------------------------------------------------

RBCP_BASE_HI    = $E0
RBCP_BASE_LO    = $00

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

RBCP_TOKEN_LSB_ADDR  = $E002
RBCP_PROGRESS_ADDR   = $E004
RBCP_RESPONSE_ADDR   = $E005
RBCP_DATA_ADDR       = $E008

; ---------------------------------------------------------------------------
; Protocol default values
; ---------------------------------------------------------------------------

RBCP_COMPLETE   = $AA       ; progress: command finished
RBCP_PENDING    = $55       ; progress: still processing
RBCP_STATUS_OK  = $CC       ; response: success
RBCP_FAILED     = $33       ; response: failure

; ---------------------------------------------------------------------------
; Poll timeout  (0 = no timeout)
; ---------------------------------------------------------------------------

RBCP_POLL_TIMEOUT = 0

; ---------------------------------------------------------------------------
; Zero-page addresses — must match the declarations in rbcp.s
; ---------------------------------------------------------------------------

RBCP_ZP_BASE    = $FB       ; base of RBCP library ZP block

rbcp_zp_0  = RBCP_ZP_BASE + 0  ; general purpose / loop counter lo
rbcp_zp_1  = RBCP_ZP_BASE + 1  ; general purpose / loop counter hi
rbcp_zp_2  = RBCP_ZP_BASE + 2  ; saved token LSB
rbcp_zp_3  = RBCP_ZP_BASE + 3  ; current token LSB / 16-bit counter lo
rbcp_zp_4  = RBCP_ZP_BASE + 4  ; scratch / 16-bit counter hi

RBCP_ARG_BASE   = $E0       ; base of argument buffer ZP block

rbcp_arg0  = RBCP_ARG_BASE + 0
rbcp_arg1  = RBCP_ARG_BASE + 1
rbcp_arg2  = RBCP_ARG_BASE + 2
rbcp_arg3  = RBCP_ARG_BASE + 3
rbcp_arg4  = RBCP_ARG_BASE + 4

; ---------------------------------------------------------------------------
; Knock byte sequence: "!RBCP!"
; ---------------------------------------------------------------------------

RBCP_KNOCK_0    = $21       ; '!'
RBCP_KNOCK_1    = $52       ; 'R'
RBCP_KNOCK_2    = $42       ; 'B'
RBCP_KNOCK_3    = $43       ; 'C'
RBCP_KNOCK_4    = $50       ; 'P'
RBCP_KNOCK_5    = $21       ; '!'

; ---------------------------------------------------------------------------
; Command GROUP and CMD values
; ---------------------------------------------------------------------------

RBCP_GRP_CTRL           = $00
RBCP_CMD_ENTER_CMD_RESP = $02
RBCP_CMD_SWITCH_AND_EXIT= $05

RBCP_GRP_READ           = $01
RBCP_CMD_GET_FLASH_SLOT = $00
RBCP_CMD_GET_RAM_SLOT   = $01

RBCP_GRP_MODIFY         = $02
RBCP_CMD_LOAD_SLOT      = $02