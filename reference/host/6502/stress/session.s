; session.s — opening the meter's session, and nothing more
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The meter is a ROM.  It owns the machine from reset, it never gives it back,
; and you switch off when you have read the number.  So there is no exit to
; repair, and none of the apparatus common/rbcp_session.s carries for one —
; the image checksum, the hunt for a flash slot holding a pristine copy, the
; spare RAM slot, the SLOT_PEEK verification, the switch on the way out.  The
; device reloads its RAM slot from flash at power-on, so switching off is the
; repair.
;
; What is left is the knock, command-response mode, the version check and the
; three strings the device calls itself.

    .include "stress_defs.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export sess_dev_type
.export sess_dev_ver
.export sess_proto

; What the device calls itself.  Read once, while the session is opening, and
; drawn from here afterwards.  A device that has stopped answering will not
; answer a question about its own name either.
sess_dev_type:  .res 25
sess_dev_ver:   .res 25
sess_proto:     .res 12

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; sess_open — knocks, enters command-response mode, checks the protocol
; version and reads the device's identity.
;
; Carry clear open, carry set refused with a FAIL_ code in A.
; ---------------------------------------------------------------------------

.export sess_open
sess_open:
    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @entered
    lda rbcp_zp_5
    cmp #1
    bne @refused                ; it answered, so something is there
    lda #FAIL_NO_DEVICE         ; the token never moved
    sec
    rts
@refused:
    lda #FAIL_ENTER
    sec
    rts

@entered:
    jsr rbcp_check_protocol_version
    bcc @ver_ok
    lda #FAIL_VERSION
    sec
    rts
@ver_ok:
    jsr read_identity
    clc
    rts

; ---------------------------------------------------------------------------
; read_identity — device type, device version and protocol version into the
; buffers the display reads.  Each response is ASCII, null-terminated, in the
; data section.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

read_identity:
    lda #0
    sta sess_dev_type
    sta sess_dev_ver
    sta sess_proto

    jsr rbcp_cmd_get_device_type
    bcs @no_type
    ldy #0
@type_loop:
    lda RBCP_DATA_ADDR, y
    sta sess_dev_type, y
    beq @type_done
    iny
    cpy #24
    bne @type_loop
@type_done:
    lda #0
    sta sess_dev_type + 24
@no_type:

    jsr rbcp_cmd_get_device_version
    bcs @no_ver
    ldy #0
@ver_loop:
    lda RBCP_DATA_ADDR, y
    sta sess_dev_ver, y
    beq @ver_done
    iny
    cpy #24
    bne @ver_loop
@ver_done:
    lda #0
    sta sess_dev_ver + 24
@no_ver:

    jsr rbcp_cmd_get_protocol_version
    bcs @no_proto
    lda #'R'
    sta sess_proto + 0
    lda #'B'
    sta sess_proto + 1
    lda #'C'
    sta sess_proto + 2
    lda #'P'
    sta sess_proto + 3
    lda #' '
    sta sess_proto + 4
    lda RBCP_DATA_ADDR + 0
    clc
    adc #'0'
    sta sess_proto + 5
    lda #'.'
    sta sess_proto + 6
    lda RBCP_DATA_ADDR + 1
    clc
    adc #'0'
    sta sess_proto + 7
    lda #'.'
    sta sess_proto + 8
    lda RBCP_DATA_ADDR + 2
    clc
    adc #'0'
    sta sess_proto + 9
    lda #0
    sta sess_proto + 10
@no_proto:
    rts
