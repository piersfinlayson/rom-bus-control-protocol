; pins.s — the pin tables, and everything derived from them
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The seam
; --------
; This file owns the tables.  Two files fill them and only one of them is ever
; linked: pins_dev.s talks to a real device over RBCP, pins_fake.s makes the
; answers up.  Everything else in the program reads these tables and does not
; know which was built.
;
; The interface both must provide:
;
;   pins_discover     no input, and called with the session already open.
;                     Fills group_count, max_hold, and per group the type and
;                     pin count.  Carry set means there is no auxiliary I/O to
;                     show, with a FAIL_ code in A.
;   pins_scan         A = group.  Refreshes pin_flags and pin_state for every
;                     pin in that group, and rebuilds its drivable list.
;                     Carry set means the device stopped answering.
;   pins_scan_all     every group, same failure.
;   pins_set          A = state, X = pin, Y = group, using pins_hold and
;                     pins_after.  Carry set means refused.
;   pins_set_exit     as pins_set, and terminal.
;   pins_switch_exit  as pins_set_exit, plus sess_slot.  Terminal.
;
; Everything that is about the session rather than the pins — opening it,
; leaving it cleanly, the device's identity and the flash slots — is
; rbcp_session.s, and both of these use it.
;
; Indexing
; --------
; A pin is addressed by group * MAX_PINS + pin, in one byte, which is why
; MAX_GROUPS is 4 and MAX_PINS is 64.  A device exposing more of either is
; shown up to the limit with pins_truncated set, and the screen says so.

    .include "aux_defs.s"

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export pins_group_count
.export pins_max_hold
.export pins_group_type
.export pins_group_pins
.export pins_group_drv
.export pin_flags
.export pin_state
.export drv_list
.export pins_hold
.export pins_after
.export pins_truncated

pins_group_count:   .res 1              ; groups this program will show
pins_max_hold:      .res 1              ; 10ms units, zero for no timed holds
pins_group_type:    .res MAX_GROUPS
pins_group_pins:    .res MAX_GROUPS     ; pins the device reports in the group
pins_group_drv:     .res MAX_GROUPS     ; how many of them are drivable

pin_flags:          .res MAX_GROUPS * MAX_PINS
pin_state:          .res MAX_GROUPS * MAX_PINS
drv_list:           .res MAX_GROUPS * MAX_PINS  ; drivable pin numbers, in order

pins_hold:          .res 1              ; 10ms units, argument to the next set
pins_after:         .res 1

pins_truncated:     .res 1              ; the device reported more than we show

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; pins_index — A = pin, X = group, returns the table index in A.
; Clobbers A.  X and Y survive.
; ---------------------------------------------------------------------------

.export pins_index
pins_index:
    pha
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a                       ; group * 64
    sta ZP_APP4
    pla
    clc
    adc ZP_APP4
    rts

; ---------------------------------------------------------------------------
; pins_rebuild_drv — A = group.  Walks the group's pins and writes the numbers
; of the drivable ones into that group's slice of drv_list, setting
; pins_group_drv.  Called by whichever pins_scan is linked.
;
; Clobbers A, X, Y and ZP_APP4 to ZP_APP6.
; ---------------------------------------------------------------------------

.export pins_rebuild_drv
pins_rebuild_drv:
    sta ZP_APP5                 ; group
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    sta ZP_APP6                 ; group * 64, the slice base

    ldx ZP_APP5
    lda pins_group_pins, x
    sta ZP_APP7                 ; pins to walk

    lda #0
    sta ZP_APP8                 ; drivable found so far
    ldy #0                      ; pin number
@loop:
    cpy ZP_APP7
    beq @done
    tya
    clc
    adc ZP_APP6
    tax
    lda pin_flags, x
    and #RBCP_AUX_FLAG_DRIVABLE
    beq @next
    lda ZP_APP8
    clc
    adc ZP_APP6
    tax
    tya
    sta drv_list, x
    inc ZP_APP8
@next:
    iny
    bne @loop                   ; a group never walks past 64 pins
@done:
    ldx ZP_APP5
    lda ZP_APP8
    sta pins_group_drv, x
    rts

; ---------------------------------------------------------------------------
; pins_drv_at — A = index into the group's drivable list, X = group.
; Returns the pin number in A.  Clobbers A, and ZP_APP4.
; ---------------------------------------------------------------------------

.export pins_drv_at
pins_drv_at:
    sta ZP_APP4
    txa
    asl a
    asl a
    asl a
    asl a
    asl a
    asl a
    clc
    adc ZP_APP4
    tay
    lda drv_list, y
    rts

; ---------------------------------------------------------------------------
; pins_tier — A = drivable pin count.  Returns the tier in A.
; The thresholds are what each tier's bank count and per-row width allow
; between ROW_RINGS and ROW_RINGS_END.
; ---------------------------------------------------------------------------

.export pins_tier
pins_tier:
    cmp #9
    bcc @big
    cmp #21
    bcc @mid
    cmp #37
    bcc @small
    lda #TIER_DOT
    rts
@big:
    lda #TIER_BIG
    rts
@mid:
    lda #TIER_MID
    rts
@small:
    lda #TIER_SMALL
    rts
