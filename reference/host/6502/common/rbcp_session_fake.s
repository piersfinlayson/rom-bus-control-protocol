; rbcp_session_fake.s — a session with no device at the other end
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Provides the rbcp_session.s interface out of fixed answers, so that the demo
; build of a tester can be looked at under an emulator, where there is nothing
; to knock on and nothing past the knock can run.  It is never linked into a
; binary that talks to hardware.
;
; What it does not model: the knock, the command encoding, the polling
; sequence, the image checksum and every way a real device can refuse.  None of
; those are visible on screen, which is the whole reason this file can stand in.

    .include "app_defs.s"

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export sess_spare_slot
.export sess_exit_slot
.export sess_slot
.export sess_gone
.export sess_dev_type
.export sess_dev_ver
.export sess_proto
.export sess_flash_count
.export sess_flash_types
.export sess_flash_name

sess_spare_slot:  .res 1
sess_exit_slot:   .res 1
sess_slot:        .res 1
sess_gone:        .res 1
sess_dev_type:    .res 25
sess_dev_ver:     .res 25
sess_proto:       .res 12
sess_flash_count: .res 1
sess_flash_types: .res 16
sess_flash_name:  .res 32

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; fake_cost — burns what a command would have cost on a real device, about
; 320us at the rate the pipe throughput test measured.  The loop is 5 cycles an
; iteration at roughly 1MHz.
;
; Every register survives, which is the whole point of the two saves.  A caller
; counting LEDs or pins in X is charging itself a command an iteration, so
; eating X here would stop it ever finishing — and a caller that has just been
; handed an LED number in A is about to use it.
; ---------------------------------------------------------------------------

.export fake_cost
fake_cost:
    pha
    txa
    pha
    ldx #64
@loop:
    dex
    bne @loop
    pla
    tax
    pla
    rts

; ---------------------------------------------------------------------------
; sess_open — always succeeds.  Fills the identity a device would report and
; two flash slots of the served ROM's type, so a screen offering a choice of
; image has one to offer and something to name.
; ---------------------------------------------------------------------------

.export sess_open
sess_open:
    lda #0
    sta sess_gone
    sta sess_slot
    sta sess_exit_slot
    lda #1
    sta sess_spare_slot

    ldx #0
@ident:
    lda fake_ident, x
    sta sess_dev_type, x
    lda fake_ident + 12, x
    sta sess_dev_ver, x
    lda fake_ident + 20, x
    sta sess_proto, x
    inx
    cpx #12
    bne @ident

    lda #2
    sta sess_flash_count
    lda #CONFIG_ROM_TYPE
    sta sess_flash_types + 0
    sta sess_flash_types + 1
    clc
    rts

.export sess_close
sess_close:
    ; fall through

.export sess_mark_gone
sess_mark_gone:
    lda #1
    sta sess_gone
    rts

.export sess_load
sess_load:
    jsr fake_cost
    lda sess_spare_slot
    sta sess_slot
    clc
    rts

; sess_read_flash_name — A = flash slot.  There is no flash here, so the names
; are made up, and only slot 1 gets the second one.
.export sess_read_flash_name
sess_read_flash_name:
    jsr fake_cost
    cmp #1
    beq @second
    ldx #0
@copy_first:
    lda fake_name_1, x
    sta sess_flash_name, x
    beq @done
    inx
    bne @copy_first
@second:
    ldx #0
@copy_second:
    lda fake_name_2, x
    sta sess_flash_name, x
    beq @done
    inx
    bne @copy_second
@done:
    clc
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

fake_name_1:
    .byte "BASIC V2", 0
fake_name_2:
    .byte "BASIC V2 GREEN", 0

; What a device would answer with, so a screen showing the device's identity
; looks the same here as it will there.  Three fixed length fields rather than
; three strings, so one loop copies all of them.
fake_ident:
    .byte "ONE ROM", 0, 0, 0, 0, 0
    .byte "0.7.2", 0, 0, 0
    .byte "RBCP 0.1.2", 0, 0
