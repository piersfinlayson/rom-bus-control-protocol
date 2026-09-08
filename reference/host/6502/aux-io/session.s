; session.s — opening the tester's session, and what the reset screen needs
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The tester is a ROM.  It owns the machine from reset and the image it is
; running out of is its own, so there is no exit to repair and none of the
; apparatus common/rbcp_session.s carries for one — the image checksum, the
; hunt for a flash slot holding a pristine copy, the SLOT_PEEK verification,
; the switch on the way out.
;
; What is left is the knock, command-response mode, the version check, the
; three strings the device calls itself, and the flash slots, because the
; reset screen offers a choice of what the machine comes back as.

    .include "auxio_defs.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version
.import rbcp_cmd_get_flash_slot_info_all
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_load_slot

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export sess_slot
.export sess_gone
.export sess_can_switch
.export sess_dev_type
.export sess_dev_ver
.export sess_proto
.export sess_flash_count
.export sess_flash_types
.export sess_flash_name

spare_slot:     .res 1          ; the RAM slot an image is loaded into
sess_slot:      .res 1          ; the slot a switch-and-exit should activate
sess_gone:      .res 1          ; a terminal command has been issued

; Zero where the device has only one RAM slot.  There is then nowhere to put
; the image the reset screen would switch to, so the screen says so instead of
; offering a choice that cannot be taken.
sess_can_switch: .res 1

; What the device calls itself.  Read once, while the session is opening, and
; drawn from here afterwards.  A device that has stopped answering will not
; answer a question about its own name either.
sess_dev_type:  .res 25
sess_dev_ver:   .res 25
sess_proto:     .res 12

; The flash slots.  Only the name of the slot being looked at is held — all of
; them at once would not fit the back channel in one reply anyway.
sess_flash_count: .res 1
sess_flash_types: .res 16
sess_flash_name:  .res 32

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; sess_open — knocks, enters command-response mode, checks the protocol
; version, reads the device's identity and lists its flash slots.
;
; Carry clear open, carry set refused with a FAIL_ code in A.
; ---------------------------------------------------------------------------

.export sess_open
sess_open:
    lda #0
    sta sess_gone
    sta sess_can_switch

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
    jsr find_spare
    jsr read_flash_types
    clc
    rts

; ---------------------------------------------------------------------------
; find_spare — the first RAM slot that is not the active one.  A device with
; only one has none, and sess_can_switch stays clear.
; Clobbers A.
; ---------------------------------------------------------------------------

find_spare:
    jsr rbcp_cmd_get_ram_slot_info_all
    bcs @none
    lda RBCP_DATA_ADDR + 0      ; slots the device has
    cmp #2
    bcc @none
    lda #0
    cmp RBCP_DATA_ADDR + 1      ; the active one
    bne @found
    lda #1
@found:
    sta spare_slot
    lda #1
    sta sess_can_switch
@none:
    rts

; ---------------------------------------------------------------------------
; sess_mark_gone — the session is over and no further command may be sent.
; Called by an application that has issued a terminal command.  Clobbers A.
; ---------------------------------------------------------------------------

.export sess_mark_gone
sess_mark_gone:
    lda #1
    sta sess_gone
    rts

; ---------------------------------------------------------------------------
; sess_load — A = flash slot.  Loads it into the spare RAM slot, so that a
; caller about to switch there has something to switch to, and puts that slot
; in sess_slot.
; Carry set if the device refused, or if there is no spare slot.
; ---------------------------------------------------------------------------

.export sess_load
sess_load:
    ldy sess_can_switch
    beq @fail
    tax
    lda spare_slot
    jsr rbcp_cmd_load_slot
    bcs @fail
    lda spare_slot
    sta sess_slot
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; read_flash_types — the rom_type of every flash slot.
; Clobbers A, X, Y and ZP_APP0 and ZP_APP1.
; ---------------------------------------------------------------------------

read_flash_types:
    lda #0
    sta sess_flash_count
    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @none

    lda RBCP_DATA_ADDR + 1          ; whole records returned
    cmp #17
    bcc @count_ok
    lda #16
@count_ok:
    sta sess_flash_count
    beq @none

    lda #<(RBCP_DATA_ADDR + 4)
    sta ZP_APP0
    lda #>(RBCP_DATA_ADDR + 4)
    sta ZP_APP1
    ldx #0
@types:
    ldy #0
    lda (ZP_APP0), y
    sta sess_flash_types, x
    lda ZP_APP0
    clc
    adc #32
    sta ZP_APP0
    bcc @no_carry
    inc ZP_APP1
@no_carry:
    inx
    cpx sess_flash_count
    bne @types
@none:
    rts

; ---------------------------------------------------------------------------
; sess_read_flash_name — A = flash slot.  Copies that slot's name into
; sess_flash_name, from a fresh GET_FLASH_SLOT_INFO_ALL.
;
; The records are 32 bytes each starting four bytes into the data section, so
; record 8 is already past what an eight bit index reaches.  This walks a
; pointer rather than indexing from the base.
;
; Carry set if the device refused, in which case the name is emptied rather
; than left as the last slot's.
; ---------------------------------------------------------------------------

.export sess_read_flash_name
sess_read_flash_name:
    sta ZP_APP6
    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @fail

    lda #<(RBCP_DATA_ADDR + 4)
    sta ZP_APP0
    lda #>(RBCP_DATA_ADDR + 4)
    sta ZP_APP1
    ldx ZP_APP6
    beq @at_record
@walk:
    lda ZP_APP0
    clc
    adc #32
    sta ZP_APP0
    bcc @no_carry
    inc ZP_APP1
@no_carry:
    dex
    bne @walk
@at_record:
    ldy #1                      ; the name starts one byte into the record
    ldx #0
@copy:
    lda (ZP_APP0), y
    sta sess_flash_name, x
    beq @done
    iny
    inx
    cpx #30
    bne @copy
@done:
    lda #0
    sta sess_flash_name + 30
    clc
    rts
@fail:
    lda #0
    sta sess_flash_name
    sec
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
