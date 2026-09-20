; amiga_defs.s — the LED tester's own constants
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The hardware, the screen geometry and the chip RAM layout are in
; ../amiga-common/amiga_defs.s, which is included before this file.

; ---------------------------------------------------------------------------
; How many LEDs the screen holds
;
; Two character rows each on the table and three on the lamps screen, which is
; what twenty-five rows allow.  A device reporting more is shown as its first
; six and says so on screen rather than truncating quietly.
; ---------------------------------------------------------------------------
LED_MAX             EQU 6

; ---------------------------------------------------------------------------
; Animation
;
; The LED's state is drawn as it happens, on the Amiga's own clock at the
; period the device reports.  The two are not synchronised and cannot be.
;
; A step is a number of fields, and a field is 20ms on a PAL machine and 17ms
; on an NTSC one.  Five fields to a protocol period unit is exact on PAL and a
; sixth short on NTSC.
; ---------------------------------------------------------------------------
ANIM_FIELDS_UNIT    EQU 5               ; fields in one 100ms period unit
ANIM_DEFAULT_PERIOD EQU 20              ; two seconds, where the device reports
                                        ; no period
ANIM_FULL           EQU 255             ; a lamp at the brightness reported

; Fields between refresh scans.  A scan is one GET_LED_INFO per LED, so the
; picture is as live as the device is fast.  At LED_MAX that is six commands
; and about 4ms, a fifth of a PAL field, and it goes into the bitmap the copper
; is not showing, so a scan every field neither tears nor crowds the field out.
SCAN_FIELDS         EQU 1

PARADE_FIELDS       EQU 100             ; fields the parade holds each mode for
RECOVER_TRIES       EQU 3               ; goes at a reset before the device is
                                        ; given up for lost
OPEN_TRIES          EQU 4               ; goes at each command that finds the
                                        ; report's pipe

; ---------------------------------------------------------------------------
; The values the stepping keys walk.  Each is a short list because a keyboard
; is a bad way to type a number and a bad number is worth nothing here — they
; are for putting the LED somewhere a camera can see.
; ---------------------------------------------------------------------------
COLOUR_COUNT        EQU 8               ; the device's own choice, then seven
BRIGHT_STEPS        EQU 5               ; device chooses, 25, 50, 75, 100
PERIOD_STEPS        EQU 5               ; the mode's default, 0.5s, 1s, 2s, 5s
HOLD_STEPS          EQU 5               ; none, 0.5s, 1s, 2s, 5s

; One ROM's own flame mode.  The spec reserves $80 to $FE for implementations
; to use as they like, so this belongs to the application and not to the
; library's list of modes every device has.
LED_MODE_FLAME      EQU $80
LED_MODE_COUNT      EQU 6               ; the modes the protocol names

; ---------------------------------------------------------------------------
; The keys.  amiga_getkey returns a letter in the case it was typed in, and
; ORing KEY_LOWER in makes the two the same key before any of these is tried.
; ---------------------------------------------------------------------------
KEY_LOWER           EQU $20
KEY_MODE            EQU 'm'
KEY_COLOUR          EQU 'c'
KEY_BRIGHT          EQU 'b'
KEY_PERIOD          EQU 'p'
KEY_HOLD            EQU 'h'
KEY_PARADE          EQU 'a'
KEY_TABLE           EQU 't'
KEY_LAMPS           EQU 'l'

; ---------------------------------------------------------------------------
; The three screens.  Every key works on all of them and they differ only in
; what is drawn.
; ---------------------------------------------------------------------------
SCR_TABLE           EQU 0               ; a row per LED and the send fields
SCR_LAMPS           EQU 1               ; every LED as a lamp big enough to read
SCR_COLOURS         EQU 2               ; the colour list, stepped in place

; ---------------------------------------------------------------------------
; Response data section offsets rbcp_defs.s does not name.  The ones it does —
; RBCP_LED_CAP_COUNT, RBCP_LED_INFO_TYPE, RBCP_LED_INFO_MODE,
; RBCP_LED_MODE_FLAGS and RBCP_LED_MODE_MIN_PERIOD — are used from there.
; ---------------------------------------------------------------------------
LED_CAP_MAX_PERIOD  EQU 1
LED_CAP_MAX_HOLD    EQU 2
LED_INFO_RED        EQU 2
LED_INFO_GREEN      EQU 3
LED_INFO_BLUE       EQU 4
LED_INFO_BRIGHT     EQU 5
LED_INFO_PERIOD     EQU 6
LED_INFO_MODES      EQU 8

; ---------------------------------------------------------------------------
; Pens.  amiga_led_test.s gives each of these its colour before the common
; palette is included.  Gold stays the title band, the brand, the mode in
; force and whatever the keys are on, so a label in its own pen does not
; compete with them.
;
; A lamp is four pens — a lit centre, the body of the lens, its dark edge and
; the light it throws on what it is sitting on.  The copper writes all four at
; the top of every lamp's own band of scan lines, so six lamps in six different
; colours cost four pens between them.  PEN_LENS is the package around the
; lens and is the same on every lamp, so it is a fixed colour.
; ---------------------------------------------------------------------------
PEN_LABEL           EQU 6               ; every label and heading
PEN_WARN            EQU 7               ; there is no pipe to report down
PEN_LAMP            EQU 8               ; centre, then body, edge and glow
PEN_SWATCH          EQU 12              ; a colour in the list, then its edge
PEN_BAD             EQU 14              ; a refusal and a read back that differs
PEN_LENS            EQU 15

; A lamp's four pens where the LED is not lit.  A lens with nothing
; behind it still has a shape, so it keeps the shading and loses the colour.
LENS_CORE_RGB       EQU $0666
LENS_BODY_RGB       EQU $0555
LENS_EDGE_RGB       EQU $0444
LENS_GLOW_RGB       EQU $0000

; The strip behind the selected LED, which the copper paints over the whole
; scan line.  The marker and the pen the row's text takes say the same thing
; up close and this says it across the room.
HILITE_RGB          EQU $0113

; ---------------------------------------------------------------------------
; Screen layout — 40 columns by the 25 rows an NTSC machine shows
;
; The rows above the LEDs and the rows below them are fixed.  The rows between
; belong to the LEDs, and how many of those there are is the device's to say,
; so the spacing is worked out at run time.  See "Laying entries into a space"
; below.
;
; ROW_DEV is the same line on all three screens.  It carries the device's name,
; its version and the protocol version and nothing else, so a reader who
; changes screen is reading the same line in the same place.
; ---------------------------------------------------------------------------
ROW_TITLE           EQU 0
ROW_DEV             EQU 1
ROW_COUNTS          EQU 2               ; how many LEDs, and the longest hold
ROW_PIPE            EQU 3               ; the report's pipe and max period
ROW_HEAD            EQU 4
ROW_MODES           EQU 17              ; the modes the selected LED has
ROW_SEND_HEAD       EQU 18
ROW_SENDS           EQU 19              ; the next command's fields
ROW_MODE_INFO       EQU 20              ; the period the next command's mode
                                        ; needs
ROW_STATUS          EQU 21              ; a read back that differs, or the note
                                        ; that a key could not send
ROW_KEYS1           EQU 22
ROW_KEYS2           EQU 23
ROW_KEYS3           EQU 24

COL_TITLE           EQU 1
COL_BRAND           EQU SCREEN_COLS-12  ; "PIERS.ROCKS" and a space
COL_TEXT            EQU 1
COL_PROTO           EQU SCREEN_COLS-10  ; "RBCP 0.1.2", hard right, where the
                                        ; device's own name and version leave
                                        ; the rest of the row
COL_MAX_HOLD        EQU 26
COL_MAX_PERIOD      EQU 23

; The LED table.  Every row is these columns and so is the heading over it.
; The lamp takes the first six columns, so a row is cleared from COL_MARK
; rightwards and the lamp under it is never crossed.
COL_MARK            EQU 6               ; the selected LED's marker
COL_NUM             EQU 7
COL_TYPE            EQU 9               ; MONO, RGB, or the number
COL_MODE            EQU 14              ; BREATHE is the longest
COL_RGB             EQU 22              ; the three colour bytes
COL_BRI             EQU 29
COL_PER             EQU 34

; The next command's fields, under a heading in the same columns.
COL_SEND_COL        EQU 7
COL_SEND_BRI        EQU 15
COL_SEND_PER        EQU 23
COL_SEND_HOLD       EQU 32

; The key legend, in columns ten apart.  Three of them are named here and a
; fourth entry runs on from the third, so the legend reads as a block rather
; than as three sentences.
KEYS_COL1           EQU 1
KEYS_COL2           EQU 11
KEYS_COL3           EQU 21

; ---------------------------------------------------------------------------
; The lamps screen — every LED at once, three character rows of text each,
; with the lamp big enough to read from where the board is.  This is the
; screen the tester opens on.
; ---------------------------------------------------------------------------
LAMPS_COL           EQU 6               ; the text beside the lamp
LAMPS_COL_TYPE      EQU 12
LAMPS_COL_MODE      EQU 18
LAMPS_COL_BRI       EQU 14
LAMPS_COL_PER       EQU 21
LAMPS_TEXT_ROWS     EQU 3

; ---------------------------------------------------------------------------
; The colour page — the list the C key steps through, in place, with the LED
; it is stepping beside it.
; ---------------------------------------------------------------------------
PICK_ROW_HEAD       EQU ROW_COUNTS
PICK_COL_NAME       EQU 5
PICK_COL_RGB        EQU 13
PICK_COL_LED        EQU 28              ; the caption over the LED's own lamp
PICK_TEXT_ROWS      EQU 1

; ---------------------------------------------------------------------------
; Laying entries into a space
;
; How many LEDs there are is the device's to say, so no screen can be drawn to
; a fixed plan.  Each one names the rows it may spend on entries, the fewest
; and the most character rows it will give one, and layout_entries divides the
; space: as many rows an entry as it will take, then the entries centred in
; what is left over.  Nothing here is top justified.
;
; _ROWS is the rows the entries may be drawn on and _SPACE the rows they are
; centred in.  The two differ where something else can appear below them: the
; status row is empty until a read back differs, so it is part of the gap a
; reader sees but not a row an entry may take.
; ---------------------------------------------------------------------------
TABLE_TOP           EQU ROW_HEAD+1
TABLE_ROWS          EQU ROW_MODES-TABLE_TOP
TABLE_SPACE         EQU TABLE_ROWS      ; the modes row is always drawn
TABLE_PITCH_MIN     EQU 2
TABLE_PITCH_MAX     EQU 3               ; a third row is as far apart as a set
                                        ; of numbers still reads as a table
TABLE_TEXT_ROWS     EQU 1

LAMPS_TOP           EQU ROW_COUNTS+1
LAMPS_ROWS          EQU ROW_STATUS-LAMPS_TOP
LAMPS_SPACE         EQU ROW_KEYS1-LAMPS_TOP
LAMPS_PITCH_MIN     EQU LAMPS_TEXT_ROWS
LAMPS_PITCH_MAX     EQU 5               ; past this the lamp is capped by the
                                        ; width of its column, not the band

PICK_TOP            EQU PICK_ROW_HEAD+1
PICK_ROWS           EQU ROW_STATUS-PICK_TOP
PICK_SPACE          EQU ROW_KEYS1-PICK_TOP
PICK_PITCH_MIN      EQU 2               ; eight colours in eighteen rows leave
PICK_PITCH_MAX      EQU 2               ; room for no more

; ---------------------------------------------------------------------------
; The two bitmaps
;
; The CPU draws a character cell at a time and a screen is a thousand of them,
; so building one takes about a quarter of a second.  Built where it can be
; seen that is a quarter of a second of half a screen.  Everything is drawn
; into the bitmap the copper is not showing and the two are exchanged between
; fields, so what is on the screen is always a finished picture.
;
; The back bitmap sits directly above the front one.  RAM_CODE_BASE is at
; $28000 and the pair end at $1C000, so nothing else is in the way.
; ---------------------------------------------------------------------------
BITPLANE_BACK       EQU BITPLANE_BASE+SCREEN_BPL_SZ

; The blit that brings the two into step after an exchange.  BLTSIZE carries
; the width in six bits, so a blit row is at most 64 words.  The bitmap is
; contiguous, so 40 words go at a zero modulo and 512 rows cover it.
SWAP_WORDS          EQU 40
SWAP_ROWS           EQU SCREEN_BPL_SZ/(SWAP_WORDS*2)

; ---------------------------------------------------------------------------
; Where a band's WAIT points.  The first displayed line is the one DIWSTRT
; names, and a band waits for the far end of the line above its own so that
; the MOVEs after the WAIT have landed before the band is drawn.
; ---------------------------------------------------------------------------
COP_LINE0           EQU DIW_START>>8
COP_WAIT_HP         EQU $DF             ; past the last pixel fetched, and odd
                                        ; because that is what makes it a WAIT

; ---------------------------------------------------------------------------
; The lamps themselves, in pixels.  A One ROM's LED is round, so the lamp on
; the screen is round: an Amiga pixel is taller than it is wide on an NTSC
; machine and a little wider than tall on a PAL one, and the half-width is
; picked from the Agnus fitted so that both draw a circle.
;
; The glow reaches GLOW_NUM/GLOW_DEN of the way out again, so a lamp's whole
; footprint is that much larger than its lens.
; ---------------------------------------------------------------------------
GLOW_NUM            EQU 11
GLOW_DEN            EQU 10

; A lamp's footprint stays inside its own band of scan lines, because the band
; below it is where the next lamp's pens are written.  A half-height of B
; reaches B*GLOW_NUM/GLOW_DEN+1 rows either side of the centre, so a band of
; LT_PITCH character rows takes the largest B whose reach is under half of it.
; lamp_half holds that B for each pitch the two lamp screens allow.
;
; The lamp stands in the six columns left of the text on both screens, which
; is 48 pixels.  A half-height of 16 reaches 21 columns either side of
; LAMP_CX, and 18 would touch the text.
LAMP_CX             EQU 24
LAMP_B_MAX          EQU 16

PICK_CX             EQU 20              ; a swatch in the colour list
PICK_B              EQU 6

; The LED the colour page is picking for, in the half of the screen the list
; leaves empty.  The caption is five characters, so PICK_COL_LED*8+20 is where
; its middle falls, and the lamp is centred under that.
;
; The caption and the lamp under it are one block, centred on the list beside
; them.  PICK_LED_ROWS is how deep the pair comes to — a row of text, the gap
; and the lamp's own 2*PICK_LED_REACH — to the nearest character row.
PICK_LED_CX         EQU 244
PICK_LED_B          EQU 24
PICK_LED_REACH      EQU 27              ; PICK_LED_B*GLOW_NUM/GLOW_DEN+1
PICK_LED_GAP        EQU 16              ; the caption's row, and one clear
PICK_LED_ROWS       EQU 9

; ---------------------------------------------------------------------------
; Status codes.  Passed to draw_note in D0.  Nothing outside the drawing
; routines holds a string.
;
; The note and the read back share one row.  A key that sends draws the read
; back last and a key that could not draws its note last, so whichever of the
; two has something to say is the one left standing.
; ---------------------------------------------------------------------------
NOTE_BLANK          EQU 0
NOTE_REFUSED        EQU 1               ; the device rejected a SET_LED
NOTE_NO_COLOUR      EQU 2               ; this LED's colour is not ours to set
NOTE_NO_PERIOD      EQU 3               ; this mode takes no period on this LED
NOTE_NO_HOLD        EQU 4               ; the device times no holds
NOTE_PARADE         EQU 5
NOTE_SLIPPED        EQU 6               ; a command was lost and the device came
                                        ; back
NOTE_GONE           EQU 7
NOTE_COUNT          EQU 8

; ---------------------------------------------------------------------------
; The last SET_LED's read back.  The only check this program can make on
; its own — nothing it reads proves an LED lit, but a device that reports back
; something other than what it was given has been caught in the act.
;
; A device that agrees says nothing on the screen.  SET_LED reported success
; and GET_LED_INFO answers out of what SET_LED wrote, so agreement is the
; ordinary case and a line saying so is a line that is always there.
; ---------------------------------------------------------------------------
READ_NONE           EQU 0               ; nothing has been set yet
READ_MATCH          EQU 1
READ_DIFFERS        EQU 2
READ_REFUSED        EQU 3
READ_COUNT          EQU 4

; The field a read back that differs names, and the order read_fields and
; read_field_len are written in.
RDF_MODE            EQU 0
RDF_BRIGHT          EQU 1
RDF_PERIOD          EQU 2
RDF_RED             EQU 3
RDF_GREEN           EQU 4
RDF_BLUE            EQU 5
RDF_COUNT           EQU 6

; The state a failed command leaves behind, as take_failure reports it.
FAIL_REFUSED        EQU 0               ; the device answered and said no
FAIL_BACK           EQU 1               ; it did not answer and the reset worked
FAIL_GONE           EQU 2               ; it did not answer and it is not coming
                                        ; back

; Whether there is a table to draw, and why not.
LEDS_PRESENT        EQU 0
LEDS_NONE           EQU 1               ; the device has none
LEDS_NO_GROUP       EQU 2               ; the device answers no LED command

; ---------------------------------------------------------------------------
; Error numbers, indices into the error message table.  Only a session that
; never opened ends this way.  A device with no LEDs is not an error — it is an
; answer, and the screen says so.
; ---------------------------------------------------------------------------
ERR_NO_DEVICE       EQU 0
ERR_ENTER           EQU 1
ERR_VERSION         EQU 2

; ---------------------------------------------------------------------------
; The tester's variables, in the chip RAM the application owns.  The common
; code owns VAR_BASE+0 to 24, APP_BASE+$158 to $15A, APP_BASE+$160 to $165 and
; APP_BASE+$170 to $177, and the library's un-swap buffer is at $2200, so
; everything here starts clear of them.  Words are at even offsets.
; ---------------------------------------------------------------------------
LT_VARS             EQU APP_BASE+$400

LT_DEV_TYPE         EQU LT_VARS+$000    ; 25 bytes, read once
LT_DEV_VER          EQU LT_VARS+$020    ; 25
LT_PROTO            EQU LT_VARS+$040    ; 12

LT_COUNT            EQU LT_VARS+$050    ; LEDs the screen holds
LT_TOTAL            EQU LT_VARS+$051    ; LEDs the device reports
LT_MAX_PERIOD       EQU LT_VARS+$052    ; 100ms units, zero if none is accepted
LT_MAX_HOLD         EQU LT_VARS+$053    ; 100ms units, zero if none is timed
LT_CUR              EQU LT_VARS+$054    ; the LED the keys land on
LT_STATE            EQU LT_VARS+$055    ; LEDS_PRESENT, NONE or NO_GROUP
LT_GONE             EQU LT_VARS+$056    ; the device is not coming back
LT_READ             EQU LT_VARS+$057    ; the last SET_LED's read back

; The GET_LED_INFO report, a table per field.
LT_TYPE             EQU LT_VARS+$058
LT_MODE             EQU LT_VARS+$060
LT_RED              EQU LT_VARS+$068
LT_GREEN            EQU LT_VARS+$070
LT_BLUE             EQU LT_VARS+$078
LT_BRIGHT           EQU LT_VARS+$080    ; percentage, zero where the LED has none
LT_PERIOD           EQU LT_VARS+$088    ; 100ms units, zero for none in force
LT_MODES            EQU LT_VARS+$090    ; bit N set where mode N is supported

; The next command's fields.  Each is an entry in one of the stepping lists
; rather than a value.
LT_W_MODE           EQU LT_VARS+$098    ; this one is the mode itself
LT_W_COL            EQU LT_VARS+$0A0
LT_W_BRIGHT         EQU LT_VARS+$0A8
LT_W_PERIOD         EQU LT_VARS+$0B0
LT_W_HOLD           EQU LT_VARS+$0B8

; Where each LED's animation has got to.  LT_A_MODE and LT_A_PERIOD hold the
; mode and the period the state was built for, so a mode or a period the
; device reports differently
; restarts it rather than carrying a stale step across.
;
; LT_A_LEFT is a word each.  A blink at the longest period the protocol carries
; is over six hundred fields to a step, which a byte does not hold.
LT_A_STEP           EQU LT_VARS+$0C0
LT_A_LEFT           EQU LT_VARS+$0C8    ; fields until the next step
LT_A_MODE           EQU LT_VARS+$0D8
LT_A_PERIOD         EQU LT_VARS+$0E0

; The last GET_LED_MODE_INFO reply, for the selected LED and the mode the
; next command will carry.  A device that answers and says no leaves both
; clear, which reads the same as a mode that takes no period — and that is what
; a refusal means here.
LT_MODE_FLAGS       EQU LT_VARS+$0E8
LT_MODE_MIN         EQU LT_VARS+$0E9    ; 100ms units

LT_TICK_ARM         EQU LT_VARS+$0EB    ; the beam is below the tick line
LT_SCAN_LEFT        EQU LT_VARS+$0EC    ; word, fields until the next scan
LT_PARADE           EQU LT_VARS+$0EE    ; 1 while the parade runs
LT_P_LED            EQU LT_VARS+$0EF    ; where the parade has got to
LT_P_MODE           EQU LT_VARS+$0F0
LT_P_LEFT           EQU LT_VARS+$0F2    ; word, fields left on this step

; The seven bytes of the last SET_LED, as they were staged to go on the wire.
; A pipe write reuses the library's scratch, and the log goes out before the
; read back is compared, so the comparison reads these instead.
LT_SENT             EQU LT_VARS+$0F8
SENT_MODE           EQU 0
SENT_RED            EQU 1
SENT_GREEN          EQU 2
SENT_BLUE           EQU 3
SENT_BRIGHT         EQU 4
SENT_PERIOD         EQU 5
SENT_HOLD           EQU 6

; Which screen is up, and where the copper list the lamps are drawn out of is
; being built.
LT_SCREEN           EQU LT_VARS+$100
LT_COP_PTR          EQU LT_VARS+$102    ; long, the next word to append

; Where in the copper list each LED's four colour words sit, or zero where
; this screen draws no lamp for it.  The animation writes through these, so a
; step costs four words rather than a redraw.
LT_LAMP_COP         EQU LT_VARS+$108    ; six longs

; The lamp lamp_paint is about to draw.  Its pens run centre, body, edge,
; glow.
LT_LAMP_CX          EQU LT_VARS+$120    ; word
LT_LAMP_CY          EQU LT_VARS+$122    ; word
LT_LAMP_A           EQU LT_VARS+$124    ; word
LT_LAMP_B           EQU LT_VARS+$126    ; word
LT_LAMP_PENS        EQU LT_VARS+$128    ; four bytes

; The terms lamp_paint works out for itself before it starts.  LT_LAMP_OFF is
; how far up and to the left the lit centre sits.
LT_A2               EQU LT_VARS+$12C    ; word
LT_B2               EQU LT_VARS+$12E    ; word
LT_THRESH           EQU LT_VARS+$130    ; five longs
LT_LAMP_XREACH      EQU LT_VARS+$144    ; word, how far the glow goes across
LT_LAMP_YREACH      EQU LT_VARS+$146    ; word, and down
LT_LAMP_OFF         EQU LT_VARS+$148    ; word
LT_LAMP_DYT         EQU LT_VARS+$14A    ; word, this row's term
LT_LAMP_DYTC        EQU LT_VARS+$14C    ; word, and the lit centre's
LT_LAMP_X0          EQU LT_VARS+$14E    ; word, the footprint's first column
LT_LAMP_X1          EQU LT_VARS+$150    ; word, and its last

; One term of the ellipse per column of the lamp being drawn.  Working it out
; once a lamp rather than once a pixel is what keeps a repaint quick.
LT_DX_TERM          EQU LT_VARS+$160    ; 48 words
LT_DX_MID           EQU LT_DX_TERM+48   ; dx = 0 sits in the middle

; The screen as it already stands.  A scan finds nothing changed most of the
; time, and a table that clears and redraws anyway flickers every field.
;
; LT_SHOWN is ROW_FIELDS bytes of the device's report for each LED and then
; whether it was the row the keys land on.  LT_SHOWN_MODES is the same for the
; modes row.  LT_REDRAW is set where the bitmap was cleared and nothing on it
; can be trusted.
ROW_FIELDS          EQU 7
ROW_SHOWN_SZ        EQU 8
LT_SHOWN            EQU LT_VARS+$1C0    ; six of ROW_SHOWN_SZ
LT_SHOWN_MODES      EQU LT_VARS+$1F0    ; the LED, its mode and the modes it has
LT_REDRAW           EQU LT_VARS+$1F4

; The bitmap the copper is showing, and whether the other one has anything on
; it the shown one has not.  Zero in LT_FRONT means the tester is still drawing
; straight to the screen, which is where it starts and where err_halt draws.
LT_DIRTY            EQU LT_VARS+$1F5
LT_COP_DUE          EQU LT_VARS+$1F6    ; the copper list is for the other screen
LT_FRONT            EQU LT_VARS+$1F8    ; long

; Where layout_entries put this screen's entries.  LT_TEXT_OFF is how far into
; a band the text starts, so a row of text sits level with the lamp beside it.
LT_PITCH            EQU LT_VARS+$200    ; character rows an entry gets
LT_FIRST            EQU LT_VARS+$201    ; the first entry's own first row
LT_TEXT_OFF         EQU LT_VARS+$202
LT_LAMP_HALF        EQU LT_VARS+$203    ; the half-height a band of this pitch
                                        ; has room for
LT_PICK_CAP         EQU LT_VARS+$204    ; the colour page's caption row

; Which field the last read back differed on and what the device gave for it.
LT_READ_FIELD       EQU LT_VARS+$208
LT_READ_GOT         EQU LT_VARS+$209

LT_END              EQU LT_VARS+$210
