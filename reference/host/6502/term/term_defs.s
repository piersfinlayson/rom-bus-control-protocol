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
STAT_SEND_ONLY  = $0D       ; open, but no pipe brings bytes the other way
STAT_RX_FAIL    = $0E       ; the device refused a read, so reading stopped
STAT_COUNT      = $0F

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
; Receiving
;
; Bytes come the other way through a second pipe, and the screen shows them in
; inverse so that what the far end said is never mistaken for what was typed.
; ---------------------------------------------------------------------------

; No pipe carries this direction.  A device may expose at most 170 pipes, so a
; number this high is one no device can have.
PIPE_NONE       = $FF

; The most one PIPE_READ can ask for.  The command needs eight bytes of its own
; at the front of the data section, ahead of the bytes themselves, and the
; count is a single argument byte, so no machine asks for more than 255.
RX_ROOM         = CONFIG_RBCP_BCH_SIZE - 8 - 8
.if RX_ROOM > 255
RX_MAX          = 255
.else
RX_MAX          = RX_ROOM
.endif

; Reads to run back to back while the device says more is waiting.  A poll a
; second would otherwise take a second per read to clear a burst, and this
; drains one at the speed the back channel allows.  The keyboard is unread for
; the whole of it, which is why it is not longer.
RX_BURST_MAX    = 8

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
