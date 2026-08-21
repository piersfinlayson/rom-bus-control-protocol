; pins_fake.s — a device that is not there
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Provides the pins.s interface out of a table instead of a device, so that
; every screen this program can draw is reachable under an emulator.  It is
; never linked into the shipped binary: the Makefile builds rbcp_aux_test.prg
; from pins_dev.s and rbcp_aux_demo.prg from this.
;
; What it models, and why each part is here:
;
;   - Several boards, chosen by BOARD at assembly time, so that every ring tier
;     and the empty-group case can be looked at.
;   - A loopback: driving the pin named as the source moves the one named as
;     the follower, which is what makes the move test worth running here.
;   - A cost per command close to the real one, so the refresh rate on screen
;     is the rate a device would give rather than an emulator's.
;
; What it does not model: the RBCP command encoding, the polling sequence, the
; knock, and every way a real device can refuse.  None of those are visible on
; screen, which is the whole reason this file can stand in.

    .include "aux_defs.s"

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

.import fake_cost
.import sess_gone
.import sess_mark_gone

; ---------------------------------------------------------------------------
; Boards.  BOARD is -D on the assembler command line, defaulting to 0.
;
;   0  three groups: 30 GPIO of which 14 drivable, 4 image select, 2 X pads.
;      The board this program was drawn for.
;   1  two groups, no X pads: the small tier, and a group with nothing
;      drivable.
;   2  one group of 48 GPIO, 30 of them drivable: the dot tier.
; ---------------------------------------------------------------------------

.ifndef BOARD
BOARD = 0
.endif

; The shape of each board.  These are up here rather than beside their tables
; because fake_apply tests BOARD_LOOP_SRC in a .if, and ca65 wants the value
; before it reaches the test.

.if BOARD = 0
BOARD_GROUPS   = 3
BOARD_MAX_HOLD = 255
BOARD_LOOP_SRC = 2 * MAX_PINS + 0       ; X pad 0 drives
BOARD_LOOP_DST = 2 * MAX_PINS + 1       ; X pad 1 follows
.endif

.if BOARD = 1
BOARD_GROUPS   = 2
BOARD_MAX_HOLD = 255
BOARD_LOOP_SRC = $FF
BOARD_LOOP_DST = $FF
.endif

.if BOARD = 2
BOARD_GROUPS   = 1
BOARD_MAX_HOLD = 0                      ; no timed holds, so blink is ours
BOARD_LOOP_SRC = 18
BOARD_LOOP_DST = 19
.endif

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; The level the fake device is holding on each pin, and whether it is driving.
; pins_scan copies these into pin_state, which is what the display reads.
fake_level:     .res MAX_GROUPS * MAX_PINS
fake_driven:    .res MAX_GROUPS * MAX_PINS
scan_group:     .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; pins_discover — fills the group tables from the board table.  The session is
; already open by the time this runs, as it is against a real device.
; Carry clear always: a fake device is always there.
; ---------------------------------------------------------------------------

.export pins_discover
pins_discover:
    lda #0
    sta pins_truncated

    ldx #0
@groups:
    lda board_type, x
    sta pins_group_type, x
    lda board_pins, x
    sta pins_group_pins, x
    inx
    cpx #BOARD_GROUPS
    bne @groups

    lda #BOARD_GROUPS
    sta pins_group_count
    lda #BOARD_MAX_HOLD
    sta pins_max_hold

    jsr fake_reset_pins
    jsr pins_scan_all
    clc
    rts

; ---------------------------------------------------------------------------
; fake_reset_pins — every pin released, and its level whatever the board table
; says it idles at.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

fake_reset_pins:
    ldy #0                      ; group
@group:
    tya
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_APP0                 ; slice base
    lda board_pins, y
    sta ZP_APP1                 ; pins in this group

    ldx #0                      ; pin
@pin:
    cpx ZP_APP1
    beq @next_group
    txa
    clc
    adc ZP_APP0
    stx ZP_APP2
    tax
    lda #0
    sta fake_level, x
    sta fake_driven, x
    ldx ZP_APP2
    inx
    bne @pin
@next_group:
    iny
    cpy #BOARD_GROUPS
    bne @group

    jmp fake_set_flags

; ---------------------------------------------------------------------------
; fake_set_flags — writes pin_flags for every pin from the board's drivable
; masks.  A pin is drivable where its bit is set, and readable either way: a
; device knows the level on a pin it is using as much as on one it is not.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

fake_set_flags:
    ldy #0                      ; group
@group:
    tya
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_APP0
    lda board_pins, y
    sta ZP_APP1
    lda board_drv_lo, y
    sta ZP_APP2                 ; first drivable pin
    lda board_drv_hi, y
    sta ZP_APP3                 ; one past the last
    lda board_drv_step, y
    sta ZP_APP4

    ldx #0
@pin:
    cpx ZP_APP1
    beq @next_group
    ; drivable where lo <= pin < hi and (pin - lo) is a multiple of step
    lda #RBCP_AUX_FLAG_READABLE
    sta ZP_APP5
    cpx ZP_APP2
    bcc @store
    cpx ZP_APP3
    bcs @store
    txa
    sec
    sbc ZP_APP2
@mod:
    cmp ZP_APP4
    bcc @mod_done
    sec
    sbc ZP_APP4
    jmp @mod
@mod_done:
    cmp #0
    bne @store
    lda #RBCP_AUX_FLAG_READABLE | RBCP_AUX_FLAG_DRIVABLE
    sta ZP_APP5
@store:
    txa
    clc
    adc ZP_APP0
    stx ZP_APP6
    tax
    lda ZP_APP5
    sta pin_flags, x
    ldx ZP_APP6
    inx
    bne @pin
@next_group:
    iny
    cpy #BOARD_GROUPS
    bne @group
    rts

; ---------------------------------------------------------------------------
; pins_scan — A = group.  Copies the fake device's own view into pin_state and
; rebuilds the drivable list.  Carry clear always.
; ---------------------------------------------------------------------------

.export pins_scan
pins_scan:
    pha
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_APP0
    pla
    pha
    tax
    lda pins_group_pins, x
    sta ZP_APP1

    ldx #0
@pin:
    cpx ZP_APP1
    beq @done
    stx ZP_APP2                 ; before fake_cost, which takes X for itself
    jsr fake_cost
    lda ZP_APP2
    clc
    adc ZP_APP0
    tax
    lda #0
    ldy fake_level, x
    beq @no_level
    ora #PIN_LEVEL_BIT
@no_level:
    ldy fake_driven, x
    beq @no_driven
    ora #PIN_DRIVEN_BIT
@no_driven:
    sta pin_state, x
    ldx ZP_APP2
    inx
    bne @pin
@done:
    pla
    jsr pins_rebuild_drv
    clc
    rts

; ---------------------------------------------------------------------------
; pins_scan_all — every group.  Carry clear always.
; ---------------------------------------------------------------------------

; The counter lives here rather than in the app zero page because pins_scan
; reaches pins_rebuild_drv, which uses all of it.
.export pins_scan_all
pins_scan_all:
    lda #0
    sta scan_group
@loop:
    lda scan_group
    jsr pins_scan
    inc scan_group
    lda scan_group
    cmp pins_group_count
    bne @loop
    clc
    rts

; ---------------------------------------------------------------------------
; pins_set — A = state, X = pin, Y = group.  Applies the state, then applies
; pins_after if pins_hold is non-zero, exactly as the device would.  The hold
; itself is not waited out: nothing on screen could tell, and waiting would
; make the emulator slower than the machine it stands in for.
;
; Carry set if the pin is not drivable, which is the one refusal this file
; models, because it is the one a user can provoke from the keyboard.
; ---------------------------------------------------------------------------

.export pins_set
pins_set:
    sta ZP_APP3                 ; state
    sty ZP_APP4                 ; group
    stx ZP_APP5                 ; pin

    jsr fake_cost

    tya
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc ZP_APP5
    tax                         ; table index

    lda pin_flags, x
    and #RBCP_AUX_FLAG_DRIVABLE
    bne @ok
    sec
    rts
@ok:
    lda ZP_APP3
    jsr fake_apply

    lda pins_hold
    beq @done
    lda pins_after
    jsr fake_apply
@done:
    clc
    rts

; ---------------------------------------------------------------------------
; fake_apply — A = state, X = table index.  Moves the pin, and the follower
; too where this board has a loopback and this is its source.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

fake_apply:
    cmp #RBCP_AUX_RELEASE
    beq @release
    tay                         ; 0 low, 1 high
    tya
    sta fake_level, x
    lda #1
    sta fake_driven, x
    jmp @follow
@release:
    lda #0
    sta fake_driven, x
    ; Released, and nothing on the board pulls it, so it reads low.  A real
    ; installation would put a resistor on the net and see the pull instead.
    sta fake_level, x
@follow:
.if BOARD_LOOP_SRC <> $FF
    cpx #BOARD_LOOP_SRC
    bne @out
    lda fake_level, x
    ldy #BOARD_LOOP_DST
    sta fake_level, y
    ; The follower is an input, so it is never driven by the device.
    lda #0
    sta fake_driven, y
@out:
.endif
    rts

; ---------------------------------------------------------------------------
; pins_set_exit and pins_switch_exit — terminal.  Nothing is left to talk to,
; which is the whole point, so both just mark the device gone.
; ---------------------------------------------------------------------------

.export pins_set_exit
pins_set_exit:
    jsr pins_set
    jmp sess_mark_gone

.export pins_switch_exit
pins_switch_exit:
    jmp pins_set_exit

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; Each board is a row per group: the type byte, the pin count, and the range
; and stride of the drivable pins within it.  A stride of 1 makes the whole
; range drivable, and a larger one leaves the gaps a ROM's address lines would.

.if BOARD = 0
board_type:     .byte RBCP_AUX_TYPE_GPIO, $80, $81
board_pins:     .byte 30, 4, 2
board_drv_lo:   .byte 2, 0, 0
board_drv_hi:   .byte 30, 4, 2
board_drv_step: .byte 2, 1, 1
.endif

.if BOARD = 1
board_type:     .byte RBCP_AUX_TYPE_GPIO, $80
board_pins:     .byte 30, 4
board_drv_lo:   .byte 0, 0
board_drv_hi:   .byte 0, 4                  ; nothing drivable in the GPIO group
board_drv_step: .byte 1, 1
.endif

.if BOARD = 2
board_type:     .byte RBCP_AUX_TYPE_GPIO
board_pins:     .byte 48
board_drv_lo:   .byte 18
board_drv_hi:   .byte 48
board_drv_step: .byte 1
.endif
