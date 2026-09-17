; amiga_defs.s — Amiga hardware constants and chip RAM layout
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; ---------------------------------------------------------------------------
; Custom chip base and register offsets
; ---------------------------------------------------------------------------
CUSTOM              EQU $DFF000

DMACONR             EQU CUSTOM+$002     ; read: DMA control, and the blitter's
                                        ; busy flag in bit 14
VPOSR               EQU CUSTOM+$004     ; read: Agnus ID and vertical position
VHPOSR              EQU CUSTOM+$006     ; read: the rest of the beam position
INTENA              EQU CUSTOM+$09A
INTREQ              EQU CUSTOM+$09C
ADKCON              EQU CUSTOM+$09E
DMACON              EQU CUSTOM+$096
COLOR00             EQU CUSTOM+$180
COLOR01             EQU CUSTOM+$182
BPLCON0             EQU CUSTOM+$100
BPLCON1             EQU CUSTOM+$102
BPLCON2             EQU CUSTOM+$104
BPL1MOD             EQU CUSTOM+$108
BPL2MOD             EQU CUSTOM+$10A
BPL1PTH             EQU CUSTOM+$0E0
BPL1PTL             EQU CUSTOM+$0E2
DIWSTRT             EQU CUSTOM+$08E
DIWSTOP             EQU CUSTOM+$090
DDFSTRT             EQU CUSTOM+$092
DDFSTOP             EQU CUSTOM+$094
COP1LCH             EQU CUSTOM+$080
COPJMP1             EQU CUSTOM+$088
POTGO               EQU CUSTOM+$034     ; write: pot-pin direction and start
POTGOR              EQU CUSTOM+$016     ; read: pot-pin levels (POTINP)

; ---------------------------------------------------------------------------
; Blitter.  The pointer registers are the high word of a long, so a whole
; address goes in with one MOVE.L.
; ---------------------------------------------------------------------------
BLTCON0             EQU CUSTOM+$040
BLTCON1             EQU CUSTOM+$042
BLTAFWM             EQU CUSTOM+$044
BLTALWM             EQU CUSTOM+$046
BLTCPTH             EQU CUSTOM+$048
BLTBPTH             EQU CUSTOM+$04C
BLTAPTH             EQU CUSTOM+$050
BLTDPTH             EQU CUSTOM+$054
BLTSIZE             EQU CUSTOM+$058
BLTCMOD             EQU CUSTOM+$060
BLTBMOD             EQU CUSTOM+$062
BLTAMOD             EQU CUSTOM+$064
BLTDMOD             EQU CUSTOM+$066

; ---------------------------------------------------------------------------
; Audio channel 0, which plays the chime as the menu comes up
; ---------------------------------------------------------------------------
AUD0LCH             EQU CUSTOM+$0A0     ; sample address, high word of a long
AUD0LEN             EQU CUSTOM+$0A4     ; length in words
AUD0PER             EQU CUSTOM+$0A6     ; sample period
AUD0VOL             EQU CUSTOM+$0A8     ; volume, 0 to 64
INTREQR             EQU CUSTOM+$01E     ; read: interrupt requests
DMAF_AUD0           EQU $0001           ; the channel's bit in DMACON
INTF_AUD0           EQU $0080           ; the channel's bit in INTREQ, raised
                                        ; when the sample has played out

; VPOSR bit 12 is set by a PAL Agnus and clear by an NTSC one.
VPOSR_PAL           EQU $1000

; ---------------------------------------------------------------------------
; CIA-B time of day counter.  A 24-bit counter clocked by horizontal sync,
; 15625 Hz on a PAL machine and 15734 on an NTSC one, so a tick is 64 us and
; it runs for eighteen minutes before it wraps.  It counts on its own whatever
; the program is doing, which is what the beam position does not.
;
; Reading the high byte latches all three, reading the low byte lets it go, so
; they are read high, middle, low.  Writing any of them stops the counter
; until the low byte is written, which is how it is started from zero.
CIAB_TODLO          EQU $00BFD800
CIAB_TODMID         EQU $00BFD900
CIAB_TODHI          EQU $00BFDA00
CIAB_CRB            EQU $00BFDF00

; CIA-A registers
; Base $BFE001.  CIA registers use odd byte addresses with stride $100.
; ---------------------------------------------------------------------------
CIAA_BASE           EQU $BFE001
CIAA_PRA            EQU CIAA_BASE+$000      ; port A: OVL, LED, LMB
CIAA_DDRA           EQU CIAA_BASE+$200      ; port A direction register
CIAA_SDR            EQU CIAA_BASE+$C00      ; serial data register (keyboard)
CIAA_ICR            EQU CIAA_BASE+$D00      ; interrupt control / status
CIAA_CRA            EQU CIAA_BASE+$E00      ; control register A

; CIA-A PRA bit positions
CIAA_PRA_OVL        EQU 0                   ; overlay: 1=ROM at $0, 0=RAM at $0
CIAA_PRA_LED        EQU 1                   ; power LED: 0=on, 1=off
CIAA_PRA_LMB        EQU 6                   ; left mouse button: 0=pressed
POTGOR_RMB          EQU 10                  ; right mouse button in POTGOR: 0=pressed

; CIA-A ICR bit position
CIAA_ICR_SP         EQU 3                   ; serial port: 1=byte received

; CIA-A CRA bit position
CIAA_CRA_SPMODE     EQU 6                   ; 0=SP input (keyboard), 1=output

; ---------------------------------------------------------------------------
; Screen geometry
;
; 320 pixels wide, four bitplanes, 16 colours, 40x8 characters from an 8x8
; font.  NTSC shows 200 lines and PAL 256, both from the same scan line, so
; the layout is drawn for NTSC's 25 rows and PAL shows background below it.
;
; The bitmap is INTERLEAVED: for each pixel row, plane 0's 40 bytes, then
; plane 1's, plane 2's and plane 3's, then the next pixel row.  A four-plane
; object generated in the same shape is then one blit rather than four.
; ---------------------------------------------------------------------------
SCREEN_COLS         EQU 40                  ; characters across
SCREEN_ROWS         EQU 25                  ; character rows an NTSC machine shows
SCREEN_PLANES       EQU 4
SCREEN_BPL_W        EQU 40                  ; bytes in one plane of one pixel row
SCREEN_BPL_H        EQU 256                 ; pixel rows allocated, PAL's full height
SCREEN_ROW_BYTES    EQU SCREEN_BPL_W*SCREEN_PLANES  ; 160, all planes of a pixel row
SCREEN_BPL_MOD      EQU SCREEN_ROW_BYTES-SCREEN_BPL_W   ; 120, the other three planes
SCREEN_BPL_SZ       EQU SCREEN_ROW_BYTES*SCREEN_BPL_H   ; 40960 = $A000 bytes
ROW_STRIDE          EQU SCREEN_ROW_BYTES*8  ; 1280 bytes per character row

; ---------------------------------------------------------------------------
; Display window and data fetch
;
; DIWSTRT/DIWSTOP hold a vertical and a horizontal edge each.  The horizontal
; stop always has bit 8 forced to 1, and the vertical stop takes bit 8 as the
; inverse of bit 7 of the field.  So $2C81/$F4C1 is lines 44 to 243 and
; $2C81/$2CC1 is lines 44 to 299.  Both start at line 44, so the top of the
; bitmap lands in the same place whichever Agnus is fitted.  Horizontally both
; run 129 to 449, which is 320 lores pixels.
;
; DDFSTRT = (129-17)/2 = $38, DDFSTOP = $38 + 8*(40/2 - 1) = $D0.
; ---------------------------------------------------------------------------
DIW_START           EQU $2C81
DIW_STOP_NTSC       EQU $F4C1               ; 200 lines
DIW_STOP_PAL        EQU $2CC1               ; 256 lines
DDF_START           EQU $0038
DDF_STOP            EQU $00D0

; BPLCON0: four planes (bits 14-12) and colour enable (bit 9), lores.
BPLCON0_4PL         EQU $4200

; ---------------------------------------------------------------------------
; Palette — 16 pens, $0RGB.  The pens the artwork uses are fixed here because
; assets/logo.s was generated against exactly these values.
;
; Text is pen 5, not pen 1: pen 1 is white and so are the ball's light checks,
; so white text vanishes wherever the ball passes under it.  $0DDD still reads
; as white and stays visible against the ball.
; ---------------------------------------------------------------------------
PEN_BG              EQU 0                   ; background
PEN_TEXT            EQU 5                   ; every line of text on the screen
PEN_GOLD            EQU 2                   ; One ROM gold
PEN_LIGHT           EQU 5                   ; the footer and the device line

PEN00_RGB           EQU $0000               ; black
PEN01_RGB           EQU $0000               ; spare.  amiga_boot.s fails a build
                                            ; whose artwork uses pen 1
PEN02_RGB           EQU $0FB0               ; One ROM gold, #FFB700
PEN03_RGB           EQU $0111               ; near black, logo outline
PEN04_RGB           EQU $0333               ; logo chip body
PEN05_RGB           EQU $0DDD               ; logo pins
PEN06_RGB           EQU $0000               ; pens 6-13 belong to the ball
PEN07_RGB           EQU $0000
PEN08_RGB           EQU $0000
PEN09_RGB           EQU $0000
PEN10_RGB           EQU $0000
PEN11_RGB           EQU $0000
PEN12_RGB           EQU $0000
PEN13_RGB           EQU $0000
    ifne BANNER_SHADOW
PEN14_RGB           EQU $0333               ; the ball's drop shadow
    else
PEN14_RGB           EQU $0000               ; no shadow, so nothing draws in it
    endc
PEN15_RGB           EQU $0000               ; spare

; ---------------------------------------------------------------------------
; Colour constants (12-bit RGB) for the boot progress indicator, which runs
; before the copper takes COLOR00 over.
; ---------------------------------------------------------------------------
COL_WHITE           EQU $0FFF
COL_RED             EQU $0F00
COL_GREEN           EQU $00F0
COL_BLUE            EQU $000F
COL_YELLOW          EQU $0FF0
COL_PURPLE          EQU $0808

; ---------------------------------------------------------------------------
; Chip RAM layout
;
; Everything the application addresses with absolute short (.W) — variables,
; buffers and the stack — stays below $8000, which is as far as a 68000
; reaches that way.  The bitmap and the code are above it and are reached
; with absolute long addresses.
;
;   $000000-$0003FF  Exception vector table (256 vectors * 4 bytes)
;   $000400-$00041F  Boot trampoline (reserved for the boot-switch milestone)
;   $001000-$00101F  RBCP scratch RAM (32 bytes, CONFIG_RBCP_SCRATCH_BASE)
;   $001100-$0018FF  Copper list (2 KB reserved)
;   $002000-$002FFF  Application variables and buffers
;   $003000-$007EFF  Free
;   $007F00          Supervisor stack top (grows downward)
;   $008000-$011FFF  Interleaved bitmap (40*4*256 = 40960 bytes)
;   $012000-$0190BD  Artwork and the chime
;   $01A000-$023FFF  The foreground object (40960 bytes)
;   $024000-$0267FF  Its mask (10240 bytes)
;   $028000+         RAM code section (copied from ROM by boot_rom_entry)
;
; amiga_boot.s checks the end of the RAM code section against CHIP_RAM_MIN.
; ---------------------------------------------------------------------------
CHIP_TRAMPOLINE     EQU $00000400           ; boot trampoline destination
COPPER_BASE         EQU $00001100           ; copper list in chip RAM
APP_BASE            EQU $00002000           ; variables and buffers
STACK_TOP           EQU $00007F00           ; supervisor stack, grows down
BITPLANE_BASE       EQU $00008000           ; interleaved four-plane bitmap
RAM_CODE_BASE       EQU $00028000           ; all RBCP and application code
CHIP_RAM_MIN        EQU $00040000           ; what a base A500 has, 256 KB

; ---------------------------------------------------------------------------
; Banner artwork in chip RAM
;
; The blitter and Paula read chip RAM and nothing else, so the artwork and the
; sample are copied out of the ROM image at startup.  Each slot has a fixed
; address, so turning one switch off does not move the others.  amiga_boot.s
; checks every asset against the room its slot has.
;
; Three slots hold something built from the asset rather than copied:
;
;   _MASK    the object's one-plane mask, each row written four times, so one
;            blit cookie-cuts all four planes
;   _SHADOW  the ball's mask in planes 1 to 3 and nothing in plane 0, which is
;            pen 14 wherever the ball is solid
;
; CHIP_FG and CHIP_FG_MASK are the foreground object, built at run time.  Its
; mask has one plane, not four, because the blit that puts it back on screen
; is made a plane at a time.
; ---------------------------------------------------------------------------
CHIP_BALL           EQU $00012000           ; 2560, the ball's bitmap
CHIP_BALL_MASK      EQU $00012A00           ; 2560
CHIP_BALL_SHADOW    EQU $00013400           ; 2560
CHIP_LOGO           EQU $00013E00           ; 5888, the logo's bitmap
CHIP_LOGO_MASK      EQU $00015500           ; 5888
CHIP_TAGLINE        EQU $00016C00           ; 2128, the tagline's bitmap
CHIP_CHIME          EQU $00017500           ; 7094, the chime Paula plays
CHIP_FG             EQU $0001A000           ; 40960, the foreground object
CHIP_FG_MASK        EQU $00024000           ; 10240

; Single-byte application variables.  Response records and strings stay in the
; RBCP library's own un-swap buffer (CONFIG_RBCP_DATA_BUF).
VAR_BASE            EQU APP_BASE+$0000

VAR_TOTAL_RAM       EQU VAR_BASE+0          ; RAM slots the device has
VAR_ACTIVE_RAM      EQU VAR_BASE+1          ; the active RAM slot
VAR_TARGET_RAM      EQU VAR_BASE+2          ; RAM slot a load stages into
VAR_SINGLE_SLOT     EQU VAR_BASE+3          ; 1 = only one RAM slot, use LOAD_AND_EXIT
VAR_TOTAL_FLASH     EQU VAR_BASE+4          ; flash slots the device has
VAR_NUM_DISPLAY     EQU VAR_BASE+5          ; menu entries shown
VAR_SELECTION       EQU VAR_BASE+6          ; 0-based index into the shown list
VAR_LMB_HELD        EQU VAR_BASE+7          ; 1 while the left button stays down
VAR_NV_PRESENT      EQU VAR_BASE+8          ; 1 = the device can remember a choice
VAR_NV_STORED       EQU VAR_BASE+9          ; slot the device already had stored
VAR_PIPE_PRESENT    EQU VAR_BASE+10         ; 1 = pipe 0 is available for logging
VAR_BOOT_FLASH      EQU VAR_BASE+11         ; 1-based flash slot to boot
VAR_LED             EQU VAR_BASE+12         ; lowest RGB LED, or $FF if none
VAR_SAVED_KEY       EQU VAR_BASE+14         ; key held across a logging call
VAR_LOG_SLOT        EQU VAR_BASE+15         ; slot a log line is naming
VAR_ERR_NUM         EQU VAR_BASE+16         ; error number, for the diagnostics
VAR_RMB_HELD        EQU VAR_BASE+17         ; 1 while the right button stays down
VAR_LMB_UP_CNT      EQU VAR_BASE+18         ; polls the left button has read up
VAR_PEN             EQU VAR_BASE+20         ; pen the glyph itself is drawn in
VAR_PEN_BG          EQU VAR_BASE+21         ; pen the rest of the cell is drawn in
VAR_COL_MAX         EQU VAR_BASE+22         ; column screen_print stops at
VAR_MENU_COL        EQU VAR_BASE+23         ; column every menu entry starts at
VAR_IS_PAL          EQU VAR_BASE+24         ; 1 = PAL Agnus, set by screen_init
VAR_MENU_ROW0       EQU VAR_BASE+25         ; row the first image sits on
VAR_STATE           EQU VAR_BASE+26         ; the state main_loop is in
VAR_PEND_KEY        EQU VAR_BASE+27         ; key read but not yet acted on
VAR_REL_CNT         EQU VAR_BASE+28         ; long, passes left in ST_RELEASE
; VAR_BASE+32 is NAME_LEN_TAB.  Nothing more fits here.

; ---------------------------------------------------------------------------
; Main loop states.  One pass tests the state it is in once and returns, so
; nothing main_loop calls can sit waiting for anything.
; ---------------------------------------------------------------------------
ST_RELEASE          EQU 0                   ; waiting for the mouse buttons the
                                            ; menu was asked for with to come up
ST_MENU             EQU 1                   ; idle in the menu, reading input

; Passes of the main loop before ST_RELEASE gives up on a button that will not
; read up, so a stuck one cannot lock the machine out of its own menu.  A loop
; count, like the RBCP timeouts, not a unit.
RELEASE_LIMIT       EQU $00200000

; The short delay once both buttons have read up, so a contact bouncing on
; release does not slip a fresh press into the menu.  It waits for nothing and
; runs once.  A spin count, not a unit.
RELEASE_SETTLE      EQU $2000

; Polls the left button must read up before another press is taken, so the
; bounce either side of a click reads as one press.  A loop count, like the
; RBCP timeouts, not a unit.
LMB_DEBOUNCE        EQU 1500

; ---------------------------------------------------------------------------
; Menu screen layout — three bands down the 200 lines an NTSC machine shows
;
;   y   6- 19   the tagline artwork, 288x14, centred.  The page heading
;                 y  50-141   the logo, 112x92, at x=4
;                 row  7      what this is, in text, columns 16-39
;                 rows 9-16   the images, columns 16-39
;   y 168-175   row 21   the controls
;   y 184-191   row 23   the device line, with piers.rocks beside it
;
; The logo is 112 wide, leaving columns 16 to 39 for the text beside it — 24
; columns, of which three are the "N) " in front of a name, so a name has 21
; and anything longer is cut short rather than wrapped.  Column 16 starts at
; pixel 128, the first word past the logo, so the two never share a word and
; the mask of one cannot reach into the other.
;
; The title, the blank row under it and the entries are one block of N+2 rows
; for N entries, centred on the logo's centre line 95.5, so the title row is
;
;     (MENU_CENTRE_SUM - N) / 2
;
; and the entries start MENU_TITLE_GAP rows below it.  VAR_MENU_ROW0 holds the
; result, worked out once the count is known.
; ---------------------------------------------------------------------------
MENU_CENTRE_SUM     EQU 23
MENU_TITLE_GAP      EQU 2
MENU_COL            EQU 16                  ; first column right of the logo
FOOTER_ROW          EQU 21
DEVICE_ROW          EQU 23
DEVICE_COL          EQU 0
ROCKS_COL           EQU SCREEN_COLS-11      ; "piers.rocks" is 11 chars

MAX_DISPLAY         EQU 8                   ; rows 9-16, one digit key each
MENU_PREFIX         EQU 3                   ; the "N) " in front of a name

; The beam line an animation step is taken from, and the line wait_field
; watches for.  The ball goes anywhere on the display, so a step has to happen
; while the beam is off it altogether: the line after the last displayed one,
; round to line 44 where the next field begins.  That is 62 lines on NTSC and
; 56 on PAL, against a step that blits for about 45.
FIELD_TICK_NTSC     EQU 244
FIELD_TICK_PAL      EQU 300

; Menu name store — one slot name per entry, as read from the device.
NAME_STRIDE         EQU 32                  ; room per name, as read
NAME_LEN_TAB        EQU APP_BASE+$20        ; MAX_DISPLAY lengths, 0 = no entry
NAME_BUF            EQU APP_BASE+$40        ; MAX_DISPLAY*NAME_STRIDE bytes

; The foreground object — everything on screen except the ball, laid out
; exactly as the bitmap is, with a one-plane mask beside it.  The banner
; section of amiga_boot.s says what it is for.
FG_BYTES            EQU SCREEN_BPL_SZ               ; 40960
FG_MASK_BYTES       EQU SCREEN_BPL_W*SCREEN_BPL_H   ; 10240

; The list's words within a plane row, which start past the logo's last.
FG_LIST_W0          EQU MENU_COL/2
FG_LIST_WORDS       EQU (SCREEN_COLS-MENU_COL)/2

    ifne CONFIG_BANNER_ART
LOGO_X              EQU 4
LOGO_Y              EQU 50                  ; the text beside it is centred on this
TAGLINE_X           EQU 16                  ; 288 wide, centred across 320
TAGLINE_Y           EQU 6
    endc

    ifne CONFIG_BANNER_BALL
    ifne BANNER_SHADOW
BALL_SHADOW_OFF     EQU 4                   ; pixels down and right of the ball
    else
BALL_SHADOW_OFF     EQU 0
    endc

; The rectangle the ball is put back over covers it wherever it starts within
; a word.  64 pixels from any bit of a word need five words, and a shadow four
; pixels further right needs a sixth.
    ifne BANNER_SHADOW
BALL_CLR_W          EQU BALL_WIDTH_W+1
    else
BALL_CLR_W          EQU BALL_WIDTH_W
    endc
BALL_CLR_H          EQU BALL_HEIGHT+BALL_SHADOW_OFF

; Travel.  The right limit is the furthest start column whose rectangle still
; lands inside the 20 words of a plane row.  The bottom limit is set at run
; time, because an NTSC machine shows 200 lines where a PAL one shows 256 and
; the ball must not go off the bottom of either.
BALL_X_MIN          EQU 0
BALL_X_MAX          EQU (SCREEN_BPL_W/2-BALL_CLR_W+1)*16-1
BALL_Y_MAX_NTSC     EQU SCREEN_ROWS*8-BALL_CLR_H
BALL_Y_MAX_PAL      EQU SCREEN_BPL_H-BALL_CLR_H

BALL_START_X        EQU 96
BALL_START_Y        EQU 24
BALL_VX             EQU $0200               ; 8.8 pixels a frame, so 2 across
BALL_VY             EQU $00C0               ; and three quarters down

; Frames between one step of BallCycle and the next.  Eight steps take the
; ball a quarter turn, and at two pixels a frame that works out close to the
; rate a ball of this size would actually roll at.
BANNER_SPIN_FRAMES  EQU 3
    endc

    ifne CONFIG_BOOT_CHIME
; Fields the volume is faded over when a boot cuts the chime off part way
; through — see chime_stop.
CHIME_RAMP_FIELDS   EQU 4

; The chime's length in TOD ticks, one per horizontal sync.  A little over the
; sample, so the channel is switched off in its silent tail.
CHIME_TICKS_PAL     EQU (CHIME_MS*15625+999)/1000
CHIME_TICKS_NTSC    EQU (CHIME_MS*15734+999)/1000

; How long after the menu is asked for before the chime starts.  One second.
CHIME_WAIT_PAL      EQU 15625
CHIME_WAIT_NTSC     EQU 15734
CHIME_VOLUME        EQU 64
    endc

; Where the text routines draw.  The bitmap normally, and the band's object
; while that is being built.
VAR_DRAW_BASE       EQU APP_BASE+$160

; Banner state.  It sits above NAME_BUF, which runs to APP_BASE+$13F.
BANNER_VARS         EQU APP_BASE+$140
VAR_BALL_X          EQU BANNER_VARS+0       ; 8.8 fixed point, kept in a long
VAR_BALL_Y          EQU BANNER_VARS+4
VAR_BALL_VX         EQU BANNER_VARS+8       ; word, 8.8 fixed point
VAR_BALL_VY         EQU BANNER_VARS+10
VAR_BALL_PX         EQU BANNER_VARS+12      ; word, where the ball was drawn
VAR_BALL_PY         EQU BANNER_VARS+14
VAR_SPIN_STEP       EQU BANNER_VARS+16      ; row of BallCycle on show
VAR_SPIN_TICK       EQU BANNER_VARS+17      ; frames until the next row
VAR_FRAME_SEEN      EQU BANNER_VARS+18      ; 1 once this field has been stepped
VAR_BALL_Y_MAX      EQU BANNER_VARS+20      ; 8.8 in a long, the Agnus decides
VAR_TICK_LINE       EQU BANNER_VARS+24      ; word, first beam line off display
VAR_CHIME_ON        EQU BANNER_VARS+26      ; 0 idle, 1 waiting to start, 2 playing
VAR_CHIME_END       EQU BANNER_VARS+28      ; long, the TOD tick it is done at
VAR_ANIM_STEP       EQU BANNER_VARS+27      ; the step of the frame being drawn
VAR_ANIM_PLANE      EQU BANNER_VARS+28      ; plane the cover blit has reached
; BANNER_VARS+32 is VAR_DRAW_BASE.  Nothing more fits here.

; ---------------------------------------------------------------------------
; Steps of one animation frame.  Each sets up a single blit and returns, and
; the next pass of the main loop takes the next once the blitter is free.
; ---------------------------------------------------------------------------
AN_IDLE             EQU 0                   ; between frames, watching the beam
AN_RESTORE          EQU 1                   ; the band back over the old place
AN_SHADOW           EQU 2                   ; the shadow at the new place
AN_DRAW             EQU 3                   ; the ball at the new place
AN_COVER            EQU 4                   ; the band over it, a plane a step

; Error numbers, indices into the error message table.
ERR_NO_CMD_RESP     EQU 0
ERR_VERSION         EQU 1
ERR_RAM_INFO        EQU 2
ERR_FLASH_INFO      EQU 3
ERR_NO_IMAGES       EQU 4
ERR_LOAD            EQU 5
ERR_TITLE_ROW       EQU 12                  ; the error screen's own heading
ERROR_ROW           EQU 14
ERROR_COL           EQU 2

; ---------------------------------------------------------------------------
; Input token constants
; ---------------------------------------------------------------------------
KEY_NONE            EQU 0
KEY_UP              EQU 1
KEY_DOWN            EQU 2
KEY_RETURN          EQU 3
KEY_ESC             EQU 4
KEY_LMB             EQU 5
KEY_RMB             EQU 6

; Amiga keyboard scancodes (key press, bit 7 clear)
KBD_RETURN          EQU $44
KBD_UP              EQU $4C
KBD_DOWN            EQU $4D
KBD_ESC             EQU $45

; ---------------------------------------------------------------------------
; Copper register offsets (within the custom chip $DFF000 address space)
; The bitplane pointers run BPL1PTH, BPL1PTL, BPL2PTH ... four bytes apart,
; and the colour registers two bytes apart, so both are indexed.
; ---------------------------------------------------------------------------
COP_BPL1PTH         EQU $00E0
COP_BPL1PTL         EQU $00E2
COP_BPLCON0         EQU $0100
COP_BPLCON1         EQU $0102
COP_BPLCON2         EQU $0104
COP_BPL1MOD         EQU $0108
COP_BPL2MOD         EQU $010A
COP_DDFSTRT         EQU $0092
COP_DDFSTOP         EQU $0094
COP_DIWSTRT         EQU $008E
COP_DIWSTOP         EQU $0090
COP_COLOR00         EQU $0180
