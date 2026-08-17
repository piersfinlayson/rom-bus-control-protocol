; aux_test.s — entry, exit, interrupts, key scanning and the main loop
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Entered from BASIC by SYS 2061 and returns to BASIC by rts, so the machine
; must be handed back exactly as it was found.  What this file takes and gives
; back, in order: the stack pointer, interrupts, zero page $D0-$FF, the border
; and background colours, and the NMI vector.
;
; sei comes second, before the zero page save and before anything reads
; $A000-$BFFF.  The kernal's raster IRQ scans the keyboard through KEYLOG at
; $F5/$F6 on every frame, which is inside the block this program is about to
; take, so leaving interrupts on for even the save would have the two fighting.

    .include "aux_defs.s"

.import display_init
.import display_keys
.import display_keys_clear
.import display_group
.import display_rings
.import display_rings_fresh
.import display_note
.import display_fail
.import display_all
.import display_reset
.import reset_pin
.import reset_flash
.import clear_row

.import pins_discover
.import pins_scan
.import pins_scan_all
.import pins_set
.import pins_close
.import pins_group_count
.import pins_group_drv
.import pins_group_pins
.import pin_flags
.import pin_state
.import pins_drv_at
.import pins_hold
.import pins_after
.import pins_gone
.import pins_switch_exit
.import pins_slot
.import pins_load
.import pins_read_flash_name
.import pins_flash_count
.import pins_flash_types

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

saved_sp:       .res 1
saved_zp:       .res ZP_SAVE_COUNT
saved_border:   .res 1
saved_bg:       .res 1
saved_nmi:      .res 2

.export nmi_flag
nmi_flag:       .res 1

.export cur_group
.export cur_slot
cur_group:      .res 1
cur_slot:       .res 1      ; index into the current group's drivable list

key_held:       .res 1
armed:          .res 1
blink_phase:    .res 1
moved:          .res 1      ; bit 7 set if a pin followed the one under test
before_state:   .res MAX_GROUPS * MAX_PINS  ; a move test's starting picture

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

BLINK_HOLD = 50             ; 10ms units, so half a second each way

; ---------------------------------------------------------------------------
; main — SYS 2061 arrives here with interrupts on and the kernal live.
; ---------------------------------------------------------------------------

main:
    tsx
    stx saved_sp
    sei                         ; before the first use of $D0-$FF

    ldx #0
@save_zp:
    lda ZP_SAVE_BASE, x
    sta saved_zp, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @save_zp

    lda VIC_BORDER
    sta saved_border
    lda VIC_BACKGROUND
    sta saved_bg

    lda #0
    sta armed
    sta cur_group
    sta cur_slot
    sta blink_phase
    sta pins_hold
    lda #RBCP_AUX_RELEASE
    sta pins_after
    lda #1
    sta pins_slot
    lda #$FF
    sta reset_flash             ; BSS arrives holding whatever BASIC left

    jsr nmi_install
    jsr display_init
    jsr display_keys

    jsr pins_discover
    bcc @armed
    jsr display_fail            ; the reason is already in A
    jmp wait_quit
@armed:
    lda #1
    sta armed
    jsr redraw
    jsr script
    jmp loop                    ; script sits between here and loop

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
.if SCRIPT = 1                          ; a driven pin, part way along a group
    lda #KEY_PIN_NEXT
    jsr dispatch
    lda #KEY_PIN_NEXT
    jsr dispatch
    lda #KEY_PIN_NEXT
    jsr dispatch
    lda #KEY_HIGH_CODE
    jsr dispatch
    lda cur_group
    jsr pins_scan
    jsr display_rings
.endif
.if SCRIPT = 2                          ; the loopback, on the last group
    lda #KEY_GRP_PREV
    jsr dispatch
    lda #KEY_HIGH_CODE
    jsr dispatch
    lda cur_group
    jsr pins_scan
    jsr display_rings
.endif
.if SCRIPT = 3                          ; a move test, run to the end
    lda #KEY_TEST_CODE
    jsr dispatch
.endif
.if SCRIPT = 6                          ; a move test where a wire is fitted
    lda #KEY_GRP_PREV
    jsr dispatch
    lda #KEY_TEST_CODE
    jsr dispatch
.endif
.if SCRIPT = 4                          ; the technical view
    jsr pins_scan_all
    jsr display_all
    jmp wait_quit
.endif
.if SCRIPT = 5                          ; the reset question
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    sta reset_pin
    lda #$FF
    sta reset_flash
    jsr next_image
    jsr show_reset_screen
    jmp wait_quit
.endif
    rts

; ---------------------------------------------------------------------------
; loop — the program's resting state.  Rescans the current group, redraws it,
; and takes one key.
;
; The scan is the refresh: one GET_AUX_PIN_INFO per pin, so a group of thirty
; costs thirty commands and the picture is as live as the device is fast.
; ---------------------------------------------------------------------------

loop:
    lda cur_group
    jsr pins_scan
    bcs lost
    jsr display_rings

    jsr scan_key
    cmp #KEY_NONE_CODE
    beq loop
    sta key_held
    jsr wait_no_key
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
    cmp #KEY_QUIT_CODE
    bne @not_q
    jmp quit
@not_q:
    cmp #KEY_PIN_NEXT
    bne @not_pn
    jmp pin_next
@not_pn:
    cmp #KEY_PIN_PREV
    bne @not_pp
    jmp pin_prev
@not_pp:
    cmp #KEY_GRP_NEXT
    bne @not_gn
    jmp group_next
@not_gn:
    cmp #KEY_GRP_PREV
    bne @not_gp
    jmp group_prev
@not_gp:
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
    cmp #KEY_TEST_CODE
    bne @not_test
    jmp move_test
@not_test:
    cmp #KEY_ALL_CODE
    bne @not_all
    jmp show_all
@not_all:
    cmp #KEY_RESET_CODE
    bne @not_reset
    jmp show_reset
@not_reset:
    rts

; ---------------------------------------------------------------------------
; show_all — the technical view, until any key.
; ---------------------------------------------------------------------------

show_all:
    jsr pins_scan_all
    jsr display_all
    jsr wait_any_key
    jsr display_init
    jsr display_keys
    jmp redraw

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
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    sta reset_pin

    ; Start on the first image of the served ROM's type.  There is always one:
    ; the program refused to arm without a flash slot matching what is being
    ; served, and that slot is of that type by definition.
    lda #$FF
    sta reset_flash
    jsr next_image
    jsr show_reset_screen

@wait:
    jsr scan_key
    cmp #KEY_NONE_CODE
    bne @key
    jsr scan_return
    bne @wait
    jmp do_reset
@key:
    cmp #KEY_PIN_NEXT
    bne @not_next
    jsr wait_no_key
    jsr next_image
    jsr show_reset_screen
    jmp @wait
@not_next:
    jsr wait_no_key
    jsr display_keys
    jmp redraw

; ---------------------------------------------------------------------------
; next_image — the next flash slot holding the type of ROM this machine is
; being served, wrapping.  reset_flash of $FF starts the search from zero.
; Clobbers A, X.
; ---------------------------------------------------------------------------

next_image:
    ldx reset_flash
@step:
    inx
    cpx pins_flash_count
    bcc @check
    ldx #0
@check:
    lda pins_flash_types, x
    cmp #ROM_TYPE_2364
    bne @step
    stx reset_flash
    rts

show_reset_screen:
    lda reset_flash
    jsr pins_read_flash_name
    jmp display_reset

do_reset:
    lda #RESET_HOLD
    sta pins_hold
    lda #RBCP_AUX_RELEASE
    sta pins_after
    lda reset_flash
    jsr pins_load
    bcc @loaded
    lda #NOTE_REFUSED
    jsr display_note
    jsr display_keys
    jmp redraw
@loaded:
    ldx reset_pin
    ldy cur_group
    lda #RBCP_AUX_LOW
    jsr pins_switch_exit
    lda #NOTE_GONE
    jsr display_note
    jmp wait_quit

; ---------------------------------------------------------------------------
; scan_return — one column.  Z set means RETURN is held.  Clobbers A.
; ---------------------------------------------------------------------------

scan_return:
    lda #KEY_COL_0
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RETURN_BIT
    rts

; ---------------------------------------------------------------------------
; wait_any_key — until something is pressed, and then released.
; ---------------------------------------------------------------------------

wait_any_key:
    jsr scan_key
    cmp #KEY_NONE_CODE
    beq wait_any_key
    jmp wait_no_key

; ---------------------------------------------------------------------------
; Cursor movement.  The cursor lives on the drivable list, so a group with
; nothing drivable has nowhere for it to be and the keys do nothing.
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

group_next:
    inc cur_group
    lda pins_group_count
    cmp cur_group
    bne @ok
    lda #0
    sta cur_group
@ok:
    jmp group_changed

group_prev:
    lda cur_group
    bne @down
    lda pins_group_count
    sta cur_group
@down:
    dec cur_group
    jmp group_changed

group_changed:
    lda #0
    sta cur_slot
    lda cur_group
    jsr pins_scan
    bcs @lost
    jsr display_group
    jsr display_rings_fresh
    jmp note_pin
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
    jsr display_group
    jsr display_rings_fresh
    jmp note_pin

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
    jsr pins_set
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
    jsr display_rings

    jsr half_second

    jsr scan_key
    cmp #KEY_NONE_CODE
    beq @cycle

    jsr wait_no_key
    jsr display_keys
    jmp note_pin

; ---------------------------------------------------------------------------
; half_second — a wait long enough to see, with no timer of its own.  Rough is
; fine: nothing measures it, and a blink that is a little off half a second
; looks exactly like one that is not.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

half_second:
    ldx #0
    ldy #0
@loop:
    dex
    bne @loop
    dey
    cpy #200
    bne @loop
    rts

; ---------------------------------------------------------------------------
; move_test — drives the cursor pin through low, high and released, scanning
; every pin at each step, and reports which other pin moved with it.
;
; This is the only thing here that says anything about the world outside the
; device.  A pin the device is not driving only follows if the signal left the
; chip, crossed a wire and came back, so a follower is evidence the pin
; actually moved.  Reading back the pin that was just driven is not: that
; answer comes from the same place the drive went.
; ---------------------------------------------------------------------------

move_test:
    ldx cur_group
    lda pins_group_drv, x
    bne @have
    lda #NOTE_NOT_DRIVABLE
    jmp display_note
@have:
    jsr display_keys_clear

    ; Low first, and the picture is taken with it held there.  Comparing the
    ; end of the test against its beginning would find nothing: the last step
    ; releases the pin, which puts everything back where it started.
    lda #NOTE_TEST_LOW
    jsr display_note
    lda #RBCP_AUX_LOW
    jsr test_step
    jsr snapshot

    lda #NOTE_TEST_HIGH
    jsr display_note
    lda #RBCP_AUX_HIGH
    jsr test_step
    jsr compare
    ror moved                   ; carry into bit 7, kept across the last step

    lda #NOTE_TEST_REL
    jsr display_note
    lda #RBCP_AUX_RELEASE
    jsr test_step

    jsr display_keys
    bit moved
    bmi @moved
    lda #NOTE_TEST_NONE
    jmp display_note
@moved:
    lda #NOTE_TEST_DONE
    jmp display_note

; ---------------------------------------------------------------------------
; test_step — A = state.  Drives the cursor pin, rescans everything so a
; follower in another group is seen too, and shows it.
; ---------------------------------------------------------------------------

test_step:
    pha
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    tax
    ldy cur_group
    pla
    jsr pins_set
    jsr pins_scan_all
    jsr display_rings
    jmp half_second

; ---------------------------------------------------------------------------
; snapshot — keeps the picture as it was before the test, so compare has
; something to compare against.  Clobbers A, X.
; ---------------------------------------------------------------------------

snapshot:
    ldx #0
@loop:
    lda pin_state, x
    sta before_state, x
    inx
    bne @loop
    rts

; ---------------------------------------------------------------------------
; compare — carry set if any pin other than the one driven ended up at a level
; it did not start at.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

compare:
    lda cur_slot
    ldx cur_group
    jsr pins_drv_at
    sta ZP_APP0                 ; the pin under test
    lda cur_group
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc ZP_APP0
    sta ZP_APP1                 ; its table index

    ldx #0
@loop:
    cpx ZP_APP1
    beq @next
    lda pin_state, x
    eor before_state, x
    and #PIN_LEVEL_BIT
    bne @found
@next:
    inx
    bne @loop
    clc
    rts
@found:
    sec
    rts

; ---------------------------------------------------------------------------
; wait_quit — the resting state when there is nothing to show.  Only Q leaves.
; ---------------------------------------------------------------------------

wait_quit:
    jsr scan_key
    cmp #KEY_QUIT_CODE
    bne wait_quit
    ; fall through

quit:
    lda armed
    beq leave
    lda pins_gone
    bne leave
    jsr pins_close
    ; fall through

; ---------------------------------------------------------------------------
; leave — hands the machine back and returns to BASIC.
;
; Order is the reverse of main's.  The kernal clear-screen call comes after the
; zero page restore because the screen editor works through LDTB1 at $D9-$F2,
; which this program has been using.
;
; The release wait comes first.  Without it the key that asked to quit is still
; held when cli runs, the kernal's IRQ scan puts it in the keyboard buffer, and
; BASIC echoes it after READY.  Zeroing NDX afterwards catches anything the IRQ
; managed to buffer between cli and here.
; ---------------------------------------------------------------------------

leave:
    jsr wait_no_key

    jsr nmi_restore

    lda saved_border
    sta VIC_BORDER
    lda saved_bg
    sta VIC_BACKGROUND

    ldx #0
@restore_zp:
    lda saved_zp, x
    sta ZP_SAVE_BASE, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @restore_zp

    ldx saved_sp
    txs
    cli
    lda #0
    sta KEY_NDX
    jsr KERNAL_CLRSCR
    rts

; ---------------------------------------------------------------------------
; NMI
;
; RESTORE is edge-triggered through its own monostable rather than through a
; CIA, so nothing needs acknowledging.  The kernal's NMI entry does sei then
; jmp ($0318) without saving registers, so the stub saves the one it uses.
;
; Without this the default handler reaches jmp ($A002) when RUN/STOP is held
; with RESTORE — a read of the command page in the middle of a session, which
; would inject a command byte.  The stub touches nothing else, so an NMI
; arriving mid-command stretches the frame in time but does not corrupt it.
; ---------------------------------------------------------------------------

nmi_stub:
    pha
    lda #1
    sta nmi_flag
    pla
    rti

nmi_install:
    lda #0
    sta nmi_flag
    lda NMINV
    sta saved_nmi
    lda NMINV+1
    sta saved_nmi+1
    lda #<nmi_stub
    sta NMINV
    lda #>nmi_stub
    sta NMINV+1
    rts

nmi_restore:
    lda saved_nmi
    sta NMINV
    lda saved_nmi+1
    sta NMINV+1
    rts

; ---------------------------------------------------------------------------
; scan_key — returns a key code in A, KEY_NONE_CODE if nothing is held.
;
; Six column selects cover the ten keys this program uses.  Shift is read on
; the two cursor keys only, where it reverses the direction, which is what a
; C64 does with them everywhere else.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export scan_key
scan_key:
    ; column 0 — the cursor keys
    lda #KEY_COL_0
    sta CIA1_PRA
    lda CIA1_PRB
    tay
    and #KEY_CRSR_RT_BIT
    bne @c0_dn
    jsr shift_held
    bcs @pin_prev
    lda #KEY_PIN_NEXT
    jmp key_done
@pin_prev:
    lda #KEY_PIN_PREV
    jmp key_done
@c0_dn:
    tya
    and #KEY_CRSR_DN_BIT
    bne @col_1
    jsr shift_held
    bcs @grp_prev
    lda #KEY_GRP_NEXT
    jmp key_done
@grp_prev:
    lda #KEY_GRP_PREV
    jmp key_done

@col_1:
    lda #KEY_COL_1
    sta CIA1_PRA
    lda CIA1_PRB
    tay
    and #KEY_A_BIT
    bne @c1_z
    lda #KEY_ALL_CODE
    jmp key_done
@c1_z:
    tya
    and #KEY_Z_BIT
    bne @col_2
    lda #KEY_REL_CODE
    jmp key_done

@col_2:
    lda #KEY_COL_2
    sta CIA1_PRA
    lda CIA1_PRB
    tay
    and #KEY_R_BIT
    bne @c2_t
    lda #KEY_RESET_CODE
    jmp key_done
@c2_t:
    tya
    and #KEY_T_BIT
    bne @col_3
    lda #KEY_TEST_CODE
    jmp key_done

@col_3:
    lda #KEY_COL_3
    sta CIA1_PRA
    lda CIA1_PRB
    tay
    and #KEY_B_BIT
    bne @c3_h
    lda #KEY_BLINK_CODE
    jmp key_done
@c3_h:
    tya
    and #KEY_H_BIT
    bne @col_5
    lda #KEY_HIGH_CODE
    jmp key_done

@col_5:
    lda #KEY_COL_5
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_L_BIT
    bne @col_7
    lda #KEY_LOW_CODE
    jmp key_done

@col_7:
    lda #KEY_COL_7
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_Q_BIT
    bne @none
    lda #KEY_QUIT_CODE
    jmp key_done
@none:
    lda #KEY_NONE_CODE
    rts

; key_done — the debounce every detected key passes through.  About 200 cycles,
; which is what stops a held key repeating between two scans.
key_done:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts

; ---------------------------------------------------------------------------
; shift_held — carry set if either shift key is down.  Clobbers A.
; ---------------------------------------------------------------------------

shift_held:
    lda #KEY_COL_1
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_LSHIFT_BIT
    beq @yes
    lda #KEY_COL_6
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RSHIFT_BIT
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; ---------------------------------------------------------------------------
; wait_no_key — spins until nothing is held.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export wait_no_key
wait_no_key:
    jsr scan_key
    cmp #KEY_NONE_CODE
    bne wait_no_key
    rts
