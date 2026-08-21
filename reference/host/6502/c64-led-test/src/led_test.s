; led_test.s — the main loop, the keys that drive it, and what each one does
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Entered from BASIC by SYS 2061 and returns to BASIC by rts.  Taking the
; machine over and handing it back is c64_app.s's job, and scanning the matrix
; is c64_keys.s's — this file supplies the table of keys it wants and says what
; each one does.
;
; Every key that changes something sends one SET_LED, reads every LED back and
; compares.  That comparison is the only check available: nothing the host
; reads proves an LED lit, because GET_LED_INFO answers out of the same place
; SET_LED wrote to.  What is left is whether the device agrees with itself, and
; whether a person or a camera looking at the board sees what the screen says.

    .include "led_defs.s"

.import c64_app_enter
.import c64_app_leave
.import c64_keys_scan
.import c64_keys_wait_none
.import c64_keys_wait_any
.import sess_open
.import sess_close
.import sess_gone

.import display_init
.import display_keys
.import display_keys_clear
.import display_leds
.import display_leds_fresh
.import display_modes
.import display_read
.import display_note
.import display_colours
.import display_all
.import display_fail

.import charset_build
.import charset_restore
.import ticker_start
.import ticker_stop
.import ticker_poll

.import leds_discover
.import leds_scan
.import leds_set
.import leds_mode_info
.import leds_supports
.import leds_nearest
.import leds_level
.import show_col
.import show_dith
.import leds_count
.import leds_truncated
.import leds_max_period
.import leds_max_hold
.import led_type
.import led_mode
.import led_red
.import led_green
.import led_blue
.import led_bright
.import led_period
.import want_mode
.import want_pal
.import want_bright
.import want_period
.import want_hold
.import mode_takes_period
.import mode_min_period
.import brighter
.import pal_r
.import pal_g
.import pal_b

; ---------------------------------------------------------------------------
; PRG header and BASIC stub
; ---------------------------------------------------------------------------

.segment "LOADADDR"
    .word $0801

; 10 SYS 2061
.segment "BASICSTUB"
    .byte $0B, $08          ; link to the end-of-program marker at $080B
    .byte $0A, $00          ; line number 10
    .byte $9E               ; SYS token
    .byte "2061"
    .byte $00               ; end of line
    .byte $00, $00          ; end of program

; The entry point has a segment of its own so that SYS 2061 lands on it
; whatever order the linker puts the CODE segment's contributors in.
.segment "ENTRY"
    jmp main

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export cur_led
.export pick_index
cur_led:        .res 1
pick_index:     .res 1      ; the palette entry the colour screen is on

armed:          .res 1
read_state:     .res 1
key_held:       .res 1

; Where each LED is in the three stepping lists.  The value that goes on the
; wire is the list entry, so nothing here has to remember a number the keyboard
; would be a bad way to type.
bright_idx:     .res MAX_LEDS
period_idx:     .res MAX_LEDS
hold_idx:       .res MAX_LEDS

parade_mode:    .res 1
pending_mode:   .res 1

; Where each LED's animation has got to.  anim_mode and anim_period are what
; the state was built for, so a mode or a period the device reports differently
; restarts it rather than carrying a stale step across.
anim_mode:      .res MAX_LEDS
anim_period:    .res MAX_LEDS
anim_step:      .res MAX_LEDS
anim_left_lo:   .res MAX_LEDS
anim_left_hi:   .res MAX_LEDS
anim_ticks:     .res 1          ; 10ms units since the last pass
paint_led:      .res 1
paint_level:    .res 1
pause_left:     .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; main — SYS 2061 arrives here with interrupts on and the kernal live.
; ---------------------------------------------------------------------------

main:
    jsr c64_app_enter
    jsr charset_build
    jsr ticker_start

    lda #0
    sta armed
    sta cur_led
    sta pick_index
    sta read_state

    jsr display_init
    jsr display_keys

    ; The session first, then what this program wants from it.  Both refuse the
    ; same way: carry set with the reason in A.
    jsr sess_open
    bcs @refused
    jsr leds_discover
    bcc @armed
@refused:
    jsr display_fail            ; the reason is already in A
    jmp wait_quit
@armed:
    lda #1
    sta armed
    jsr anim_reset
    jsr init_wants
    jsr redraw
    lda leds_truncated
    beq @script
    lda #NOTE_TRUNCATED         ; after the redraw, which blanks the note row
    jsr display_note
@script:
    jsr script
    jmp loop

; ---------------------------------------------------------------------------
; init_wants — starts every LED where the device already has it, so the first
; key changes one thing rather than everything.
;
; SET_LED carries every field at once, so there is no way to change a mode and
; leave a brightness alone.  What this can do is start from the device's own
; answers: the mode it reports, and the palette entry nearest the colour it
; reports.  Brightness, period and hold start at the entry that leaves each of
; them to the device.
; ---------------------------------------------------------------------------

init_wants:
    ldx #0
@each:
    lda led_mode, x
    sta want_mode, x
    txa
    pha                         ; leds_nearest wants the LED in A, and eats X
    jsr leds_nearest
    tay
    pla
    tax
    tya
    sta want_pal, x
    lda #0
    sta bright_idx, x
    sta period_idx, x
    sta hold_idx, x
    jsr apply_steps
    inx
    cpx leds_count
    bne @each
    rts

; ---------------------------------------------------------------------------
; apply_steps — X = LED.  Copies the three stepping lists into the want_
; tables.  Clobbers A, Y.
; ---------------------------------------------------------------------------

apply_steps:
    ldy bright_idx, x
    lda bright_steps, y
    sta want_bright, x
    ldy period_idx, x
    lda period_steps, y
    sta want_period, x
    ldy hold_idx, x
    lda hold_steps, y
    sta want_hold, x
    rts

; ---------------------------------------------------------------------------
; loop — the program's resting state.  Rescans, redraws and takes one key.
;
; The scan is the refresh: one GET_LED_INFO per LED, so the picture is as live
; as the device is fast.  An LED something else on the device changed shows up
; here without this program having asked.
; ---------------------------------------------------------------------------

loop:
    jsr leds_scan
    bcs lost
    jsr ticker_poll
    sta anim_ticks
    jsr anim_update
    jsr display_leds

    jsr c64_keys_scan
    cmp #KEY_NONE_CODE
    beq loop
    sta key_held
    jsr c64_keys_wait_none
    lda key_held
    jsr dispatch
    jmp loop

lost:
    lda #NOTE_LOST
    jsr display_note
    jmp wait_quit

; ---------------------------------------------------------------------------
; dispatch — A = a KEY_ code.
; ---------------------------------------------------------------------------

dispatch:
    cmp #KEY_QUIT
    bne @not_q
    jmp quit
@not_q:
    cmp #KEY_LED_NEXT
    bne @not_ln
    jmp led_next
@not_ln:
    cmp #KEY_LED_PREV
    bne @not_lp
    jmp led_prev
@not_lp:
    cmp #KEY_LED_0
    bne @not_l0
    lda #0
    jmp led_pick
@not_l0:
    cmp #KEY_LED_1
    bne @not_l1
    lda #1
    jmp led_pick
@not_l1:
    cmp #KEY_COL_NEXT
    bne @not_cn
    jmp colour_next
@not_cn:
    cmp #KEY_COL_PREV
    bne @not_cp
    jmp colour_prev
@not_cp:
    cmp #KEY_MODE_0
    bcc @not_mode
    cmp #KEY_MODE_5 + 1
    bcs @not_mode
    sec
    sbc #KEY_MODE_0
    jmp set_mode
@not_mode:
    cmp #KEY_COLOURS
    bne @not_col
    jmp show_colours
@not_col:
    cmp #KEY_BRIGHT
    bne @not_br
    jmp step_bright
@not_br:
    cmp #KEY_PERIOD
    bne @not_per
    jmp step_period
@not_per:
    cmp #KEY_HOLD
    bne @not_hold
    jmp step_hold
@not_hold:
    cmp #KEY_PARADE
    bne @not_parade
    jmp parade
@not_parade:
    cmp #KEY_ALL
    bne @not_all
    jmp show_all
@not_all:
    rts

; ---------------------------------------------------------------------------
; redraw — the whole screen below the title.
; ---------------------------------------------------------------------------

redraw:
    jsr anim_update
    jsr display_leds_fresh
    jsr display_modes
    lda read_state
    jsr display_read
    lda #NOTE_BLANK
    jmp display_note

; ---------------------------------------------------------------------------
; Moving between LEDs.  A device with one LED has nowhere to move to.
; ---------------------------------------------------------------------------

led_next:
    inc cur_led
    lda leds_count
    cmp cur_led
    bne @done
    lda #0
    sta cur_led
@done:
    jmp led_changed

led_prev:
    lda cur_led
    bne @down
    lda leds_count
    sta cur_led
@down:
    dec cur_led
    jmp led_changed

; led_pick — A = the LED F1 or F3 named.  A device with fewer LEDs than keys
; ignores the ones that name nothing.
led_pick:
    cmp leds_count
    bcs @out
    sta cur_led
    jmp led_changed
@out:
    rts

led_changed:
    lda #0
    sta read_state
    jmp redraw

; ---------------------------------------------------------------------------
; Stepping the colour in place, which is the fast way round the palette when
; the names are not what is wanted.  The colour screen is the slow way, and
; says what each one is.
; ---------------------------------------------------------------------------

colour_next:
    jsr colour_allowed
    bcs @out
    ldx cur_led
    lda want_pal, x
    clc
    adc #1
    cmp #PICK_COUNT
    bcc @store
    lda #0
@store:
    sta want_pal, x
    jmp send_current
@out:
    rts

colour_prev:
    jsr colour_allowed
    bcs @out
    ldx cur_led
    lda want_pal, x
    bne @down
    lda #PICK_COUNT
@down:
    sec
    sbc #1
    sta want_pal, x
    jmp send_current
@out:
    rts

; colour_allowed — carry clear if this LED's colour is the host's to set.
; Says so on the note row if it is not.  Clobbers A, X.
colour_allowed:
    ldx cur_led
    lda led_type, x
    cmp #RBCP_LED_TYPE_RGB
    beq @yes
    lda #NOTE_NO_COLOUR
    jsr display_note
    sec
    rts
@yes:
    clc
    rts

; ---------------------------------------------------------------------------
; set_mode — A = mode.  A mode the LED does not report is refused here rather
; than sent, because the device reported which ones it has and this is what
; that report is for.
; ---------------------------------------------------------------------------

set_mode:
    sta pending_mode
    tax
    lda cur_led
    jsr leds_supports
    bcs @have
    lda #NOTE_UNSUPPORTED
    jmp display_note
@have:
    ldx cur_led
    lda pending_mode
    sta want_mode, x
    jmp send_current

; ---------------------------------------------------------------------------
; The three stepping keys.  Each walks a short list and sends the result: a C64
; keyboard is a bad way to type a number, and a bad number is worth nothing
; here — what these are for is putting the LED somewhere a camera can see.
; ---------------------------------------------------------------------------

step_bright:
    ldx cur_led
    lda bright_idx, x
    clc
    adc #1
    cmp #BRIGHT_STEPS
    bcc @store
    lda #0
@store:
    sta bright_idx, x
    jsr apply_steps
    jmp send_current

step_hold:
    lda leds_max_hold
    bne @have
    lda #NOTE_NO_HOLD
    jmp display_note
@have:
    ldx cur_led
@step:
    lda hold_idx, x
    clc
    adc #1
    cmp #HOLD_STEPS
    bcc @store
    lda #0
@store:
    sta hold_idx, x
    tay
    lda hold_steps, y
    beq @ok                     ; nothing to check against: until changed
    cmp leds_max_hold
    beq @ok
    bcs @step                   ; past what this device times, so try the next
@ok:
    jsr apply_steps
    jmp send_current

; step_period — the range depends on the mode as well as the device, so this
; asks before it steps, and skips a value the mode would refuse.
step_period:
    ldx cur_led
    lda want_mode, x
    tax
    lda cur_led
    jsr leds_mode_info
    lda mode_takes_period
    bne @have
    lda #NOTE_NO_PERIOD
    jmp display_note
@have:
    ldx cur_led
@step:
    lda period_idx, x
    clc
    adc #1
    cmp #PERIOD_STEPS
    bcc @store
    lda #0
@store:
    sta period_idx, x
    tay
    lda period_steps, y
    beq @ok                     ; nothing to check against: the mode's default
    cmp mode_min_period
    bcc @step
    cmp leds_max_period
    beq @ok
    bcs @step
@ok:
    jsr apply_steps
    jmp send_current

; ---------------------------------------------------------------------------
; send_current — one SET_LED for the cursor LED, then a read back of every LED
; and a comparison against what was asked for.
; ---------------------------------------------------------------------------

send_current:
    lda #NOTE_BLANK
    jsr display_note
    lda cur_led
    jsr leds_set
    bcs @refused
    jsr leds_scan
    bcs @lost
    jsr check_read
    jmp @show
@refused:
    lda #READ_REFUSED
    sta read_state
    jsr leds_scan
@show:
    jsr anim_restart
    jsr anim_update
    jsr display_leds
    jsr display_modes
    lda read_state
    jmp display_read
@lost:
    lda #NOTE_LOST
    jsr display_note
    jmp wait_quit

; ---------------------------------------------------------------------------
; check_read — compares what the device now reports for the cursor LED against
; what it was given, field by field, and only for the fields the host named.
;
; A brightness of zero, a period of zero and a colour of three zeroes all mean
; the device chooses, so there is nothing to compare on those.  A monochrome
; LED's colour is never the host's, so there is nothing to compare there
; either.  What is left is what the device promised to do.
; ---------------------------------------------------------------------------

check_read:
    ldx cur_led
    lda want_mode, x
    cmp led_mode, x
    bne @differs

    lda want_bright, x
    beq @bright_ok
    cmp led_bright, x
    bne @differs
@bright_ok:

    lda want_period, x
    beq @period_ok
    cmp led_period, x
    bne @differs
@period_ok:

    lda led_type, x
    cmp #RBCP_LED_TYPE_RGB
    bne @match
    ldy want_pal, x
    beq @match
    dey
    lda pal_r, y
    cmp led_red, x
    bne @differs
    lda pal_g, y
    cmp led_green, x
    bne @differs
    lda pal_b, y
    cmp led_blue, x
    bne @differs
@match:
    lda #READ_MATCH
    sta read_state
    rts
@differs:
    lda #READ_DIFFERS
    sta read_state
    rts

; ---------------------------------------------------------------------------
; show_colours — the colour screen.  RETURN sets what the cursor is on, Q backs
; out, and nothing is sent until RETURN.
; ---------------------------------------------------------------------------

show_colours:
    jsr colour_allowed
    bcc @have
    rts
@have:
    ldx cur_led
    lda want_pal, x
    sta pick_index
    jsr display_colours

@wait:
    jsr c64_keys_scan
    cmp #KEY_NONE_CODE
    beq @wait
    sta key_held
    jsr c64_keys_wait_none
    lda key_held

    cmp #KEY_RETURN_CODE
    bne @not_return
    ldx cur_led
    lda pick_index
    sta want_pal, x
    jsr back_from_screen
    jmp send_current
@not_return:
    cmp #KEY_QUIT
    beq @back
    cmp #KEY_LED_NEXT
    beq @next
    cmp #KEY_COL_NEXT
    beq @next
    cmp #KEY_LED_PREV
    beq @prev
    cmp #KEY_COL_PREV
    beq @prev
    jmp @wait
@next:
    lda pick_index
    clc
    adc #1
    cmp #PICK_COUNT
    bcc @set
    lda #0
    beq @set                    ; always taken
@prev:
    lda pick_index
    bne @down
    lda #PICK_COUNT
@down:
    sec
    sbc #1
@set:
    sta pick_index
    jsr display_colours
    jmp @wait
@back:
    jsr back_from_screen
    rts

; ---------------------------------------------------------------------------
; show_all — every byte the device reported, until any key.
; ---------------------------------------------------------------------------

show_all:
    jsr display_all
    jsr c64_keys_wait_any
    ; fall through

back_from_screen:
    jsr display_init
    jsr display_keys
    jmp redraw

; ---------------------------------------------------------------------------
; parade — steps every mode this LED has, holding each long enough to see and
; naming it inside the disc as it goes.
;
; This is the one thing here that is about the world outside the device.
; Nothing the host reads can tell a lit LED from a dead one, so the witness has
; to be an eye or a camera, and what an eye needs is one continuous thing to
; watch with the answer written beside it.
; ---------------------------------------------------------------------------

parade:
    jsr display_keys_clear
    lda #NOTE_PARADE
    jsr display_note

    lda #0
    sta parade_mode
@step:
    ldx parade_mode
    lda cur_led
    jsr leds_supports
    bcc @next
    ldx cur_led
    lda parade_mode
    sta want_mode, x
    jsr send_current
    jsr pause
    bcs @stopped
@next:
    inc parade_mode
    lda parade_mode
    cmp #6
    bne @step
@stopped:
    jsr display_keys
    lda #NOTE_BLANK
    jsr display_note
    rts

; ---------------------------------------------------------------------------
; The animation
;
; The device tells this program what mode each LED is in and how long one
; repetition takes.  That is enough to draw the same thing on screen, so it
; does — a blink blinks, a breathe fades, a cycle turns.  The two clocks are
; not synchronised and cannot be, and that is fine: this is not a measurement,
; it is a C64 and a board doing the same thing at the same time.
;
; What comes out is show_col and show_dith for each LED, which is all display.s
; draws from.
; ---------------------------------------------------------------------------

; anim_reset — forgets every LED's animation, so the next update restarts it.
; Clobbers A, X.
anim_reset:
    ldx #MAX_LEDS - 1
@each:
    lda #$FF
    sta anim_mode, x
    sta anim_period, x
    dex
    bpl @each
    rts

; anim_restart — the cursor LED only, so a key that changes a mode is seen at
; the start of that mode rather than part way through the old one.
anim_restart:
    ldx cur_led
    lda #$FF
    sta anim_mode, x
    rts

; ---------------------------------------------------------------------------
; anim_update — advances every LED by anim_ticks and works out how each one is
; to be drawn.  Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

anim_update:
    ldx #0
@each:
    jsr anim_led
    inx
    cpx leds_count
    bne @each
    rts

; anim_led — X = LED.  X survives.
anim_led:
    lda led_mode, x
    cmp anim_mode, x
    bne @restart
    lda led_period, x
    cmp anim_period, x
    beq @running
@restart:
    lda led_mode, x
    sta anim_mode, x
    lda led_period, x
    sta anim_period, x
    lda #0
    sta anim_step, x
    jsr anim_reload
    jmp anim_paint

@running:
    lda anim_ticks
    beq anim_paint
    sec
    lda anim_left_lo, x
    sbc anim_ticks
    sta anim_left_lo, x
    lda anim_left_hi, x
    sbc #0
    sta anim_left_hi, x
    bcs anim_paint              ; the step still has time left in it

    ; One step a pass, however long the pass took.  A period shorter than a
    ; pass would want more, but the screen cannot be drawn faster than it is
    ; drawn, so there would be nothing to see for the extra steps.
    inc anim_step, x
    lda anim_step, x
    jsr anim_steps
    sta ZP_APP0
    lda anim_step, x
    cmp ZP_APP0
    bcc @reload
    lda #0
    sta anim_step, x
@reload:
    jsr anim_reload
    ; fall through

; ---------------------------------------------------------------------------
; anim_paint — X = LED.  Works out the colour and the halftone the disc is to
; be drawn in, which is all display.s reads.  X survives.
; ---------------------------------------------------------------------------

anim_paint:
    lda led_mode, x
    cmp #RBCP_LED_OFF
    bne @not_off
    lda #LVL_DARK
    jmp set_level
@not_off:
    cmp #RBCP_LED_BLINK
    bne @not_blink
    ldy anim_step, x
    beq lit_level
    lda #LVL_BLACK
    jmp set_level
@not_blink:
    cmp #RBCP_LED_BREATHE
    bne @not_breathe
    ldy anim_step, x
    lda breathe_tab, y
    jmp set_level
@not_breathe:
    cmp #RBCP_LED_BEACON
    bne @not_beacon
    ldy anim_step, x
    lda beacon_tab, y
    jmp set_level
@not_beacon:
    cmp #RBCP_LED_CYCLE
    bne lit_level
    ldy anim_step, x
    lda hue_tab, y
    sta show_col, x
    lda #DITH_SOLID
    sta show_dith, x
    rts

; lit_level — X = LED.  The brightness the device reports, as a level.
lit_level:
    txa
    pha
    jsr leds_level              ; wants the LED in A, and eats X
    tay
    pla
    tax
    tya
    ; fall through

; ---------------------------------------------------------------------------
; set_level — A = LVL_, X = LED.  X survives.
;
; Dark is the LED's body rather than a hole in the screen: an unlit LED is a
; grey lens, and drawing it that way keeps the disc where it was.
; ---------------------------------------------------------------------------

set_level:
    sta paint_level
    stx paint_led
    cmp #LVL_BLACK
    bne @not_black
    lda #COL_BLACK              ; nothing there, on a black screen
    sta show_col, x
    lda #DITH_SOLID
    sta show_dith, x
    rts
@not_black:
    cmp #LVL_DARK
    bne @lit
    lda #COL_DARK_GREY
    sta show_col, x
    lda #DITH_SOLID
    sta show_dith, x
    rts
@lit:
    lda paint_led
    jsr leds_nearest            ; a palette entry, which is also its colour
    bne @have
    lda #COL_MED_GREY           ; the device states no colour
@have:
    tay
    lda paint_level
    cmp #LVL_BRIGHT
    bne @plain
    lda brighter, y
    tay                         ; full brightness borrows the brighter partner
    lda #DITH_SOLID
    jmp @store
@plain:
    ; The three lit levels below full sit in the same order as the three
    ; halftones, so one subtraction turns a level into a character table.
    .assert DITH_QUARTER = 0 && DITH_HALF = 1 && DITH_SOLID = 2, error, "halftones out of order"
    sec
    sbc #LVL_QTR
@store:
    ldx paint_led
    sta show_dith, x
    tya
    sta show_col, x
    rts

; ---------------------------------------------------------------------------
; anim_steps — X = LED.  How many steps its mode has.  Clobbers A, Y.
; ---------------------------------------------------------------------------

anim_steps:
    ldy led_mode, x
    cpy #6
    bcs @one
    lda step_tab, y
    rts
@one:
    lda #1                      ; a mode this program does not know does not move
    rts

; ---------------------------------------------------------------------------
; anim_reload — X = LED.  How long its next step lasts, in 10ms units.
;
; A step is the period divided by the number of steps, and every step count is
; a power of two so the divide is a shift.  Beacon times itself: it is a
; pattern to be picked out by eye rather than one repetition of anything.
; Clobbers A, Y and ZP_APP0 to ZP_APP4.
; ---------------------------------------------------------------------------

anim_reload:
    lda led_mode, x
    cmp #RBCP_LED_BEACON
    bne @timed
    lda #ANIM_BEACON_TICKS
    sta anim_left_lo, x
    lda #0
    sta anim_left_hi, x
    rts
@timed:
    jsr anim_steps
    sta ZP_APP0
    cmp #2
    bcs @moving
    lda #$FF                    ; one step, so nothing ever ends it
    sta anim_left_lo, x
    sta anim_left_hi, x
    rts
@moving:
    lda led_period, x
    bne @have
    lda #ANIM_DEFAULT_PERIOD
@have:
    jsr times_ten               ; the period in 10ms units, in ZP_APP1 and 2
    lda ZP_APP0
    cmp #2
    beq @by_two
    lsr ZP_APP2
    ror ZP_APP1
    lsr ZP_APP2
    ror ZP_APP1
@by_two:
    lsr ZP_APP2
    ror ZP_APP1
    lda ZP_APP1
    ora ZP_APP2
    bne @store
    lda #1                      ; never nothing, or every pass would step
    sta ZP_APP1
@store:
    lda ZP_APP1
    sta anim_left_lo, x
    lda ZP_APP2
    sta anim_left_hi, x
    rts

; times_ten — A, in the protocol's 100ms units, into ZP_APP1 and ZP_APP2 in
; 10ms units.  Ten is eight plus two.  Clobbers A, ZP_APP1 to ZP_APP4.
times_ten:
    sta ZP_APP1
    lda #0
    sta ZP_APP2
    asl ZP_APP1
    rol ZP_APP2                 ; twice
    lda ZP_APP1
    sta ZP_APP3
    lda ZP_APP2
    sta ZP_APP4
    asl ZP_APP1
    rol ZP_APP2
    asl ZP_APP1
    rol ZP_APP2                 ; eight times
    lda ZP_APP1
    clc
    adc ZP_APP3
    sta ZP_APP1
    lda ZP_APP2
    adc ZP_APP4
    sta ZP_APP2
    rts

; ---------------------------------------------------------------------------
; pause — about two seconds, or until a key is pressed, which is reported by
; carry set.  Rough is fine: nothing measures it, and a step that is a little
; off two seconds looks exactly like one that is not.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

pause:
    lda #0
    sta pause_left
@loop:
    jsr ticker_poll
    sta anim_ticks
    clc
    adc pause_left
    bcs @done                   ; past two seconds by a long way
    sta pause_left
    cmp #200
    bcs @done
    jsr anim_update
    jsr display_leds
    jsr c64_keys_scan
    cmp #KEY_NONE_CODE
    beq @loop
    jsr c64_keys_wait_none
    sec
    rts
@done:
    clc
    rts

; ---------------------------------------------------------------------------
; wait_quit — the resting state when there is nothing to show.  Only Q leaves.
; ---------------------------------------------------------------------------

wait_quit:
    jsr c64_keys_scan
    cmp #KEY_QUIT
    bne wait_quit
    ; fall through

quit:
    lda armed
    beq @leave
    jsr sess_close
@leave:
    jsr ticker_stop
    jsr charset_restore
    jmp c64_app_leave

; ---------------------------------------------------------------------------
; script — nothing at all in a real build.  In a demo build it puts the
; program into one named state at startup, by calling the same dispatch the
; keyboard calls, so that a screen can be captured under an emulator without
; anything to press the keys.
; ---------------------------------------------------------------------------

.ifndef SCRIPT
SCRIPT = 0
.endif

script:
.if SCRIPT = 1                          ; an RGB LED lit, in a colour it was given
    lda #KEY_LED_NEXT
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_MODE_1
    jsr dispatch
.endif
.if SCRIPT = 2                          ; breathing, at half brightness
    lda #KEY_LED_NEXT
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_MODE_3
    jsr dispatch
    lda #KEY_BRIGHT
    jsr dispatch
    lda #KEY_BRIGHT
    jsr dispatch
    lda #KEY_PERIOD
    jsr dispatch
.endif
.if SCRIPT = 3                          ; the colour screen
    lda #KEY_LED_NEXT
    jsr dispatch
    lda #KEY_COLOURS
    jsr dispatch
    jmp wait_quit
.endif
.if SCRIPT = 4                          ; every byte the device reported
    jsr display_all
    jmp wait_quit
.endif
.if SCRIPT = 5                          ; a mode this LED does not have
    lda #KEY_MODE_4
    jsr dispatch
    jmp wait_quit
.endif
.if SCRIPT = 6                          ; a parade, run to the end
    lda #KEY_LED_NEXT
    jsr dispatch
    lda #KEY_PARADE
    jsr dispatch
.endif
.if SCRIPT = 7                          ; half brightness on the first LED
    lda #KEY_MODE_1
    jsr dispatch
    lda #KEY_BRIGHT
    jsr dispatch
    lda #KEY_BRIGHT
    jsr dispatch
.endif
.if SCRIPT = 8                          ; a hold on a device that times none
    lda #KEY_HOLD
    jsr dispatch
    jmp wait_quit
.endif
.if SCRIPT = 9                          ; a beacon, which is the fastest thing
    lda #KEY_LED_NEXT                   ; here to move
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_COL_NEXT
    jsr dispatch
    lda #KEY_MODE_5
    jsr dispatch
.endif
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; The three stepping lists.  Entry zero of each is the one that leaves the
; choice to the device: no brightness named, the mode's own period, and a mode
; that stays until something changes it.
; How many steps each mode is drawn in, and what those steps look like.
step_tab:
    .byte 1, 1, ANIM_STEPS_BLINK, ANIM_STEPS_BREATHE, ANIM_STEPS_CYCLE, ANIM_STEPS_BEACON

; Breathe fades between dark and lit and back, which is what the protocol says
; it does.
breathe_tab:
    .byte LVL_BLACK, LVL_QTR, LVL_HALF, LVL_FULL
    .byte LVL_BRIGHT, LVL_FULL, LVL_HALF, LVL_QTR

; Beacon is two quick flashes and a wait, which is what picks a board out of a
; row of them.
beacon_tab:
    .byte LVL_BRIGHT, LVL_BLACK, LVL_BRIGHT, LVL_BLACK
    .byte LVL_BLACK, LVL_BLACK, LVL_BLACK, LVL_BLACK

; Cycle turns through the hues the C64 has, in the order they sit on a wheel.
hue_tab:
    .byte COL_RED, COL_ORANGE, COL_YELLOW, COL_GREEN
    .byte COL_CYAN, COL_LIGHT_BLUE, COL_PURPLE, COL_LIGHT_RED

bright_steps:   .byte 0, 25, 50, 75, 100
period_steps:   .byte 0, 5, 10, 20, 50      ; 100ms units, so up to five seconds
hold_steps:     .byte 0, 5, 10, 20, 50

; The keys this program uses, in the form c64_keys.s walks: column mask, row
; bit, code, and the code shift gives instead.  Shift reverses the two cursor
; keys, which is what a C64 does with them everywhere else.
;
; A column mask of zero ends the table.

.export app_key_table
app_key_table:
    .byte %11111110, %00000100, KEY_LED_NEXT,  KEY_LED_PREV     ; CRSR right
    .byte %11111110, %10000000, KEY_COL_NEXT,  KEY_COL_PREV     ; CRSR down
    .byte %11111110, %00000010, KEY_RETURN_CODE, KEY_RETURN_CODE ; RETURN
    .byte %11111110, %00010000, KEY_LED_0,     KEY_LED_0        ; F1
    .byte %11111110, %00100000, KEY_LED_1,     KEY_LED_1        ; F3
    .byte %01111111, %00000001, KEY_MODE_1,    KEY_MODE_1       ; 1
    .byte %01111111, %00001000, KEY_MODE_2,    KEY_MODE_2       ; 2
    .byte %11111101, %00000001, KEY_MODE_3,    KEY_MODE_3       ; 3
    .byte %11111101, %00001000, KEY_MODE_4,    KEY_MODE_4       ; 4
    .byte %11111011, %00000001, KEY_MODE_5,    KEY_MODE_5       ; 5
    .byte %11101111, %00001000, KEY_MODE_0,    KEY_MODE_0       ; 0
    .byte %11111101, %00000100, KEY_ALL,       KEY_ALL          ; A
    .byte %11110111, %00010000, KEY_BRIGHT,    KEY_BRIGHT       ; B
    .byte %11111011, %00010000, KEY_COLOURS,   KEY_COLOURS      ; C
    .byte %11110111, %00100000, KEY_HOLD,      KEY_HOLD         ; H
    .byte %11011111, %00000010, KEY_PERIOD,    KEY_PERIOD       ; P
    .byte %01111111, %00010000, KEY_PARADE,    KEY_PARADE       ; SPACE
    .byte %01111111, %01000000, KEY_QUIT,      KEY_QUIT         ; Q
    .byte 0
