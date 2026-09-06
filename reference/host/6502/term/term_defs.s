; term_defs.s — what every machine's RBCP terminal shares
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The terminal is one program built for several machines.  This file and the
; four beside it are the same on all of them.  What differs is the screen, the
; keys and the zero page, and those come from the application's own plat_defs.s
; and plat.s.

    .include "plat_defs.s"
    .include "rbcp_stage.s"

; ---------------------------------------------------------------------------
; Status codes.  Passed to display_status in A.  Nothing outside display.s
; holds a string.
; ---------------------------------------------------------------------------

STAT_BLANK      = $00
STAT_OPENING    = $01       ; knocking and entering command-response mode
STAT_READY      = $02
STAT_NO_DEVICE  = $03       ; no token increment — nothing answered the knock
STAT_ENTER_FAIL = $04       ; the device answered but refused ENTER_CMD_RESP
STAT_VERSION    = $05
STAT_NO_PIPE    = $06
STAT_PIPE_DIR   = $07       ; pipe 0 does not carry OUT
STAT_NO_ANSWER  = $08       ; the token never moved, so nothing received it
STAT_NO_COMPLETE = $09      ; the token moved and the command never finished
STAT_PIPE_FULL  = $0A       ; the pipe would not take the line
STAT_NOT_ARMED  = $0B       ; there is no session to send down
STAT_NO_RECOVER = $0C       ; the device did not come back after a reset
STAT_COUNT      = $0D

; ---------------------------------------------------------------------------
; The line
;
; One screen row holds the prompt, the line and the cursor, so the line is two
; characters shorter than the row.  Two bytes on the end of the buffer carry
; the carriage return and the line feed that go out with it.
; ---------------------------------------------------------------------------

LINE_MAX        = SCREEN_COLS - 2
LINE_BUF_SIZE   = LINE_MAX + 2

; Refused writes before the line is given up on.  A refusal means the pipe is
; full, which is the far end not reading, and a refused write costs about half
; a millisecond, so this is about an eighth of a second.  The display is off
; for all of it, which is why it is not longer.
;
; A byte counting down from zero gives 256 tries.
FULL_TRIES      = 256

; ---------------------------------------------------------------------------
; Keys.  plat_key returns ASCII, and the machine's own matrix, or whatever else
; it reads, stays behind that.
; ---------------------------------------------------------------------------

KEY_NONE_CODE   = $00
KEY_DEL_CODE    = $08
KEY_RET_CODE    = $0D

; What may go in a line.  $20-$3F and $41-$5A are the characters every one of
; these screens draws as itself.
CHAR_FIRST      = $20
CHAR_PUNCT_END  = $40       ; one past the punctuation and the digits
CHAR_ALPHA      = $41
CHAR_ALPHA_END  = $5B
