; session_rom.s — opening the LED tester's session
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The tester owns the machine from reset and never exits, so the session
; doesn't set up an exit.

    .include "led_defs.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export sess_gone
.export sess_dev_type
.export sess_dev_ver
.export sess_proto

sess_gone:      .res 1          ; a terminal command has been issued

; The device's identity, read once as the session opens so the title row can
; still be drawn after the device stops answering.
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
; Carry clear on success, carry set on failure with a SESS_FAIL_ code in A.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export sess_open
sess_open:
    lda #0
    sta sess_gone

    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @entered
    lda rbcp_zp_5
    cmp #1
    bne @refused                ; it answered, so something is there
    lda #SESS_FAIL_NO_DEVICE    ; the token never moved
    sec
    rts
@refused:
    lda #SESS_FAIL_ENTER
    sec
    rts

@entered:
    jsr rbcp_check_protocol_version
    bcc @ver_ok
    lda #SESS_FAIL_VERSION
    sec
    rts
@ver_ok:
    jsr read_identity
    clc
    rts

; ---------------------------------------------------------------------------
; read_identity — device type, device version and protocol version into the
; sess_ buffers.  Clobbers A, X, Y.
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
