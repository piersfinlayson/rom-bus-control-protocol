; amiga_defs.s — the pipe throughput test's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

; ---------------------------------------------------------------------------
; The one-second window
;
; The CIA-B time of day counter is clocked by horizontal sync, so a second is
; a fixed number of lines and the machine decides which number.  A PAL Agnus
; draws 15625.09 lines a second and an NTSC one 15734.26, and the counts below
; are those rounded down.  A window is then 6 parts per million short on PAL
; and 17 on NTSC, which at any rate this can measure is a fraction of a byte.
;
; The count matters because the byte count in a window is the rate, and that
; only holds while a window is a second.  Nothing here divides.
; ---------------------------------------------------------------------------
TOD_HZ_PAL          EQU 15625
TOD_HZ_NTSC         EQU 15734
TOD_MASK            EQU $00FFFFFF           ; the counter is 24 bits

; A fixed length run, in windows.
TIMED_SECS          EQU 10

; ---------------------------------------------------------------------------
; The line
;
;   NNNN 012345678901234567890123456789012345678901234567890123456<CR><LF>
;   0123 5                                                     61 62 63
;
; 64 bytes, which is sixteen whole PIPE_WRITE payloads, so no write straddles
; a line boundary.  Bytes 0 to 3 are the sequence in hex, byte 4 a space,
; bytes 5 to 61 the body and 62 and 63 CR and LF.
;
; The body is a digit ruler with one cell replaced by '#', one place further
; right on each line.  On a terminal that is a diagonal scrolling up the
; screen, and a dropped line breaks it without anyone reading the numbers.
; ---------------------------------------------------------------------------
LINE_LEN            EQU 64
BODY_START          EQU 5
BODY_LEN            EQU 57

; ---------------------------------------------------------------------------
; Send paths.  The order is the order they appear on the paths row.
; ---------------------------------------------------------------------------
PATH_LIB4           EQU 0                   ; four bytes a command, the library
PATH_LIB1           EQU 1                   ; one byte a command, the library
PATH_TUNED4         EQU 2                   ; four bytes a command, hand written
PATH_COUNT          EQU 3

; ---------------------------------------------------------------------------
; Where TUNED4's four fixed command bytes live
;
; A command byte is sent by reading the command page at that byte's own offset,
; so a byte whose value never changes has an offset that never changes.  The
; group, the command and the count are constants, and send_tuned_line holds an
; address register on the command page, so each of the three is a displacement
; off it.  The pipe number is not a constant, so its address is worked out once
; a line.
; ---------------------------------------------------------------------------
TUNED_GROUP_OFF     EQU RBCP_GRP_PIPES<<CONFIG_RBCP_BUS_SHIFT
TUNED_CMD_OFF       EQU RBCP_CMD_PIPE_WRITE<<CONFIG_RBCP_BUS_SHIFT
TUNED_COUNT_OFF     EQU RBCP_PIPE_WRITE_MAX<<CONFIG_RBCP_BUS_SHIFT

; The progress and response bytes, as displacements from the token byte, which
; is what send_tuned_line keeps an address register on.
TUNED_PROG_OFF      EQU RBCP_PROGRESS_ADDR-RBCP_TOKEN_LSB_ADDR
TUNED_RESP_OFF      EQU RBCP_RESPONSE_ADDR-RBCP_TOKEN_LSB_ADDR

; TUNED4 counts its polls in a DBcc, whose counter is a word, so the timeout
; has to fit in one.
TUNED_POLL          EQU CONFIG_RBCP_POLL_TIMEOUT

    ifgt CONFIG_RBCP_POLL_TIMEOUT-$FFFF
    fail "CONFIG_RBCP_POLL_TIMEOUT does not fit the word TUNED4 counts in"
    endc
    ifeq CONFIG_RBCP_POLL_TIMEOUT
    fail "a run needs a bounded poll"
    endc

; ---------------------------------------------------------------------------
; What happens when a write does not go through
;
; Immediate retries of a refused write before the pipe is asked how much room
; it has.  A pipe that is momentarily full is the case the retry exists for.
; ---------------------------------------------------------------------------
FAULT_BURST         EQU 8

; How long a pipe that really is full may stay that way, in seconds.
STALL_SECS          EQU 5

; Resets before the device is given up for lost.
RECOVER_TRIES       EQU 3

; Goes at each of the two commands that find the pipe.  Each runs once, so a
; single mangled one would otherwise cost the whole session.
OPEN_TRIES          EQU 4

; Lines between reads of the keyboard.  It has to be a power of two.
;
; A read is about ten CIA accesses, and against a LIB4 line it costs 1.0% of
; the rate every line and 0.25% every fourth.  Four puts RETURN inside 21ms on
; LIB4 and 84ms on LIB1, which is faster than anyone lets a key up, and leaves
; the figure the run reports very nearly the machine's own.
KEY_LINES           EQU 4

; The key that asks for a fixed length run.  amiga_getkey returns a letter in
; the case it was typed in, and the tester takes it either way.
KEY_TIMED           EQU 'T'
KEY_TIMED_LOWER     EQU 't'

; ---------------------------------------------------------------------------
; Status codes.  draw_status takes one in D0 and nothing outside the string
; table holds a message.
; ---------------------------------------------------------------------------
STAT_BLANK          EQU 0
STAT_ARMED          EQU 1
STAT_NO_PIPE        EQU 2                   ; the device has no pipe at all
STAT_PIPE_DIR       EQU 3                   ; no pipe of its takes host bytes
STAT_RUNNING        EQU 4
STAT_STOPPED        EQU 5
STAT_NOT_ARMED      EQU 6
STAT_NO_ANSWER      EQU 7                   ; the token never moved
STAT_NO_COMPLETE    EQU 8                   ; it moved and nothing completed
STAT_BAD_REFUSAL    EQU 9                   ; refused with the pipe not full
STAT_PIPE_STUCK     EQU 10                  ; the pipe stayed full
STAT_NO_RECOVER     EQU 11                  ; the device did not come back
STAT_COUNT          EQU 12

; ---------------------------------------------------------------------------
; Error numbers, indices into the error message table.  Only a session that
; never opened ends this way.  Everything after that leaves the figures on the
; screen, because the figures are the result.
; ---------------------------------------------------------------------------
ERR_NO_DEVICE       EQU 0
ERR_ENTER           EQU 1
ERR_VERSION         EQU 2

; ---------------------------------------------------------------------------
; Pens.  amiga_pipe.s gives each of these its colour before the common palette
; is included.  Gold stays the two bands, so a label in its own pen does not
; compete with them.
; ---------------------------------------------------------------------------
PEN_LABEL           EQU 6                   ; every label and heading
PEN_WARN            EQU 7                   ; nothing to send down
PEN_MARK            EQU 8                   ; the send path in hand
PEN_BAD             EQU 14                  ; refusals and errors

; ---------------------------------------------------------------------------
; Screen layout — 40 columns by the 25 rows an NTSC machine shows
;
; Every count is 32 bits, so every field is the ten digits 4294967295 takes.
; A label sits at column 1 and its ten digits end at column 38.
; ---------------------------------------------------------------------------
ROW_TITLE           EQU 0
ROW_DEV             EQU 2
ROW_VER             EQU 3
ROW_PROTO           EQU 4
ROW_PIPE            EQU 5
ROW_BPS             EQU 7                   ; the headline band
ROW_BEST            EQU 9
ROW_MEAN            EQU 10
ROW_TOTAL           EQU 12
ROW_LINES           EQU 13
ROW_SECS            EQU 14
ROW_REFUSALS        EQU 16
ROW_ERRORS          EQU 17
ROW_PATHS           EQU 19
ROW_STATUS          EQU 21
ROW_KEYS            EQU 23                  ; and the row under it

; The counter rows, each a label drawn once and a figure rewritten beside it.
; The headline has a band of its own and is not among them.
LABEL_COUNT         EQU 7

COL_TITLE           EQU 1
COL_TEXT            EQU 1
COL_LABEL           EQU 1
COL_NUM             EQU 29                  ; ten digits, ending at column 38
COL_BRAND           EQU SCREEN_COLS-12      ; "PIERS.ROCKS" and a space

; The three send paths sit behind the label naming the row, far enough apart
; for the longest of them.
COL_PATH_LBL        EQU 1
COL_PATH_0          EQU 8
COL_PATH_1          EQU 18
COL_PATH_2          EQU 28

; ---------------------------------------------------------------------------
; The number fields
;
; Every figure on the screen has a slot holding the characters that go in the
; field rather than the count they came from.  A refresh fills every slot and
; writes them out afterwards, so the totals and the rates cannot be a
; photograph of two different moments.
;
; There are two of each slot, one for what the numbers say now and one for
; what the screen already has, and only the characters that differ are
; written.  Most of a ten-digit count is the same as it was a second ago.
; ---------------------------------------------------------------------------
FLD_BPS             EQU 0
FLD_BEST            EQU 1
FLD_MEAN            EQU 2
FLD_TOTAL           EQU 3
FLD_LINES           EQU 4
FLD_SECS            EQU 5
FLD_REFUSALS        EQU 6
FLD_ERRORS          EQU 7
FLD_COUNT           EQU 8

NUM_DIGITS          EQU 10
FLD_WIDTH           EQU NUM_DIGITS

; ---------------------------------------------------------------------------
; The tester's variables, in the chip RAM the application owns.  The common
; code owns VAR_BASE+0 to 24, APP_BASE+$158 to $15A, APP_BASE+$160 to $165 and
; APP_BASE+$170 to $177, and the library's un-swap buffer is at $2200, so
; everything here starts clear of them.  Longs are at even offsets.
; ---------------------------------------------------------------------------
PT_VARS             EQU APP_BASE+$400

PT_DEV_TYPE         EQU PT_VARS+$000        ; 25 bytes, read once
PT_DEV_VER          EQU PT_VARS+$020        ; 25
PT_PROTO            EQU PT_VARS+$040        ; 12

; The counters a run owns, nine longs in one block so starting a run is one
; loop.  The send path writes them and the screen reads them.
PT_COUNTS           EQU PT_VARS+$050
PT_BYTES_WIN        EQU PT_COUNTS+$00       ; bytes sent in the window now open
PT_BYTES_TOTAL      EQU PT_COUNTS+$04
PT_LINES_TOTAL      EQU PT_COUNTS+$08
PT_REFUSALS         EQU PT_COUNTS+$0C
PT_ERRORS           EQU PT_COUNTS+$10
PT_RATE_NOW         EQU PT_COUNTS+$14       ; the last closed window, so bytes
PT_RATE_BEST        EQU PT_COUNTS+$18       ; a second
PT_RATE_MEAN        EQU PT_COUNTS+$1C
PT_SECS             EQU PT_COUNTS+$20       ; windows closed this run
PT_COUNTS_END       EQU PT_COUNTS+$24

PT_STALL_TICKS      EQU PT_VARS+$074        ; long, the ticks in STALL_SECS
PT_TICKS            EQU PT_VARS+$078        ; long, ticks in a second here
PT_WIN_AT           EQU PT_VARS+$07C        ; long, the tick the window opened
PT_STALL_AT         EQU PT_VARS+$080        ; long, the tick a stall opened

PT_PATH             EQU PT_VARS+$084        ; PATH_LIB4, LIB1 or TUNED4
PT_CHUNK            EQU PT_VARS+$085        ; and the bytes a command carries
PT_ARMED            EQU PT_VARS+$086        ; the session is open and checked
PT_HAVE_PIPE        EQU PT_VARS+$087
PT_PIPE             EQU PT_VARS+$088        ; the pipe the stream goes down
PT_TIMED            EQU PT_VARS+$089        ; a run of TIMED_SECS windows
PT_RUN_NO           EQU PT_VARS+$08A
PT_STAT             EQU PT_VARS+$08B        ; the status that ended the run
PT_LOST             EQU PT_VARS+$08C        ; the device needs putting together
PT_STALL            EQU PT_VARS+$08D        ; a stall is open on this line
PT_BURST            EQU PT_VARS+$08E        ; retries left before asking
PT_SAW_ROOM         EQU PT_VARS+$08F        ; the pipe reported room already
PT_STRIPE_COL       EQU PT_VARS+$090        ; body column holding the '#'
PT_STRIPE_DIG       EQU PT_VARS+$091        ; the ruler digit it covers
PT_LINE_TICK        EQU PT_VARS+$092        ; lines since the keyboard was read
PT_ADVANCED         EQU PT_VARS+$093        ; the next line is built already
PT_SEQ              EQU PT_VARS+$094        ; word, the line's sequence number

PT_NUM_VAL          EQU PT_VARS+$098        ; long, what the arithmetic eats
PT_NUM_DEN          EQU PT_VARS+$09C        ; long, what num_div divides by
PT_NUM_TXT          EQU PT_VARS+$0A0        ; 10 digits, right aligned
PT_NUM_FIRST        EQU PT_VARS+$0AA        ; the first of them

PT_LINE             EQU PT_VARS+$0B0        ; LINE_LEN bytes

PT_NOW              EQU PT_VARS+$100        ; FLD_COUNT*FLD_WIDTH
PT_SHOWN            EQU PT_VARS+$180        ; and what the screen already has
PT_END              EQU PT_SHOWN+(FLD_COUNT*FLD_WIDTH)
