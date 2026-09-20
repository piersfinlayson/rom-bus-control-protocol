; amiga_defs.s — the bootloader's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

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
;   _SHADOW  the ball's mask in planes 1 to 3 and nothing in plane 0, so it
;            comes out pen 14 wherever the ball is solid
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

; The bootloader's variables sit at the offsets from VAR_BASE the common code
; leaves free.  That code owns 0, 4, 7, 10, 13, 14, 16 to 24.
; Response records and strings stay in the RBCP library's un-swap buffer
; (CONFIG_RBCP_DATA_BUF).

VAR_ACTIVE_RAM      EQU VAR_BASE+1          ; the active RAM slot
VAR_TARGET_RAM      EQU VAR_BASE+2          ; RAM slot a load stages into
VAR_SINGLE_SLOT     EQU VAR_BASE+3          ; 1 = only one RAM slot, use LOAD_AND_EXIT
VAR_NUM_DISPLAY     EQU VAR_BASE+5          ; menu entries shown
VAR_SELECTION       EQU VAR_BASE+6          ; 0-based index into the shown list
VAR_NV_PRESENT      EQU VAR_BASE+8          ; 1 = the device can remember a choice
VAR_NV_STORED       EQU VAR_BASE+9          ; slot the device already had stored
VAR_BOOT_FLASH      EQU VAR_BASE+11         ; 1-based flash slot to boot
VAR_LED             EQU VAR_BASE+12         ; lowest RGB LED, or $FF if none
VAR_LOG_SLOT        EQU VAR_BASE+15         ; slot a log line is naming
VAR_MENU_ROW0       EQU VAR_BASE+25         ; row the first image sits on
VAR_STATE           EQU VAR_BASE+26         ; the state main_loop is in
VAR_PEND_KEY        EQU VAR_BASE+27         ; key read but not yet acted on
VAR_REL_CNT         EQU VAR_BASE+28         ; long, passes left in ST_RELEASE
; VAR_BASE+32 is NAME_LEN_TAB.  Nothing more fits here.

; ---------------------------------------------------------------------------
; Main loop states.  One pass tests the state it is in once and returns, so
; nothing main_loop calls can sit waiting for anything.
; ---------------------------------------------------------------------------
ST_RELEASE          EQU 0                   ; waiting for the two mouse buttons
                                            ; to come up
ST_MENU             EQU 1                   ; idle in the menu, reading input

; Passes of the main loop before ST_RELEASE gives up on a button that will not
; read up, so a stuck one cannot lock the machine out of its own menu.  A loop
; count, like the RBCP timeouts, not a unit.
RELEASE_LIMIT       EQU $00200000

; The short delay once both buttons have read up, so a contact bouncing on
; release does not slip a fresh press into the menu.  It waits for nothing and
; runs once.  A spin count, not a unit.
RELEASE_SETTLE      EQU $2000

; ---------------------------------------------------------------------------
; Menu screen layout — three bands down the 200 lines an NTSC machine shows
;
;   y   6- 19   the tagline artwork, 288x14, centred — the page heading
;   y  50-141   the logo, 112x92, at x=4
;   y  56- 63   row  7      the heading as text, columns 16-39
;   y  72-143   rows 9-17   the images, columns 16-39
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

MAX_DISPLAY         EQU 9                   ; rows 9-17, one digit key each
MENU_PREFIX         EQU 3                   ; the "N) " in front of a name

; Menu name store — one slot name per entry, as read from the device.  NAME_BUF
; sits above the RBCP un-swap buffer, where there is room for the whole of it
; and nothing to step around.
NAME_STRIDE         EQU 32                  ; room per name, as read
NAME_LEN_TAB        EQU APP_BASE+$20        ; MAX_DISPLAY lengths, 0 = no entry
NAME_BUF            EQU APP_BASE+$300       ; MAX_DISPLAY*NAME_STRIDE bytes

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
BALL_VX             EQU $0200               ; 8.8 fixed point, two pixels a frame across
BALL_VY             EQU $00C0               ; and three quarters of one down

; Frames between one step of BallCycle and the next.  Eight steps take the
; ball a quarter turn, and at two pixels a frame that is close to the rate a
; ball of this size would roll at.
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

; Banner state, in the gap the common code leaves between VAR_BASE and the two
; of its own at APP_BASE+$158.
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
; BANNER_VARS+24 is VAR_TICK_LINE and +26 is VAR_SHIFT_HELD, both the common
; code's.  +27 to +31 are the last bytes free before VAR_DRAW_BASE at +32.
VAR_ANIM_STEP       EQU BANNER_VARS+27      ; the step of the frame being drawn
VAR_ANIM_PLANE      EQU BANNER_VARS+28      ; plane the cover blit has reached

; The chime's two, clear of the block above, which has no room for a long.
VAR_CHIME_ON        EQU APP_BASE+$180       ; 0 idle, 1 waiting to start, 2 playing
VAR_CHIME_END       EQU APP_BASE+$184       ; long, the TOD tick it is done at

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
