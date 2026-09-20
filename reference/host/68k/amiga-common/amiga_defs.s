; amiga_defs.s — Amiga hardware constants, screen geometry and chip RAM layout
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; ---------------------------------------------------------------------------
; Custom chip base and register offsets
; ---------------------------------------------------------------------------
CUSTOM              EQU $DFF000

DMACONR             EQU CUSTOM+$002     ; read: DMA control with the blitter's
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
; Audio channel 0, which plays an application's chime
; ---------------------------------------------------------------------------
AUD0LCH             EQU CUSTOM+$0A0     ; sample address, high word of a long
AUD0LEN             EQU CUSTOM+$0A4     ; length in words
AUD0PER             EQU CUSTOM+$0A6     ; sample period
AUD0VOL             EQU CUSTOM+$0A8     ; volume, 0 to 64
INTREQR             EQU CUSTOM+$01E     ; read: interrupt requests
DMAF_AUD0           EQU $0001           ; the channel's bit in DMACON
INTF_AUD0           EQU $0080           ; the channel's bit in INTREQ.  It is
                                        ; raised once the sample has played out

; VPOSR bit 12 is set by a PAL Agnus and clear by an NTSC one.
VPOSR_PAL           EQU $1000

; ---------------------------------------------------------------------------
; CIA-B time of day counter.  Horizontal sync clocks it — 15625 Hz on a PAL
; machine and 15734 on an NTSC one — so a tick is 64 us and it runs for
; eighteen minutes before it wraps.  It counts on its own whatever the program
; is doing.
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

; POTGOR bit position
POTGOR_RMB          EQU 10                  ; right mouse button: 0=pressed

; CIA-A ICR bit position
CIAA_ICR_SP         EQU 3                   ; serial port: 1=byte received

; CIA-A CRA bit position
CIAA_CRA_SPMODE     EQU 6                   ; 0=SP input (keyboard), 1=output

; ---------------------------------------------------------------------------
; Screen geometry
;
; 320 pixels wide, four bitplanes, 16 colours, 40x25 characters from an 8x8
; font.  NTSC shows 200 lines and PAL 256, both from the same scan line, so
; the layout is drawn for NTSC's 25 rows and PAL shows background below it.
;
; The bitmap is interleaved.  For each pixel row, plane 0's 40 bytes, then
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
; Palette — 16 pens, $0RGB.  Every pen is a default an application overrides
; by defining it before this file.  The bootloader's artwork is generated
; against the values here.
;
; Text is pen 5, $0DDD, rather than white.  The light checks on the
; bootloader's bouncing ball are $0FFF, so white text vanishes wherever that
; ball passes under it.  $0DDD still reads as white and stays visible.
;
; Pens 0 to 5 are the logo and the text, pens 6 to 13 the ball's checks, pen
; 14 the drop shadow and pen 15 spare.  An application that draws none of it
; can set all sixteen.
; ---------------------------------------------------------------------------
PEN_BG              EQU 0                   ; background
PEN_TEXT            EQU 5                   ; every line of text on the screen
PEN_GOLD            EQU 2                   ; One ROM gold
PEN_LIGHT           EQU 5                   ; the device line along the bottom

    ifnd PEN00_RGB
PEN00_RGB           EQU $0000               ; black
    endc
    ifnd PEN01_RGB
PEN01_RGB           EQU $0000               ; spare.  Artwork that uses pen 1
    endc                                    ; comes out as background
    ifnd PEN02_RGB
PEN02_RGB           EQU $0FB0               ; One ROM gold, #FFB700
    endc
    ifnd PEN03_RGB
PEN03_RGB           EQU $0111               ; near black, logo outline
    endc
    ifnd PEN04_RGB
PEN04_RGB           EQU $0333               ; logo chip body
    endc
    ifnd PEN05_RGB
PEN05_RGB           EQU $0DDD               ; logo pins
    endc
    ifnd PEN06_RGB
PEN06_RGB           EQU $0000
    endc
    ifnd PEN07_RGB
PEN07_RGB           EQU $0000
    endc
    ifnd PEN08_RGB
PEN08_RGB           EQU $0000
    endc
    ifnd PEN09_RGB
PEN09_RGB           EQU $0000
    endc
    ifnd PEN10_RGB
PEN10_RGB           EQU $0000
    endc
    ifnd PEN11_RGB
PEN11_RGB           EQU $0000
    endc
    ifnd PEN12_RGB
PEN12_RGB           EQU $0000
    endc
    ifnd PEN13_RGB
PEN13_RGB           EQU $0000
    endc
    ifnd PEN14_RGB
PEN14_RGB           EQU $0000
    endc
    ifnd PEN15_RGB
PEN15_RGB           EQU $0000
    endc

; ---------------------------------------------------------------------------
; Colour constants (12-bit RGB) for the boot progress indicator.  It runs
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
;   $000400-$00041F  Boot trampoline
;   $001000-$00101F  RBCP scratch RAM (32 bytes, CONFIG_RBCP_SCRATCH_BASE)
;   $001100-$0018FF  Copper list (2 KB reserved)
;   $002000-$002FFF  Application variables and buffers
;   $003000-$007EFF  Free
;   $007F00          Supervisor stack top (grows downward)
;   $008000-$011FFF  Interleaved bitmap (40*4*256 = 40960 bytes)
;   $012000-$027FFF  Free for the application
;   $028000+         RAM code section (copied from ROM by boot_rom_entry)
;
; Each application checks the end of its RAM code section against CHIP_RAM_MIN.
; ---------------------------------------------------------------------------
CHIP_TRAMPOLINE     EQU $00000400           ; boot trampoline destination
COPPER_BASE         EQU $00001100           ; copper list in chip RAM
APP_BASE            EQU $00002000           ; variables and buffers
STACK_TOP           EQU $00007F00           ; supervisor stack, grows down
BITPLANE_BASE       EQU $00008000           ; interleaved four-plane bitmap
RAM_CODE_BASE       EQU $00028000           ; all RBCP and application code
CHIP_RAM_MIN        EQU $00040000           ; a base A500's chip RAM, 256 KB

; ---------------------------------------------------------------------------
; The device line along the bottom, with the author beside it.
; ---------------------------------------------------------------------------
DEVICE_ROW          EQU 23
DEVICE_COL          EQU 0
ROCKS_COL           EQU SCREEN_COLS-11      ; "piers.rocks" is 11 chars

; The beam line an animation step is taken from, and the line wait_field
; watches for.  It is the first line off the bottom of the display, which
; leaves the gap to line 44 where the next field begins — 62 lines on NTSC
; and 56 on PAL.  VAR_TICK_LINE holds it.
FIELD_TICK_NTSC     EQU 244
FIELD_TICK_PAL      EQU 300

; ---------------------------------------------------------------------------
; Variables the shared routines own, at fixed offsets from VAR_BASE.  The
; offsets an application uses run between them.
; ---------------------------------------------------------------------------
VAR_BASE            EQU APP_BASE+$0000

VAR_TOTAL_RAM       EQU VAR_BASE+0          ; RAM slots the device has
VAR_TOTAL_FLASH     EQU VAR_BASE+4          ; flash slots the device has
VAR_LMB_HELD        EQU VAR_BASE+7          ; 1 while the left button stays down
VAR_PIPE_PRESENT    EQU VAR_BASE+10         ; 1 = there is a pipe to log through
VAR_LINE_CUT        EQU VAR_BASE+13         ; 1 = a newline is owed, because the
                                            ; last line could not be finished
VAR_SAVED_KEY       EQU VAR_BASE+14         ; a byte held across a device query
VAR_ERR_NUM         EQU VAR_BASE+16         ; error number, for the diagnostics
VAR_RMB_HELD        EQU VAR_BASE+17         ; 1 while the right button stays down
VAR_LMB_UP_CNT      EQU VAR_BASE+18         ; word over 18 and 19, polls the
                                            ; left button has read up
VAR_PEN             EQU VAR_BASE+20         ; pen the glyph itself is drawn in
VAR_PEN_BG          EQU VAR_BASE+21         ; pen the rest of the cell is drawn in
VAR_COL_MAX         EQU VAR_BASE+22         ; column screen_print stops at
VAR_MENU_COL        EQU VAR_BASE+23         ; column a filled row starts at
VAR_IS_PAL          EQU VAR_BASE+24         ; 1 = PAL Agnus, set by screen_init

; Where the text routines draw.  The bitmap normally, and an off-screen
; object while the application is building one.
VAR_DRAW_BASE       EQU APP_BASE+$160

VAR_TICK_LINE       EQU APP_BASE+$158       ; word
VAR_SHIFT_HELD      EQU APP_BASE+$15A       ; 1 while either shift key is down

; 1 between the keyboard's lost-sync code and the code it repeats behind it,
; so amiga_getkey drops the repeat.  Clear of the four bytes of VAR_DRAW_BASE.
VAR_KEY_RESEND      EQU APP_BASE+$164

; The pipe every log line goes down.  VAR_LMB_UP_CNT holds both the bytes in
; the VAR_BASE run it would sit in, so it is here.  It starts as whatever chip
; RAM held, which nothing reads — log_open sets it with VAR_PIPE_PRESENT and
; the log says nothing until then.
VAR_LOG_PIPE        EQU APP_BASE+$165

; The device state the error screen and the log both report, copied on entry
; to err_halt.  Sending the log is itself an RBCP command, so by the time it
; has gone the scratch bytes hold that command and the device has rewritten
; the response header.  Both readers take their values from here.
VAR_ERR_SNAP        EQU APP_BASE+$170       ; 8 bytes
VAR_ES_STAGE        EQU VAR_ERR_SNAP+0      ; RBCP_ERROR_CODE
VAR_ES_SGRP         EQU VAR_ERR_SNAP+1      ; RBCP_GROUP, the group sent
VAR_ES_SCMD         EQU VAR_ERR_SNAP+2      ; RBCP_CMD, the command sent
VAR_ES_DGRP         EQU VAR_ERR_SNAP+3      ; group the device last processed
VAR_ES_DCMD         EQU VAR_ERR_SNAP+4      ; command the device last processed
VAR_ES_TOK          EQU VAR_ERR_SNAP+5      ; token LSB
VAR_ES_PRG          EQU VAR_ERR_SNAP+6      ; progress
VAR_ES_RSP          EQU VAR_ERR_SNAP+7      ; response

; Polls the left button must read up before another press is taken, so the
; bounce either side of a click reads as one press.  A loop count rather than a
; unit of time.  The RBCP timeouts are counts in the same way.
LMB_DEBOUNCE        EQU 1500

; How many times a write the device will not take is tried.  A log line is not
; under test and a line cut in the middle is a record lost.
LOG_TRIES           EQU 4

; Rows and column the error screen draws at.
ERR_TITLE_ROW       EQU 12                  ; the error screen's own heading
ERROR_ROW           EQU 14
ERROR_COL           EQU 2

; ---------------------------------------------------------------------------
; Input token constants
;
; amiga_getkey returns either a character or one of these.  Every token is
; below $20 and every character is $20 to $7E, so `CMPI.B #$20,D0` separates
; them and $1F is the highest a new token may take.  DEL is a token rather
; than its ASCII $7F for that reason.
;
; KEY_UP to KEY_RMB are fixed by the values applications already use, so the
; list is not in key order.
; ---------------------------------------------------------------------------
KEY_NONE            EQU 0
KEY_UP              EQU 1
KEY_DOWN            EQU 2
KEY_RETURN          EQU 3
KEY_LEFT            EQU 4
KEY_LMB             EQU 5
KEY_RMB             EQU 6
KEY_RIGHT           EQU 7
KEY_BACKSPACE       EQU 8
KEY_DEL             EQU 9
KEY_TAB             EQU 10
KEY_ESC             EQU 11

; Amiga keyboard scancodes (key press, bit 7 clear)
KBD_SHIFT_L         EQU $60
KBD_SHIFT_R         EQU $61

; The whole decoded byte, not a scancode.  The keyboard sends it to say the
; code before it went unhandshaked, and sends that code again behind it.
KBD_LOST_SYNC       EQU $F9

; Scancodes $00 to $40 are the typing keys, ending at the space bar, and
; kbd_plain and kbd_shifted give the character each one stands for.  BACKSPACE
; at $41 is the first key with a name instead, and cursor left at $4F the last
; one amiga_getkey decodes.
KBD_NAMED_FIRST     EQU $41
KBD_NAMED_COUNT     EQU $0F

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

; ---------------------------------------------------------------------------
; CONFIG_BOOT_CHIME — an application that plays a chime defines it as 1 and
; supplies chime_stop, which the error screen calls before it halts.
; ---------------------------------------------------------------------------
    ifnd CONFIG_BOOT_CHIME
CONFIG_BOOT_CHIME   EQU 0
    endc
