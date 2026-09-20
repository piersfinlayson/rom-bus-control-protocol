; amiga_defs.s — the terminal's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

; ---------------------------------------------------------------------------
; The line
;
; One screen row holds the prompt, the line and the cursor, so the line is two
; characters shorter than the row.  Two bytes on the end of the buffer carry
; the carriage return and the line feed that go out with it.
; ---------------------------------------------------------------------------
LINE_MAX            EQU SCREEN_COLS-2
LINE_BUF_SIZE       EQU LINE_MAX+2

; Refusals to sit through before the line is given up on.  A refusal is the
; pipe being full, which is the far end not reading.  Each try is a command, so
; this is about 48ms — long enough to ride out a far end that is briefly behind
; and short enough that the status bar answers while the key is still down.
FULL_TRIES          EQU 256

; ---------------------------------------------------------------------------
; Receiving
;
; A pipe number of $AA is the reset marker and is refused, so no device can
; number a pipe above 169 and PIPE_NONE is safe.
; ---------------------------------------------------------------------------
PIPE_NONE           EQU $FF

; The most one PIPE_READ asks for.  The reply puts eight bytes of its own in
; front of the data, and both go through the library's un-swap buffer.  The
; back channel holds 512 device bytes and its own header and the reply's take
; sixteen of them, so the count the command carries runs out first.  It is one
; byte, and 255 is the most it says without using the zero that means 256.
RX_MAX              EQU 255
    ifgt RX_MAX+8-CONFIG_RBCP_DATA_BUF_SIZE
    fail "CONFIG_RBCP_DATA_BUF_SIZE is too small for a PIPE_READ of RX_MAX"
    endc

; Reads to run back to back while the device says more is waiting.  A read a
; field would otherwise take a field to clear every RX_MAX bytes, and this
; drains one at the speed the back channel allows.  The keyboard is polled
; before each of them.
;
; Two of them is about 510 bytes, and putting 510 characters on the screen
; already costs several fields, so a longer burst would only make the keys
; wait longer for the same bytes.
RX_BURST_MAX        EQU 2

; Resets before the device is given up for lost.
RECOVER_TRIES       EQU 3

; ---------------------------------------------------------------------------
; Keys
;
; amiga_getkey returns a character for a typing key and a token for everything
; else.  A character is anything from $20 up, so one comparison separates the
; two.
; ---------------------------------------------------------------------------
CHAR_FIRST          EQU $20
CHAR_LAST           EQU $7E
KEY_RUBOUT          EQU KEY_BACKSPACE

; Keys polled but not yet acted on.  A poll happens wherever the terminal
; waits and the loop empties the ring once a field, so the ring holds what
; arrived while the terminal was busy elsewhere.  A power of two, so the wrap
; is a mask.  Sixteen is far more than a keyboard delivers in the longest
; stretch between two drains.
KEY_RING            EQU 16
KEY_RING_MASK       EQU KEY_RING-1

; Blitter rows in one scroll of the text area.  The bitmap is interleaved, so
; a character row is eight pixel rows of four planes and the whole area is one
; run of SCREEN_BPL_W-wide rows with nothing to step over.
SCROLL_ROWS         EQU (ROW_TEXT_BOT-ROW_TEXT_TOP)*ROW_STRIDE/SCREEN_BPL_W

; ---------------------------------------------------------------------------
; Status codes.  The bar carries one of these and nothing else holds a string.
; ---------------------------------------------------------------------------
STAT_BLANK          EQU 0
STAT_OPENING        EQU 1
STAT_READY          EQU 2
STAT_SEND_ONLY      EQU 3       ; open, but no pipe brings bytes the other way
STAT_NO_PIPE        EQU 4
STAT_PIPE_DIR       EQU 5       ; pipes, but none takes bytes from the host
STAT_NO_ANSWER      EQU 6       ; the token never moved, so nothing received it
STAT_NO_COMPLETE    EQU 7       ; the token moved and the command never finished
STAT_PIPE_FULL      EQU 8
STAT_NOT_ARMED      EQU 9       ; there is no session to send down
STAT_NO_RECOVER     EQU 10      ; the device did not come back after a reset
STAT_RX_FAIL        EQU 11      ; the device refused a read, so reading stopped
STAT_COUNT          EQU 12

; ---------------------------------------------------------------------------
; Error numbers, indices into the error message table.  Only a session that
; never opened ends this way.  Everything after it goes on the status bar,
; because the screen holds what has been typed and what has arrived.
; ---------------------------------------------------------------------------
ERR_NO_DEVICE       EQU 0
ERR_ENTER           EQU 1
ERR_VERSION         EQU 2

; ---------------------------------------------------------------------------
; Pens.  amiga_term.s gives each of these its colour before the common palette
; is included.  Gold stays the two bands, so a label in its own pen does not
; compete with them.
; ---------------------------------------------------------------------------
PEN_LABEL           EQU 6                   ; the device and pipe lines
PEN_WARN            EQU 7                   ; a direction the device has no
                                            ; pipe for

; ---------------------------------------------------------------------------
; Screen layout — 40 columns by the 25 rows an NTSC machine shows
;
; A title bar, the device, the pipes, the text area, the line being typed and
; a status bar.  Both bars are gold with black on them, so the text area is
; the only part of the screen that looks like text.
; ---------------------------------------------------------------------------
ROW_TITLE           EQU 0
ROW_DEV             EQU 1
ROW_PIPE            EQU 2
ROW_TEXT_TOP        EQU 4
ROW_TEXT_BOT        EQU 22
ROW_INPUT           EQU 23
ROW_STATUS          EQU 24

COL_TITLE           EQU 1
COL_BRAND           EQU SCREEN_COLS-12      ; "PIERS.ROCKS" and a space
COL_TEXT            EQU 1
COL_PROTO           EQU SCREEN_COLS-11      ; "RBCP 0.1.2" hard right
COL_RX_PIPE         EQU 21                  ; the receiving half of the pipe row

; The count of characters the line has left, and the word after it.
COL_LEFT            EQU SCREEN_COLS-8
COL_LEFT_LBL        EQU COL_LEFT+3

; ---------------------------------------------------------------------------
; The terminal's variables, in the chip RAM the application owns.  The common
; code owns VAR_BASE+0 to 24, APP_BASE+$158 to $15A, APP_BASE+$160 to $165 and
; APP_BASE+$170 to $177, and the library's un-swap buffer is at $2200, so
; everything here starts clear of them.
; ---------------------------------------------------------------------------
TRM_VARS            EQU APP_BASE+$400

TRM_DEV_TYPE        EQU TRM_VARS+$000       ; 25 bytes, read once
TRM_DEV_VER         EQU TRM_VARS+$020       ; 25
TRM_PROTO           EQU TRM_VARS+$040       ; 12

; The pipes the scan settled on, or PIPE_NONE.  A line goes out of TRM_PIPE_OUT
; and the far end's bytes come back on TRM_PIPE_IN.
TRM_PIPE_OUT        EQU TRM_VARS+$050
TRM_PIPE_IN         EQU TRM_VARS+$051
TRM_PIPE_COUNT      EQU TRM_VARS+$052       ; what GET_PIPE_CAPABILITY said
TRM_ARMED           EQU TRM_VARS+$053       ; 1 while there is a session to send
TRM_RX_ARMED        EQU TRM_VARS+$054       ; 1 while a pipe brings bytes back

; The line being typed, and the two bytes that end it on the way out.
TRM_LINE            EQU TRM_VARS+$060
TRM_LINE_LEN        EQU TRM_VARS+$090
TRM_SEND_LEN        EQU TRM_VARS+$091       ; the line plus the two
TRM_SEND_POS        EQU TRM_VARS+$092
TRM_CHUNK           EQU TRM_VARS+$093
TRM_STAT            EQU TRM_VARS+$094       ; what the status bar is saying
TRM_FAULT           EQU TRM_VARS+$095       ; the status a failed line ended with

; The column the next received byte goes in, on the bottom row of the text
; area.  Zero means no row is open, which works because the first byte of one
; goes in column 1.
TRM_RX_COL          EQU TRM_VARS+$096
TRM_RX_LEN          EQU TRM_VARS+$097       ; bytes the last read returned
TRM_BURST           EQU TRM_VARS+$098       ; back to back reads left this field

; The keys polled and not yet acted on.
TRM_KEY_RING        EQU TRM_VARS+$0A0       ; KEY_RING bytes
TRM_KEY_HEAD        EQU TRM_KEY_RING+KEY_RING   ; where the next poll writes
TRM_KEY_TAIL        EQU TRM_KEY_HEAD+1      ; where the loop takes the next key

TRM_END             EQU TRM_VARS+$0C0

    ifgt TRM_KEY_TAIL+1-TRM_END
    fail "the key ring runs past the end of the terminal's variables"
    endc
