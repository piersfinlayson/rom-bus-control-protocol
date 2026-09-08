; auxio.s — the main loop, the keys that drive it, and what each one does
;
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The machine's reset entry copies this into RAM and jumps to auxio_run, which
; does not return.  The device is serving the image these instructions were
; copied out of, so nothing here may be fetched from it: see the machine's own
; plat.s for the copy, and its linker configuration for where the command page
; and the back channel sit inside the image.
;
; Where a display steals cycles from the processor, every exchange with the
; device is bracketed by plat_dark and plat_light.  A pair covers a whole
; operation — the session opening, a drive, a blink — not a command, so the
; screen changes state once for something you pressed rather than once per
; command.

    .include "auxio_defs.s"

.import sess_open
.import plat_init
.import plat_key
.import plat_dark
.import plat_light

.import display_init
.import display_keys
.import display_frame
.import display_keys_clear
.import display_group
.import display_rings
.import display_rings_fresh
.import display_note
.import display_fail
.import display_all
.import display_all_fresh
.import display_reset
.import reset_pin
.import reset_flash

.import pins_discover
.import pins_scan
.import pins_scan_all
.import pins_set
.import pins_group_count
.import pins_group_drv
.import pin_state
.import pins_drv_at
.import pins_tier
.import tier_perrow
.import pins_hold
.import pins_after
.import pins_switch_exit
.import sess_load
.import sess_read_flash_name
.import sess_flash_count
.import sess_flash_types
.import sess_can_switch

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export cur_group
.export cur_slot
.export cur_page
cur_group:      .res 1
cur_slot:       .res 1      ; index into the current group's drivable list
cur_page:       .res 1      ; a group, or the all-pins page after the last one

scan_lo:        .res 1      ; passes left before the group is reread
scan_hi:        .res 1
blink_phase:    .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

BLINK_HOLD = 50             ; 10ms units, so half a second each way

; ---------------------------------------------------------------------------
; auxio_run — the machine's reset entry jumps here once the code is in RAM,
; with interrupts masked and the display already up.  It does not return.
; ---------------------------------------------------------------------------

.export auxio_run
auxio_run:
    jsr plat_init

    lda #0
    sta cur_group
    sta cur_page
    sta cur_slot
    sta blink_phase
    sta pins_hold
    lda #RBCP_AUX_RELEASE
    sta pins_after
    lda #$FF
    sta reset_flash

    jsr display_init

    ; The session first, then what this program wants from it.  Both refuse
    ; the same way: carry set with the reason in A.  One dark window covers
    ; both, because between them there is nothing to look at.
    jsr plat_dark
    jsr sess_open
    bcs @refused
    jsr pins_discover
@refused:
    jsr plat_light
    bcc @armed
    jsr display_fail            ; the reason is already in A
    jmp halt
@armed:
    jsr redraw
    jmp loop

; ---------------------------------------------------------------------------
; loop — the program's resting state.  Takes a key, and every SCAN_TICKS passes
; without one rereads the current group.
;
; The scan is the refresh: one GET_AUX_PIN_INFO per pin, so a group of thirty
; costs thirty commands.  On a machine whose display has to go off for that,
; doing it every pass would leave the screen dark almost always, which is why
; SCAN_TICKS is what makes that bearable, and the machine sets it.  Anything
; pressed rereads at once, so the delay is only ever how long it takes to
; notice a pin that moved on its own.
; ---------------------------------------------------------------------------

loop:
    jsr plat_key
    cmp #KEY_NONE_CODE
    bne @key

    lda scan_lo
    bne @dec_lo
    dec scan_hi
@dec_lo:
    dec scan_lo
    lda scan_lo
    ora scan_hi
    bne loop
    jsr rescan
    jmp loop

@key:
    jsr dispatch
    lda #1
    sta scan_lo                 ; whatever was pressed, show the result now
    lda #0
    sta scan_hi
    jmp loop

; ---------------------------------------------------------------------------
; rescan — the current group, and the picture again.  Clobbers A, X, Y and the
; app zero page.
; ---------------------------------------------------------------------------

rescan:
    lda #<SCAN_TICKS
    sta scan_lo
    lda #>SCAN_TICKS
    sta scan_hi
    lda cur_page
    cmp pins_group_count
    bcs @all
    jsr plat_dark
    lda cur_group
    jsr pins_scan
    jsr plat_light
    bcs lost
    jmp display_rings
@all:
    jsr plat_dark
    jsr pins_scan_all
    jsr plat_light
    bcs lost
    jmp display_all

lost:
    lda #NOTE_LOST
    jsr display_note
    jmp halt

; ---------------------------------------------------------------------------
; dispatch — A = a KEY_ code.
; ---------------------------------------------------------------------------

dispatch:
    cmp #KEY_PIN_NEXT
    bne @not_pn
    jmp pin_next
@not_pn:
    cmp #KEY_PIN_PREV
    bne @not_pp
    jmp pin_prev
@not_pp:
    cmp #KEY_ROW_NEXT
    bne @not_rn
    jmp row_next
@not_rn:
    cmp #KEY_ROW_PREV
    bne @not_rp
    jmp row_prev
@not_rp:
    cmp #KEY_LOW_CODE
    bne @not_low
    lda #RBCP_AUX_LOW
    jmp drive
@not_low:
    cmp #KEY_HIGH_CODE
    bne @not_high
    lda #RBCP_AUX_HIGH
    jmp drive
@not_high:
    cmp #KEY_REL_CODE
    bne @not_rel
    lda #RBCP_AUX_RELEASE
    jmp drive
@not_rel:
    cmp #KEY_BLINK_CODE
    bne @not_blink
    jmp blink
@not_blink:
    cmp #KEY_PAGE_NEXT
    bne @not_pgn
    jmp page_next
@not_pgn:
    cmp #KEY_PAGE_PREV
    bne @not_pgp
    jmp page_prev
@not_pgp:
    cmp #KEY_RESET_CODE
    bne @not_reset
    jmp show_reset
@not_reset:
    rts

; ---------------------------------------------------------------------------
; show_reset — the one terminal thing this program can do, behind a screen
; that says so.  RETURN goes, anything else backs out.
;
; The pin is driven low and released afterwards, never driven high: the line
; this is for is one the host pulls up itself, and a 3V3 pin driving into it
; would be the wrong thing on every board that has one.
; ---------------------------------------------------------------------------

show_reset:
    ldx cur_group
    lda pins_group_drv, x
    bne @have
    lda #NOTE_NOT_DRIVABLE
    jmp display_note
@have:
    lda sess_can_switch
    bne @can_switch
    lda #NOTE_NO_SWITCH
    jmp display_note
@can_switch:
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    sta reset_pin

    ; Start on the first image of the served ROM's type.  A device holding
    ; none says so and stays where it is: there is nothing to switch to, and
    ; driving the reset pin without one would stop the machine for good.
    lda #$FF
    sta reset_flash
    jsr next_image
    bcc @have_image
    lda #NOTE_NO_IMAGE
    jmp display_note
@have_image:
    jsr show_reset_screen

@wait:
    jsr plat_key
    cmp #KEY_NONE_CODE
    beq @wait
    cmp #KEY_RETURN_CODE
    beq do_reset
    cmp #KEY_REL_CODE
    beq @out
    cmp #KEY_PIN_NEXT
    bne @wait                   ; a key with no meaning here does nothing
    jsr next_image
    jsr show_reset_screen
    jmp @wait
@out:
    jmp redraw

; ---------------------------------------------------------------------------
; next_image — the next flash slot holding the type of ROM this machine is
; being served, wrapping.  reset_flash of $FF starts the search from zero.
;
; Carry clear with reset_flash set, or carry set if the device holds no slot
; of that type.  The count of slots looked at bounds the search, so a device
; with none does not spin.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

next_image:
    ldy sess_flash_count
    beq @none
    ldx reset_flash
@step:
    inx
    cpx sess_flash_count
    bcc @check
    ldx #0
@check:
    lda sess_flash_types, x
    cmp #CONFIG_ROM_TYPE
    beq @found
    dey
    bne @step
@none:
    sec
    rts
@found:
    stx reset_flash
    clc
    rts

show_reset_screen:
    jsr plat_dark
    lda reset_flash
    jsr sess_read_flash_name
    jsr plat_light
    jmp display_reset

do_reset:
    lda #RESET_HOLD
    sta pins_hold
    lda #RBCP_AUX_RELEASE
    sta pins_after
    jsr plat_dark
    lda reset_flash
    jsr sess_load
    bcc @loaded
    jsr plat_light
    lda #NOTE_REFUSED
    jsr display_note
    jsr display_keys
    jmp redraw
@loaded:
    ldx reset_pin
    ldy cur_group
    lda #RBCP_AUX_LOW
    jsr pins_switch_exit
    jsr plat_light
    lda #NOTE_GONE
    jsr display_note
    jmp halt

; ---------------------------------------------------------------------------
; Cursor movement.  The cursor lives on the drivable list, so a group with
; nothing drivable has nowhere for it to be and the keys do nothing.
;
; Left and right step along that list, which is the order the rings are drawn
; in, so they run along a row and on to the start of the next.  Up and down
; move by a whole row, which is how many rings this page fits across.
; ---------------------------------------------------------------------------

pin_next:
    ldx cur_group
    lda pins_group_drv, x
    beq @out
    inc cur_slot
    cmp cur_slot
    bne @out
    lda #0
    sta cur_slot
@out:
    jmp note_pin

pin_prev:
    ldx cur_group
    lda pins_group_drv, x
    beq @out
    ldx cur_slot
    bne @down
    sta cur_slot
@down:
    dec cur_slot
@out:
    jmp note_pin

; ---------------------------------------------------------------------------
; row_next, row_prev — a whole row up or down the grid, wrapping.  A move that
; would land past the last ring drops to the same column of the first row, and
; one that would go above the first climbs to the lowest row that column has a
; ring on.  So every column is a loop and no key press does nothing.
; Clobbers A, X, Y and ZP_APP0.
; ---------------------------------------------------------------------------

row_next:
    jsr page_width
    beq @out                    ; nothing drivable on this page
    clc
    adc cur_slot
    ldx cur_group
    cmp pins_group_drv, x
    bcc @take
    jsr column                  ; past the end, so back to the top of it
@take:
    sta cur_slot
@out:
    jmp note_pin

row_prev:
    jsr page_width
    beq @out
    sta ZP_APP0
    lda cur_slot
    sec
    sbc ZP_APP0
    bcs @take
    jsr column                  ; above the top, so down to the bottom of it
@sink:
    clc
    adc ZP_APP0
    ldx cur_group
    cmp pins_group_drv, x
    bcc @sink
    sec
    sbc ZP_APP0
@take:
    sta cur_slot
@out:
    jmp note_pin

; ---------------------------------------------------------------------------
; page_width — how many rings this page draws across a row, in A, from the
; tier the current group's drivable count picks.  Zero if it draws none.
; Clobbers A, X.
; ---------------------------------------------------------------------------

page_width:
    ldx cur_group
    lda pins_group_drv, x
    beq @none
    jsr pins_tier
    tax
    lda tier_perrow, x
    rts
@none:
    lda #0
    rts

; ---------------------------------------------------------------------------
; column — A = a slot, ZP_APP0 = the row width.  Returns the column it sits
; in, which is A modulo the width.  Clobbers A.
; ---------------------------------------------------------------------------

column:
    sec
@loop:
    sbc ZP_APP0
    bcs @loop
    adc ZP_APP0
    rts

; ---------------------------------------------------------------------------
; page_next, page_prev — one page per group of pins, and one more after them
; holding every pin at once.  Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

page_next:
    inc cur_page
    lda cur_page
    cmp pins_group_count
    beq @changed                ; the all-pins page sits after the last group
    bcc @changed
    lda #0
    sta cur_page
@changed:
    jmp page_changed

page_prev:
    lda cur_page
    bne @down
    lda pins_group_count
    clc
    adc #1
    sta cur_page
@down:
    dec cur_page
    jmp page_changed

page_changed:
    lda #0
    sta cur_slot
    ; fall through

; ---------------------------------------------------------------------------
; paint_page — the whole screen for the page cur_page names.  Every page is
; drawn from a blank screen, because a page that painted only its own parts
; would leave whatever the last one put in the rows it does not use.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

paint_page:
    jsr display_frame
    lda cur_page
    cmp pins_group_count
    bcs all_page
    sta cur_group
    jsr plat_dark
    lda cur_group
    jsr pins_scan
    jsr plat_light
    bcs @lost
    jsr display_group
    jsr display_rings_fresh
    jsr display_keys
    jmp note_pin
@lost:
    jmp lost

all_page:
    jsr plat_dark
    jsr pins_scan_all
    jsr plat_light
    bcs @lost
    jmp display_all_fresh
@lost:
    jmp lost

; ---------------------------------------------------------------------------
; note_pin — the line under the rings.  A group with nothing drivable says so,
; otherwise nothing is said at all: the rings are the answer and a sentence
; repeating them is noise.
; ---------------------------------------------------------------------------

note_pin:
    ldx cur_group
    lda pins_group_drv, x
    bne @quiet
    lda #NOTE_NO_DRIVE
    jmp display_note
@quiet:
    lda #NOTE_BLANK
    jmp display_note

; ---------------------------------------------------------------------------
; redraw — the whole screen below the title.
; ---------------------------------------------------------------------------

redraw:
    jmp paint_page

; ---------------------------------------------------------------------------
; drive — A = the state to put the cursor pin in.
; ---------------------------------------------------------------------------

drive:
    pha
    ldx cur_group
    lda pins_group_drv, x
    bne @have
    pla
    lda #NOTE_NOT_DRIVABLE
    jmp display_note
@have:
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    tax                         ; pin
    ldy cur_group
    pla                         ; state
    jsr plat_dark
    jsr pins_set
    jsr plat_light
    bcc @ok
    lda #NOTE_REFUSED
    jmp display_note
@ok:
    rts

; ---------------------------------------------------------------------------
; blink — drives the cursor pin high and low until a key is pressed.
;
; Where the device can time a hold this is one command a flash: high, hold,
; then low.  Where it cannot, the two states are sent separately and the wait
; is ours.  Both look the same on screen, which is the point.
; ---------------------------------------------------------------------------

blink:
    ldx cur_group
    lda pins_group_drv, x
    bne @have
    lda #NOTE_NOT_DRIVABLE
    jmp display_note
@have:
    jsr display_keys_clear
    lda #NOTE_BLINKING
    jsr display_note

    jsr plat_dark
@cycle:
    lda blink_phase
    eor #1
    sta blink_phase
    beq @low
    lda #RBCP_AUX_HIGH
    bne @send
@low:
    lda #RBCP_AUX_LOW
@send:
    pha
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    tax
    ldy cur_group
    pla
    jsr pins_set

    lda cur_group
    jsr pins_scan
    jsr plat_light
    jsr display_rings

    jsr half_second

    jsr plat_key
    cmp #KEY_NONE_CODE
    bne @stop
    jsr plat_dark
    jmp @cycle

@stop:
    jsr display_keys
    jmp note_pin

; ---------------------------------------------------------------------------
; half_second — a wait long enough to see, with no timer of its own.  Three
; nested counts, because one byte of them at these clock rates is nearer
; seventy milliseconds, which flickers rather than blinks.  Rough is fine
; beyond that: nothing measures it.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

half_second:
    ldx #2
@outer:
    ldy #128
@mid:
    lda #0
@inner:
    sec
    sbc #1
    bne @inner
    dey
    bne @mid
    dex
    bne @outer
    rts

; ---------------------------------------------------------------------------
; any_key — returns once something has been pressed.  Clobbers A.
; ---------------------------------------------------------------------------

any_key:
    jsr plat_key
    cmp #KEY_NONE_CODE
    beq any_key
    rts

; ---------------------------------------------------------------------------
; halt — the resting state when there is nothing left to do: the device never
; answered, or it has been sent a terminal command and the session is over.
; The screen already says which.  There is nothing to hand the machine back
; to, this image being the ROM it would be handed back through, so the way out
; is the power switch or the reset the R screen offers.
; ---------------------------------------------------------------------------

halt:
    jmp halt
