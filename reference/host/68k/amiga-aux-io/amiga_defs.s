; amiga_defs.s — the tester's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

; ---------------------------------------------------------------------------
; Limits
;
; A device reporting more groups or more pins than these is shown up to the
; limit, and the note row says so.
; Four groups is one more than any One ROM board exposes, and a pin's index
; into the tables is group*MAX_PINS+pin, so MAX_PINS is a power of two.
;
; MAX_PINS is what the five tables below hold at MAX_GROUPS*MAX_PINS bytes
; each, rather than what a board has.  The smallest pad puts 36 pads on a row
; and ten rows on the board.  That is more than the tables carry.
; ---------------------------------------------------------------------------
MAX_GROUPS          EQU 4
MAX_PINS            EQU 128
MAX_PINS_SHIFT      EQU 7

; ---------------------------------------------------------------------------
; Group types beyond the two the protocol defines.  A One ROM names its image
; select pads by letter and its X pads from one, and both read as a number
; with its low end on the right, so both are drawn right to left.
; ---------------------------------------------------------------------------
RBCP_AUX_TYPE_IMGSEL EQU $80
RBCP_AUX_TYPE_XPADS  EQU $81

; ---------------------------------------------------------------------------
; How long the reset pin is held low before it is released, in the 10ms units
; the protocol counts holds in.  A device accepting less than this gets what it
; will take, and one that times no holds at all cannot pulse a pin.
;
; The reset screen shows the hold in milliseconds and print_dec reads a byte,
; so it has to stay small enough for the answer to fit one.
; ---------------------------------------------------------------------------
RESET_HOLD          EQU 20                  ; 200ms
    ifgt RESET_HOLD*10-255
    fail "RESET_HOLD in milliseconds does not fit a byte"
    endc

; ---------------------------------------------------------------------------
; A field, in CIA-B time of day ticks.  A tick is one scan line.
;
; The pins are read again every field, and where a board has more pins than a
; field can ask about the sweep stops and carries on next field.  What it has
; left is the rest of the field, so the reading fills whatever the drawing
; leaves rather than a fixed slice: a fixed slice one line too long costs a
; whole field waiting for the next one.
;
; SCAN_SPARE is what the field keeps back for the draw to start on time.  The
; sweep stops that far short, and a further read's worth short again, so a
; slow device stops rather than running over.
; ---------------------------------------------------------------------------
FIELD_LINES_PAL     EQU 312
FIELD_LINES_NTSC    EQU 262
SCAN_SPARE          EQU 6

; The CIA-B counter is clocked by horizontal sync, so a second is that many
; ticks and the two machines differ.
TOD_SEC_PAL         EQU 15625
TOD_SEC_NTSC        EQU 15734

; ---------------------------------------------------------------------------
; The command timer.
;
; Four commands, each sent TIME_RUNS times, each run timed on its own.  The
; count is a power of two so the mean is a shift, and one run's worth of
; anything unusual moves a figure by a two-hundred-and-fifty-sixth of itself.
; ---------------------------------------------------------------------------
TIME_RUNS           EQU 256
TIME_RUNS_SHIFT     EQU 8
TIME_CMDS           EQU 4

T_CMD_PIN           EQU 0                   ; GET_AUX_PIN_INFO
T_CMD_GRP           EQU 1                   ; GET_AUX_GROUP_INFO
T_CMD_WR            EQU 2                   ; PIPE_WRITE
T_CMD_RD            EQU 3                   ; PIPE_READ

; What a figure on the timer screen is.
T_NONE              EQU 0                   ; nothing has been timed yet
T_OK                EQU 1
T_LOST              EQU 2                   ; the device stopped answering
T_ABSENT            EQU 3                   ; there is no pipe to ask
T_NO_PIPE           EQU $FF                 ; in AUX_T_PIPE_OUT and _IN

; ---------------------------------------------------------------------------
; The clock the timer reads.  A tick is 64us on a PAL machine and 63.556us on
; an NTSC one.  The multiplier and the shift are worked out in
; amiga_auxio_time.s.
; ---------------------------------------------------------------------------
TOD_US_PAL          EQU 4096                ; 64.000us over 256 runs
TOD_US_NTSC         EQU 4067                ; 63.556us over 256 runs
US_SHIFT            EQU 14

; ---------------------------------------------------------------------------
; The font at three times the size, for the figures the timer screen exists to
; show.  A big character is three bytes across and 24 pixel rows deep, so a
; row of the screen holds thirteen of them.
; ---------------------------------------------------------------------------
BIG_W_BYTES         EQU 3
BIG_H               EQU 24
BIG_COLS            EQU SCREEN_BPL_W/BIG_W_BYTES
BIG_ROW_STRIDE      EQU BIG_H*SCREEN_ROW_BYTES

; ---------------------------------------------------------------------------
; Pens.  amiga_auxio.s gives each of these its colour before the common
; palette is included.
;
; Red, white and blue for the three things that can own a pin, and a darker
; shade of each for the centre of a pad whose level is low, so a pin's owner
; reads at either level.  Two more carry the board and the light line along
; its edge.
; ---------------------------------------------------------------------------
PEN_BOARD           EQU 1                   ; the board the pads sit on
PEN_EDGE            EQU 4                   ; and the light line along it
PEN_OURS            EQU 6                   ; the Amiga is driving this pin
PEN_FREE            EQU 7                   ; nobody is driving it
PEN_THEIRS          EQU 8                   ; the device ROM has it reserved
PEN_LABEL           EQU 9                   ; every label and heading
PEN_NOTE            EQU 10                  ; the line of plain English
PEN_OURS_LOW        EQU 11
PEN_FREE_LOW        EQU 12
PEN_THEIRS_LOW      EQU 13
PEN_SHINE           EQU 14                  ; spare
PEN_SHADE           EQU 15                  ; spare

; ---------------------------------------------------------------------------
; Screen layout — 40 columns by the 25 rows an NTSC machine shows
; ---------------------------------------------------------------------------
ROW_TITLE           EQU 0
ROW_DEVICE          EQU 1                   ; the device's own names
ROW_GROUP           EQU 3                   ; the heading band
ROW_COUNT           EQU 4                   ; how many of its pins can be driven
ROW_LEGEND          EQU 5                   ; what a pad's pen and fill mean
ROW_RINGS           EQU 6
ROW_RINGS_END       EQU 21
ROW_NOTE            EQU 22
ROW_KEYS1           EQU 23
ROW_KEYS2           EQU 24

COL_TITLE           EQU 1
COL_BRAND           EQU SCREEN_COLS-12
COL_GROUP           EQU 2
COL_DEV_VER         EQU 16                  ; the device row: type, then
COL_DEV_PROTO       EQU SCREEN_COLS-11      ; version, then protocol
COL_OF              EQU 31                  ; "n OF m" at the right of the band
BAND_WIDTH          EQU COL_OF+6-COL_GROUP  ; "n OF m" is six columns
COL_RATE            EQU 33                  ; the read rate, under the band

; The space the board sits in, in pixels.  The board itself is as deep as the
; page's own pads and headings come to and sits in the middle of that space,
; so a page with one row of pads sits as deliberately as a page with four.  A
; pad row starts PIN_TOP_PAD below the board's top edge so the light line along
; it is not drawn over.
PIN_Y0              EQU ROW_RINGS*8
PIN_H               EQU (ROW_RINGS_END+1-ROW_RINGS)*8
PIN_TOP_PAD         EQU 3

; The legend's pads, in pixels, each with its word in the columns after it.
LEG_X_OURS          EQU 16
LEG_X_FREE          EQU 72
LEG_X_THEIRS        EQU 120
LEG_X_HIGH          EQU 176
LEG_X_LOW           EQU 240

; ---------------------------------------------------------------------------
; The timer screen.  Four big rows carry the figures, and the ordinary font
; below them carries the spread, the pin and pipes they were measured on, and
; the way out.
;
; A big row is three text rows deep.  A label is eight big columns and the
; figure the five after it, which is the whole width.
; ---------------------------------------------------------------------------
ROW_T_UNITS         EQU 13                  ; what the big figures are
ROW_T_HEAD          EQU 14                  ; what each column under them is
ROW_T_DETAIL        EQU 15                  ; one row a command
ROW_T_ASKED         EQU 20                  ; the pin and the pipes asked about
ROW_T_BACK          EQU 22

T_LABEL_W           EQU 8                   ; columns a command's name is given
T_FIG_W             EQU 5                   ; and a figure
COL_T_FIG           EQU T_LABEL_W           ; big, straight after the label

COL_T_MINV          EQU 10                  ; the detail row's four figures
COL_T_MAXV          EQU 16
COL_T_FRAMEV        EQU 22
COL_T_BADV          EQU 31
COL_T_MIN           EQU 12                  ; and the heading over each
COL_T_MAX           EQU 18
COL_T_FRAME         EQU 22
COL_T_BAD           EQU 29

COL_T_GROUP         EQU 1                   ; the row naming what was asked
COL_T_GROUPV        EQU 7
COL_T_PIN           EQU 9
COL_T_PINV          EQU 13
COL_T_OUT           EQU 17
COL_T_OUTV          EQU 26
COL_T_IN            EQU 28
COL_T_INV           EQU 36

; The reset screen, laid out from the top of the board down.
ROW_R_PIN           EQU ROW_RINGS
ROW_R_HOLD          EQU ROW_RINGS+2
ROW_R_IMAGE         EQU ROW_RINGS+4
ROW_R_ENDS          EQU ROW_RINGS+7
COL_R_VAL           EQU 16                  ; clear of the widest label
    ifgt ROW_R_ENDS+2-ROW_RINGS_END
    fail "the reset screen does not fit above the note row"
    endc

; ---------------------------------------------------------------------------
; Pad sizes, largest first.  amiga_auxio_art.s holds the tables.  A group's
; drivable pin count picks the largest pad that holds them all on the board.
; The page holding every pin picks between the last two, because it has a
; heading for each group to fit as well.
; ---------------------------------------------------------------------------
TIER_LAST           EQU 3
TIER_NO_LABEL       EQU 255                 ; a pad too small to letter
; The composed pads.  One set of rows for each role at each level, at the
; largest size a pad comes in.
PAD_ROWS_MAX        EQU 20
PAD_VARIANTS        EQU 6
PAD_ROW_BYTES       EQU SCREEN_PLANES*4
PAD_VAR_BYTES       EQU PAD_ROWS_MAX*PAD_ROW_BYTES
PAD_CACHE_BYTES     EQU PAD_VARIANTS*PAD_VAR_BYTES

ALL_TIER_BIG        EQU 2
ALL_TIER_SMALL      EQU 3

; ---------------------------------------------------------------------------
; Pin table encoding.  The flags byte is what GET_AUX_PIN_INFO reported.  The
; state byte is its level and driven bytes folded into two bits, which is all
; a pad needs.
; ---------------------------------------------------------------------------
PIN_LEVEL_BIT       EQU $01
PIN_DRIVEN_BIT      EQU $02

; ---------------------------------------------------------------------------
; The descriptor of a pad on screen, so a refresh can tell whether it is still
; right.  The bits outside the level and the driven flag are the ones that
; move the label or the bracket as well, and so need the whole box drawn
; again rather than the pad's rows alone.
; ---------------------------------------------------------------------------
DESC_SEL            EQU $10                 ; the cursor is on this pin
DESC_DRAWN          EQU $80                 ; the pad has been drawn once
DESC_SETTLED        EQU $FC

; ---------------------------------------------------------------------------
; Each pin's role, which indexes the pen tables a pad is drawn from.
; ---------------------------------------------------------------------------
ROLE_THEIRS         EQU 0
ROLE_FREE           EQU 1
ROLE_OURS           EQU 2

; ---------------------------------------------------------------------------
; The note row.  Nothing outside the drawing code holds a string, so a caller
; passes one of these.
; ---------------------------------------------------------------------------
NOTE_BLANK          EQU 0                   ; the row is empty
NOTE_NO_DRIVE       EQU 1                   ; every pin here belongs to the ROM
NOTE_BLINKING       EQU 2                   ; the selected pin is blinking
NOTE_REFUSED        EQU 3                   ; the device rejected a command
NOTE_NOT_DRIVABLE   EQU 4                   ; the selected pin is read only
NOTE_TRUNCATED      EQU 5                   ; more than this program shows
NOTE_GONE           EQU 6                   ; a terminal command has been sent
NOTE_NO_PULSE       EQU 7                   ; the device times no holds
NOTE_COUNT          EQU 8

; ---------------------------------------------------------------------------
; Error numbers, indices into the error message table err_halt reads.  Each
; one is a session that never opened, and there is no way back from any of
; them.
; ---------------------------------------------------------------------------
ERR_NO_DEVICE       EQU 0
ERR_ENTER           EQU 1
ERR_VERSION         EQU 2
ERR_NO_AUX          EQU 3
ERR_LOST            EQU 4

; ---------------------------------------------------------------------------
; The keys.  All four cursor keys walk the drivable pins, and the pages are on
; the brackets, which is where the C64 tester puts them.
; ---------------------------------------------------------------------------
KEY_PAGE_NEXT       EQU ']'
KEY_PAGE_PREV       EQU '['
KEY_LOW             EQU 'l'
KEY_HIGH            EQU 'h'
KEY_RELEASE         EQU 'z'
KEY_BLINK           EQU 'b'
KEY_RESET           EQU 'r'
KEY_TIME            EQU 't'

; ---------------------------------------------------------------------------
; The tester's variables, in the chip RAM the application owns.  The common
; code owns VAR_BASE+0 to 24, APP_BASE+$158 to $15A, APP_BASE+$160 to $165 and
; APP_BASE+$170 to $177, and the library's un-swap buffer is at $2200, so
; everything here starts clear of them.
; ---------------------------------------------------------------------------
AUX_VARS            EQU APP_BASE+$400

; The device's own names.  Read once while the session is opening,
; because a device that has stopped answering will not answer a question about
; its own name either.
AUX_DEV_TYPE        EQU AUX_VARS+$000       ; 25 bytes
AUX_DEV_VER         EQU AUX_VARS+$020       ; 25
AUX_PROTO           EQU AUX_VARS+$040       ; 12
AUX_FLASH_NAME      EQU AUX_VARS+$050       ; 32, the image the reset offers

; The device's reported capabilities.
AUX_GROUP_COUNT     EQU AUX_VARS+$080       ; groups this program will show
AUX_MAX_HOLD        EQU AUX_VARS+$081       ; 10ms units, 0 for no timed holds
AUX_GROUP_TYPE      EQU AUX_VARS+$082       ; MAX_GROUPS bytes
AUX_GROUP_PINS      EQU AUX_VARS+$086       ; pins the device reports
AUX_GROUP_DRV       EQU AUX_VARS+$08A       ; how many of them are drivable
AUX_TRUNCATED       EQU AUX_VARS+$08E       ; more pins than this program shows

; Where the cursor is.
AUX_CUR_GROUP       EQU AUX_VARS+$090
AUX_CUR_SLOT        EQU AUX_VARS+$091       ; index into the drivable list
AUX_CUR_PAGE        EQU AUX_VARS+$092       ; a group, or the all-pins page
AUX_BLINK_PHASE     EQU AUX_VARS+$093

; The arguments the next SET_AUX carries beyond the state.
AUX_HOLD            EQU AUX_VARS+$094       ; 10ms units
AUX_AFTER           EQU AUX_VARS+$095

; The session, and what the reset screen needs from it.
AUX_CAN_SWITCH      EQU AUX_VARS+$096       ; there is a spare RAM slot
AUX_SPARE_SLOT      EQU AUX_VARS+$097       ; and this is it
AUX_FLASH_COUNT     EQU AUX_VARS+$098
AUX_RESET_PIN       EQU AUX_VARS+$099       ; the pin the reset screen drives
AUX_RESET_FLASH     EQU AUX_VARS+$09A       ; and the image it comes back as

; How the page on screen is laid out.
AUX_VIEW_TIER       EQU AUX_VARS+$0A0       ; the pad size it picked
AUX_VIEW_N          EQU AUX_VARS+$0A1       ; pads on it
AUX_VIEW_ROWS       EQU AUX_VARS+$0A2       ; and rows of them
AUX_REPAINT         EQU AUX_VARS+$0A3       ; the board goes down again
AUX_BOARD_Y         EQU AUX_VARS+$0F6       ; word, the board's top row
AUX_BOARD_H         EQU AUX_VARS+$0F8       ; word, and how deep it is

; The pad being drawn.
AUX_CELL_X          EQU AUX_VARS+$0A4       ; word, its box's left edge
AUX_CELL_Y          EQU AUX_VARS+$0A6       ; word, and its top
AUX_CELL_TIER       EQU AUX_VARS+$0A8
AUX_CELL_PADX       EQU AUX_VARS+$0A9       ; the pad's place in the box
AUX_CELL_ROLE       EQU AUX_VARS+$0AA
AUX_CELL_HIGH       EQU AUX_VARS+$0AB       ; 1 where the level is high
AUX_CELL_SEL        EQU AUX_VARS+$0AC       ; 1 where the cursor is on it
AUX_CELL_PART       EQU AUX_VARS+$0AD       ; 1 for the pad's rows alone
AUX_CELL_PIN        EQU AUX_VARS+$0AE
AUX_CELL_GROUP      EQU AUX_VARS+$0AF
AUX_CELL_BG         EQU AUX_VARS+$0B0       ; what the box sits on
AUX_BR_RUN          EQU AUX_VARS+$0B1       ; the bracket's run on this row
AUX_LAB_LEN         EQU AUX_VARS+$0B2
AUX_LAB_X           EQU AUX_VARS+$0B3
AUX_LABEL           EQU AUX_VARS+$0B4       ; 4 bytes

; One row of a box, built before it is written.
AUX_BOX_BYTES       EQU AUX_VARS+$0B8
AUX_PEN_A           EQU AUX_VARS+$0B9       ; the ring, or the label
AUX_PEN_B           EQU AUX_VARS+$0BA       ; the centre
AUX_PEN_C           EQU AUX_VARS+$0BB       ; the selection bracket
AUX_PEN_D           EQU AUX_VARS+$0BC       ; and whatever none of them claims
AUX_MASK_A          EQU AUX_VARS+$0C0       ; long
AUX_MASK_B          EQU AUX_VARS+$0C4
AUX_MASK_C          EQU AUX_VARS+$0C8
AUX_ROWBUF          EQU AUX_VARS+$0CC       ; 4 longs, one a plane

; A row of the page holding every pin.
AUX_ALL_GROUP       EQU AUX_VARS+$0E0
AUX_ALL_REV         EQU AUX_VARS+$0E1       ; its pins run right to left
AUX_ALL_BASE        EQU AUX_VARS+$0E2       ; word, the row's first pin
AUX_ALL_CNT         EQU AUX_VARS+$0E4       ; word, pads on the row
AUX_ALL_LEFT        EQU AUX_VARS+$0E6       ; word, its left edge
AUX_ALL_PER         EQU AUX_VARS+$0E8       ; word, pads a full row holds
AUX_ALL_BOXH        EQU AUX_VARS+$0EA       ; word, how deep a row is

; The sweep and what it is measured against.
AUX_SCAN_NEXT       EQU AUX_VARS+$0EC       ; word, where the sweep is
AUX_SWEEPS          EQU AUX_VARS+$0EE       ; whole passes since the last count
AUX_FPS             EQU AUX_VARS+$0EF       ; and the count itself
AUX_RATE_TOD        EQU AUX_VARS+$0F0       ; long, when that count started
AUX_KEY_STASH       EQU AUX_VARS+$0F4       ; a key held until the loop is ready
AUX_FIELD_TOD       EQU AUX_VARS+$0FC       ; long, when this field began

; The pins themselves, group*MAX_PINS+pin.
AUX_PIN_FLAGS       EQU AUX_VARS+$100       ; MAX_GROUPS*MAX_PINS
AUX_PIN_STATE       EQU AUX_VARS+$300
AUX_DRV_LIST        EQU AUX_VARS+$500       ; drivable pin numbers, in order
AUX_PIN_DRAWN       EQU AUX_VARS+$700       ; what each pad on screen shows

; A figure being written out, lowest digit first.
AUX_DEC_BUF         EQU AUX_VARS+$900       ; 6 bytes

; ---------------------------------------------------------------------------
; The command timer.  One batch at a time is summed in the first block, and
; what every batch so far came to is kept in the arrays below it, one entry a
; command.  A count is CIA-B ticks until the batch ends and microseconds after
; it.
; ---------------------------------------------------------------------------
AUX_BIG_ROW         EQU AUX_VARS+$930       ; 3 bytes, one row of a big glyph
AUX_T_TEXT          EQU AUX_VARS+$934       ; 6 bytes, a figure as characters
AUX_T_SUM           EQU AUX_VARS+$93C       ; long, this batch's runs summed
AUX_T_MIN           EQU AUX_VARS+$940       ; long, its shortest run
AUX_T_MAX           EQU AUX_VARS+$944       ; long, and its longest
AUX_T_TOD           EQU AUX_VARS+$948       ; long, the whole batch off CIA-B
AUX_T_BAD           EQU AUX_VARS+$94C       ; word, runs the device refused
AUX_T_TOD_MUL       EQU AUX_VARS+$956       ; word, CIA-B ticks to microseconds
AUX_T_NARGS         EQU AUX_VARS+$958       ; argument bytes the command takes
AUX_T_PIPE_OUT      EQU AUX_VARS+$959       ; the pipe PIPE_WRITE goes down
AUX_T_PIPE_IN       EQU AUX_VARS+$95A       ; and the one PIPE_READ comes off
AUX_T_GROUP         EQU AUX_VARS+$95B       ; the group the aux commands ask about
AUX_T_PIN           EQU AUX_VARS+$95C       ; and the pin

AUX_T_US            EQU AUX_VARS+$960       ; TIME_CMDS words, the mean
AUX_T_MINS          EQU AUX_VARS+$968
AUX_T_MAXS          EQU AUX_VARS+$970
AUX_T_FRAMES        EQU AUX_VARS+$978       ; the whole frame, host included
AUX_T_BADS          EQU AUX_VARS+$980
AUX_T_STATE         EQU AUX_VARS+$988       ; TIME_CMDS bytes
; The two flags the drawer reads before it draws.  The sweep marks the pins the
; device reported differently, so a field where nothing moved draws nothing
; and a field where two pins moved draws two pads.
AUX_MOVED           EQU AUX_VARS+$990       ; a pin has come back different
AUX_FORCE           EQU AUX_VARS+$991       ; every pad drawn again this field
AUX_LAST_PAGE       EQU AUX_VARS+$992       ; where the cursor was last drawn
AUX_LAST_GROUP      EQU AUX_VARS+$993
AUX_LAST_SLOT       EQU AUX_VARS+$994

; The composed pads.  A pad's own rows carry neither its label nor the
; selection bracket, so their contents depend only on the pad size, the
; background, the role and the level.  Every combination is built once when
; the page is laid out and written straight to the bitmap after that.
AUX_PAD_OK          EQU AUX_VARS+$995       ; there is something in the cache
AUX_PAD_TIER        EQU AUX_VARS+$996       ; the size it was built at
AUX_PAD_BG          EQU AUX_VARS+$997       ; and the background under it

AUX_PIN_DIRTY       EQU AUX_VARS+$A00       ; MAX_GROUPS*MAX_PINS
AUX_PAD_CACHE       EQU AUX_VARS+$C00       ; PAD_CACHE_BYTES
AUX_END             EQU AUX_PAD_CACHE+PAD_CACHE_BYTES
