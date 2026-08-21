; app_defs.s — constants shared by the C64 applications that take the machine
; over while the kernal is still resident
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; These programs are entered from BASIC by SYS, mask interrupts, drive the
; screen directly and hand the machine back exactly as they found it.  What
; they share is the zero page they claim, the kernal locations they touch on
; the way in and out, and the way a session refuses to start.

    .include "c64_defs.s"

; ---------------------------------------------------------------------------
; Application zero page — between the c64_hw.s scratch and the RBCP block
;
; Three claims live in $D0-$FF: the RBCP library at $F0-$FF, the c64_hw.s
; scratch at $D0-$D6, and the application's own at $D7-$DF.  The block is saved
; whole on entry and restored on exit.
;
; That is safe only while nothing else is running in it, which means interrupts
; masked and no kernal or BASIC call in flight.  The screen editor is broken
; for that whole span, which is why the screen is written directly and the
; first kernal screen call happens after the restore.
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

ZP_SAVE_BASE  = $D0
ZP_SAVE_COUNT = $30

; ---------------------------------------------------------------------------
; Kernal and BASIC locations
; ---------------------------------------------------------------------------

NMINV           = $0318     ; NMI vector, kernal jmp ($0318) target
KEY_NDX         = $00C6     ; kernal keyboard buffer count, zeroed on the way out
KERNAL_CLRSCR   = $E544     ; called only after the zero page restore

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
