; session.s — opening the RBCP session, and nothing more
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The terminal is a ROM.  It owns the machine from reset, it never gives it
; back, and you switch off when you have finished typing.  So there is no exit
; to repair, and none of the apparatus an exit needs — the image checksum, the
; hunt for a flash slot holding a pristine copy, the spare RAM slot, the
; SLOT_PEEK verification, the switch on the way out.  The device reloads its
; RAM slot from flash at power-on, so switching off is the repair.
;
; What is left is the knock, command-response mode, the version check, the
; three strings the device calls itself, and the two questions this program has
; that no other host asks: whether there is a pipe at all, and whether pipe 0
; takes bytes from the host.
;
; Everything here runs with interrupts masked and the terminal executing from
; RAM.  Once the knock has gone out, the only reads of the served image are the
; command page reads the protocol makes and the back-channel reads it
; requires.

    .include "term_defs.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version
.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_get_pipe_info

.import display_status

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export device_type_buf
.export device_version_buf
.export proto_ver_buf
.export session_open

device_type_buf:    .res 25     ; 24 ASCII bytes and a terminator
device_version_buf: .res 25
proto_ver_buf:      .res 12     ; "RBCP n.n.n" and a terminator

session_open:       .res 1      ; non-zero once ENTER_CMD_RESP has succeeded

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; session_start — opens the session and checks the device can do what this
; program needs.
;
; Returns carry clear open, carry set refused, with the reason already on the
; status row.
;
; Clobbers A, X, Y, the app zero page and the RBCP arguments.
; ---------------------------------------------------------------------------

.export session_start
session_start:
    lda #0
    sta session_open

    lda #STAT_OPENING
    jsr display_status

    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @entered
    lda rbcp_zp_5
    cmp #STAGE_NOT_TAKEN
    bne @enter_refused
    lda #STAT_NO_DEVICE         ; token never moved, so nothing received it
    jmp fail
@enter_refused:
    lda #STAT_ENTER_FAIL
    jmp fail

@entered:
    lda #1
    sta session_open

    jsr rbcp_check_protocol_version
    bcc @ver_ok
    lda #STAT_VERSION
    jmp fail
@ver_ok:
    jsr read_identity

    ; GET_PIPE_CAPABILITY takes no argument bytes, so a device whose protocol
    ; version predates the Pipes group fails it and stays in step.  Carry set
    ; means no pipe here either way.
    jsr rbcp_cmd_get_pipe_capability
    bcs @no_pipe
    lda RBCP_DATA_ADDR + RBCP_PIPE_CAP_COUNT
    bne @have_pipe
@no_pipe:
    lda #STAT_NO_PIPE
    jmp fail

@have_pipe:
    lda #0                      ; pipe 0
    jsr rbcp_cmd_get_pipe_info
    bcs @pipe_dir_bad
    lda RBCP_DATA_ADDR + RBCP_PIPE_INFO_FLAGS
    and #RBCP_PIPE_FLAG_OUT
    bne @pipe_ok
@pipe_dir_bad:
    lda #STAT_PIPE_DIR
    jmp fail

@pipe_ok:
    clc
    rts

fail:
    jsr display_status
    sec
    rts

; ---------------------------------------------------------------------------
; read_identity — device type, device version and protocol version into the
; buffers display.s reads.  Each response is ASCII, null-terminated, in the
; data section.
;
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

read_identity:
    lda #0
    sta device_type_buf
    sta device_version_buf
    sta proto_ver_buf

    jsr rbcp_cmd_get_device_type
    bcs @no_type
    ldy #0
@type_loop:
    lda RBCP_DATA_ADDR, y
    sta device_type_buf, y
    beq @type_done
    iny
    cpy #24
    bne @type_loop
@type_done:
    lda #0
    sta device_type_buf + 24
@no_type:

    jsr rbcp_cmd_get_device_version
    bcs @no_ver
    ldy #0
@ver_loop:
    lda RBCP_DATA_ADDR, y
    sta device_version_buf, y
    beq @ver_done
    iny
    cpy #24
    bne @ver_loop
@ver_done:
    lda #0
    sta device_version_buf + 24
@no_ver:

    jsr rbcp_cmd_get_protocol_version
    bcs @no_proto
    lda #'R'
    sta proto_ver_buf + 0
    lda #'B'
    sta proto_ver_buf + 1
    lda #'C'
    sta proto_ver_buf + 2
    lda #'P'
    sta proto_ver_buf + 3
    lda #' '
    sta proto_ver_buf + 4
    lda RBCP_DATA_ADDR + 0
    clc
    adc #'0'
    sta proto_ver_buf + 5
    lda #'.'
    sta proto_ver_buf + 6
    lda RBCP_DATA_ADDR + 1
    clc
    adc #'0'
    sta proto_ver_buf + 7
    lda #'.'
    sta proto_ver_buf + 8
    lda RBCP_DATA_ADDR + 2
    clc
    adc #'0'
    sta proto_ver_buf + 9
    lda #0
    sta proto_ver_buf + 10
@no_proto:
    rts
