; app_defs.s — constants shared by the C64 applications that drive the screen
; themselves
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; These applications run with interrupts masked.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Application zero page — between the c64_hw.s scratch and the RBCP block
;
; Three claims live in $D0-$FF: the RBCP library at $F0-$FF, the c64_hw.s
; scratch at $D0-$D6, and the application's own at $D7-$DF.
; ---------------------------------------------------------------------------

ZP_APP0     = $D7
ZP_APP1     = $D8
ZP_APP2     = $D9
ZP_APP3     = $DA
ZP_APP4     = $DB
ZP_APP5     = $DC
ZP_APP6     = $DD
ZP_APP7     = $DE
ZP_APP8     = $DF

; ---------------------------------------------------------------------------
; Kernal locations
; ---------------------------------------------------------------------------

NMINV           = $0318     ; NMI vector, kernal jmp ($0318) target

; ---------------------------------------------------------------------------
; Key scanning.  An application supplies the table, c64_keys.s walks it, and
; every code in it is the application's own but for this one.
; ---------------------------------------------------------------------------

KEY_NONE_CODE   = $00

; ---------------------------------------------------------------------------
; Why a session refused to start.  Returned in A by sess_open with carry set.
; An application numbers its own refusals from SESS_FAIL_COUNT upwards.
; ---------------------------------------------------------------------------

SESS_FAIL_NO_DEVICE = $00   ; the knock token never moved
SESS_FAIL_ENTER     = $01   ; the device refused ENTER_CMD_RESP
SESS_FAIL_VERSION   = $02   ; the device speaks a protocol this cannot
SESS_FAIL_CLASH     = $03   ; the image already holds a configured value
SESS_FAIL_RAM_SLOTS = $04   ; fewer than two RAM slots
SESS_FAIL_NO_CLEAN  = $05   ; no flash slot matches, so there is no clean exit
SESS_FAIL_COUNT     = $06
