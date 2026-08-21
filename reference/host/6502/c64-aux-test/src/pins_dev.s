; pins_dev.s — the pins.s interface, against a real device
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything here runs with interrupts masked and the program executing from
; RAM.  Between the knock and the exit nothing may read $A000-$BFFF except the
; command page reads the protocol makes and the back-channel reads it requires.
; The image checksum, the knock and the way out are rbcp_session.s's, shared
; with the other testers.  What is left here is the auxiliary I/O group and
; nothing else.
;
; This file has never run.  There is no 6502 emulator here that speaks RBCP and
; the demo build deliberately does not exercise it: hardware is the only thing
; that can.

    .include "aux_defs.s"

.import sess_mark_gone
.import sess_slot

.import rbcp_cmd_get_aux_capability
.import rbcp_cmd_get_aux_group_info
.import rbcp_cmd_get_aux_pin_info
.import rbcp_cmd_set_aux
.import rbcp_cmd_set_aux_and_exit
.import rbcp_cmd_set_aux_switch_exit

.import pins_rebuild_drv
.import pins_group_count
.import pins_max_hold
.import pins_group_type
.import pins_group_pins
.import pin_flags
.import pin_state
.import pins_hold
.import pins_after
.import pins_truncated

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

scan_pin:       .res 1
scan_count:     .res 1
scan_base:      .res 1
scan_grp:       .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; pins_discover — opens the session and reads everything that does not change
; while it is open.
;
; Carry clear armed, carry set refused with a FAIL_ code in A.
; ---------------------------------------------------------------------------

.export pins_discover
pins_discover:
    lda #0
    sta pins_truncated

    ; GET_AUX_CAPABILITY takes no argument bytes, so a device whose protocol
    ; version predates the Auxiliary I/O group fails it and stays in step.
    ; Carry set means no auxiliary pins here either way.
    jsr rbcp_cmd_get_aux_capability
    bcs @no_aux
    lda RBCP_DATA_ADDR + RBCP_AUX_CAP_GROUPS
    bne @have_aux
@no_aux:
    lda #FAIL_NO_AUX
    sec
    rts

@have_aux:
    cmp #MAX_GROUPS + 1
    bcc @groups_fit
    lda #1
    sta pins_truncated
    lda #MAX_GROUPS
@groups_fit:
    sta pins_group_count
    lda RBCP_DATA_ADDR + RBCP_AUX_CAP_MAX_HOLD
    sta pins_max_hold

    jsr read_groups
    bcc @groups_ok
    lda #FAIL_NO_AUX
    sec
    rts
@groups_ok:
    jsr pins_scan_all
    bcc @done
    lda #SESS_FAIL_NO_DEVICE
    sec
    rts
@done:
    clc
    rts

; ---------------------------------------------------------------------------
; read_groups — the type and pin count of every group this program will show.
;
; A pin count of zero means 256, which is more than this program can draw, so
; it clamps and says so rather than wrapping to nothing.
;
; Carry set if the device refused a group it had just claimed to have.
; ---------------------------------------------------------------------------

read_groups:
    lda #0
    sta scan_grp
@loop:
    lda scan_grp
    jsr rbcp_cmd_get_aux_group_info
    bcs @fail
    ldx scan_grp
    lda RBCP_DATA_ADDR + RBCP_AUX_GROUP_TYPE
    sta pins_group_type, x
    lda RBCP_DATA_ADDR + RBCP_AUX_GROUP_PINS
    bne @not_256
    lda #MAX_PINS               ; zero means 256, and 256 is past our limit
    sta pins_truncated
    bne @store                  ; always taken
@not_256:
    cmp #MAX_PINS + 1
    bcc @store
    pha
    lda #1
    sta pins_truncated
    pla
    lda #MAX_PINS
@store:
    ldx scan_grp
    sta pins_group_pins, x
    inc scan_grp
    lda scan_grp
    cmp pins_group_count
    bne @loop
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; pins_scan — A = group.  One GET_AUX_PIN_INFO per pin.
; Carry set means the device stopped answering.
; ---------------------------------------------------------------------------

.export pins_scan
pins_scan:
    sta scan_grp
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta scan_base
    ldx scan_grp
    lda pins_group_pins, x
    sta scan_count

    lda #0
    sta scan_pin
@loop:
    lda scan_pin
    cmp scan_count
    beq @done
    lda scan_pin
    ldx scan_grp
    jsr rbcp_cmd_get_aux_pin_info
    bcs @fail

    lda scan_pin
    clc
    adc scan_base
    tax
    lda RBCP_DATA_ADDR + RBCP_AUX_PIN_FLAGS
    sta pin_flags, x

    ; Level and driven mean nothing unless the device says they do, so a pin
    ; that cannot be read is recorded low and undriven rather than believed.
    lda #0
    sta pin_state, x
    lda pin_flags, x
    and #RBCP_AUX_FLAG_READABLE
    beq @next
    lda RBCP_DATA_ADDR + RBCP_AUX_PIN_LEVEL
    beq @not_high
    lda #PIN_LEVEL_BIT
    sta pin_state, x
@not_high:
    lda RBCP_DATA_ADDR + RBCP_AUX_PIN_DRIVEN
    beq @next
    lda pin_state, x
    ora #PIN_DRIVEN_BIT
    sta pin_state, x
@next:
    inc scan_pin
    bne @loop
@done:
    lda scan_grp
    jsr pins_rebuild_drv
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; pins_scan_all — every group.  Carry set as pins_scan.
; ---------------------------------------------------------------------------

.export pins_scan_all
pins_scan_all:
    lda #0
    sta all_grp
@loop:
    lda all_grp
    jsr pins_scan
    bcs @fail
    inc all_grp
    lda all_grp
    cmp pins_group_count
    bne @loop
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; pins_set — A = state, X = pin, Y = group, with pins_hold and pins_after.
; Carry set means the device refused it.
; ---------------------------------------------------------------------------

.export pins_set
pins_set:
    jsr set_args
    jmp rbcp_cmd_set_aux

; ---------------------------------------------------------------------------
; pins_set_exit — as pins_set, and terminal.  Nothing to poll and nothing to
; report: the device writes no response header for this one.
; ---------------------------------------------------------------------------

.export pins_set_exit
pins_set_exit:
    jsr set_args
    jsr rbcp_cmd_set_aux_and_exit
    jmp sess_mark_gone

; ---------------------------------------------------------------------------
; pins_switch_exit — as pins_set_exit, and activates sess_slot as well.
;
; Pin first, because the pin this is for is one that stops the host: the
; machine is held while the image underneath it changes.  Under that ordering
; the device does not apply after until the switch is done, so the hold is at
; least as long as the switch takes.
; ---------------------------------------------------------------------------

.export pins_switch_exit
pins_switch_exit:
    jsr set_args
    lda rbcp_arg3               ; set_args left pin here, and group in arg4
    pha
    lda rbcp_arg4
    pha
    lda #RBCP_AUX_PIN_FIRST
    sta rbcp_arg3
    pla
    sta rbcp_arg5               ; group
    pla
    sta rbcp_arg4               ; pin
    lda sess_slot
    sta rbcp_arg6
    jsr rbcp_cmd_set_aux_switch_exit
    jmp sess_mark_gone

; ---------------------------------------------------------------------------
; set_args — A = state, X = pin, Y = group into the SET_AUX argument layout.
; Clobbers A.
; ---------------------------------------------------------------------------

set_args:
    sta rbcp_arg0               ; state
    stx rbcp_arg3               ; pin
    sty rbcp_arg4               ; group
    lda pins_after
    sta rbcp_arg1
    lda pins_hold
    sta rbcp_arg2
    rts

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

all_grp:        .res 1
