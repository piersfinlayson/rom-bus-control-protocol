; session.s — opening and closing the RBCP session
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything here runs with interrupts masked and the program executing from
; RAM.  Between the knock and the exit nothing may read $A000-$BFFF except the
; command page reads the protocol makes and the back-channel reads it requires.

    .include "pipe_defs.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version
.import rbcp_cmd_get_pipe_capability
.import rbcp_cmd_get_pipe_info
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_switch_and_exit
.import rbcp_cmd_get_flash_slot_info_all
.import rbcp_cmd_load_slot
.import rbcp_cmd_slot_peek
.import rbcp_send_cmd

.import display_status
.import display_device
.import display_exit_slot

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export device_type_buf
.export device_version_buf
.export proto_ver_buf
.export ram_slot_total
.export ram_slot_active
.export image_sum1
.export image_sum2
.export session_open
.export exit_slot
.export exit_flash
.export exit_slot_valid

device_type_buf:    .res 25     ; 24 ASCII bytes and a terminator
device_version_buf: .res 25
proto_ver_buf:      .res 12     ; "RBCP n.n.n" and a terminator

ram_slot_total:     .res 1
ram_slot_active:    .res 1
ram_slot_spare:     .res 1

image_sum1:         .res 1      ; Fletcher-16 of the served image, pre-knock
image_sum2:         .res 1

session_open:       .res 1      ; non-zero once ENTER_CMD_RESP has succeeded
exit_slot:          .res 1      ; RAM slot holding a verified clean image
exit_flash:         .res 1      ; flash slot it was loaded from
exit_slot_valid:    .res 1      ; zero until one has been found
flash_records:      .res 1      ; whole records the device returned
flash_types:        .res 16     ; rom_type of each, in slot index order

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; session_start — reads the image, opens the session, checks the device can do
; what this program needs.
;
; Returns carry clear armed, carry set refused, with the reason already on the
; status row.
;
; Clobbers A, X, Y, the app zero page and the RBCP arguments.
; ---------------------------------------------------------------------------

.export session_start
session_start:
    lda #0
    sta session_open
    sta exit_slot_valid

    lda #STAT_CHECKING
    jsr display_status

    ; The two bytes the device will use for progress and response.  A device
    ; writes complete only when it has finished, so an image that already holds
    ; the complete value there would let a poll read a false complete before the
    ; command had landed.  The inverses are harmless: pending and failed are
    ; what those locations are supposed to look like before anything happens.
    lda RBCP_PROGRESS_ADDR
    cmp #RBCP_COMPLETE
    beq @clash
    lda RBCP_RESPONSE_ADDR
    cmp #RBCP_STATUS_OK
    bne @image_ok
@clash:
    lda #STAT_CLASH
    jmp fail

@image_ok:
    jsr checksum_image

    lda #STAT_OPENING
    jsr display_status

    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @entered
    lda rbcp_zp_5
    cmp #1
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
    and #RBCP_PIPE_FLAG_H2D
    bne @pipe_ok
@pipe_dir_bad:
    lda #STAT_PIPE_DIR
    jmp fail

@pipe_ok:
    jsr rbcp_cmd_get_ram_slot_info_all
    bcs @slots_bad
    lda RBCP_DATA_ADDR + 0
    sta ram_slot_total
    lda RBCP_DATA_ADDR + 1
    sta ram_slot_active
    lda ram_slot_total
    cmp #2
    bcc @slots_bad

    ; The spare slot is the first that is not the active one.  It is where a
    ; pristine image is loaded and verified, and it never holds a back channel,
    ; so it is clean when it goes live.
    lda #0
    cmp ram_slot_active
    bne @spare_found
    lda #1
@spare_found:
    sta ram_slot_spare

    jsr display_device

    jsr verify_image
    bcs @no_clean
    jsr display_exit_slot
    lda #STAT_ARMED
    jsr display_status
    clc
    rts

@no_clean:
    lda #STAT_NO_CLEAN
    jmp fail

@slots_bad:
    lda #STAT_RAM_SLOTS
    ; fall through

fail:
    jsr display_status
    sec
    rts

; ---------------------------------------------------------------------------
; verify_image — finds a flash slot holding exactly the image being served.
;
; The exit switches away from the dirtied slot rather than repairing it: every
; command writes the response header, and the header lives in the active slot,
; so the served image is dirty from the first command and the write that would
; restore it would be a command in its turn.  A slot that has never held a back
; channel is clean when it goes live, and SWITCH_AND_EXIT writes no header.
;
; Each candidate is loaded into the spare RAM slot and read back with
; SLOT_PEEK, because an inactive slot is not mapped anywhere the host can see.
; Its Fletcher pair is compared with the one taken from $A000-$BFFF before the
; knock.
;
; About 8 ms a peek and 32 peeks a slot, so a quarter of a second per candidate,
; paid once.
;
; Returns carry clear with exit_slot and exit_flash set, or carry set if no
; slot matches — in which case there is no clean way out and the program will
; not arm.
;
; Clobbers A, X, Y, the app zero page and the RBCP arguments.
; ---------------------------------------------------------------------------

verify_image:
    lda #0
    sta exit_slot_valid

    lda #STAT_VERIFYING
    jsr display_status

    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @none

    lda RBCP_DATA_ADDR + 1          ; whole records returned
    cmp #17
    bcc @count_ok
    lda #16
@count_ok:
    sta flash_records
    beq @none

    ; The rom_type is the first byte of each 32 byte record, and the records
    ; start four bytes into the data section.  Record 8 is already 260 bytes in,
    ; past what an 8 bit index reaches, so this walks a pointer rather than
    ; indexing from the base.
    lda #<(RBCP_DATA_ADDR + 4)
    sta ZP_APP0
    lda #>(RBCP_DATA_ADDR + 4)
    sta ZP_APP1
    ldx #0
@types:
    ldy #0
    lda (ZP_APP0), y
    sta flash_types, x
    lda ZP_APP0
    clc
    adc #32
    sta ZP_APP0
    bcc @no_carry
    inc ZP_APP1
@no_carry:
    inx
    cpx flash_records
    bne @types

    lda #0
    sta ZP_APP6                     ; candidate flash slot
@candidate:
    ldx ZP_APP6
    lda flash_types, x
    cmp #ROM_TYPE_2364
    bne @next

    lda ram_slot_spare
    ldx ZP_APP6
    jsr rbcp_cmd_load_slot
    bcs @next

    jsr fold_spare_slot
    bcs @next

    lda ZP_APP2
    cmp image_sum1
    bne @next
    lda ZP_APP3
    cmp image_sum2
    bne @next

    lda ram_slot_spare
    sta exit_slot
    lda ZP_APP6
    sta exit_flash
    lda #1
    sta exit_slot_valid
    clc
    rts

@next:
    inc ZP_APP6
    lda ZP_APP6
    cmp flash_records
    bne @candidate
@none:
    sec
    rts

; ---------------------------------------------------------------------------
; fold_spare_slot — reads the spare RAM slot back 256 bytes at a time and folds
; the whole image into ZP_APP2 and ZP_APP3.
;
; Returns carry set if the device refused a read.
; Clobbers A, X, Y and the app zero page above ZP_APP1.
; ---------------------------------------------------------------------------

fold_spare_slot:
    lda #0
    sta ZP_APP2
    sta ZP_APP3
    sta ZP_APP5                     ; page within the slot
@page:
    lda #0
    sta rbcp_arg0                   ; count 0 means 256 bytes
    sta rbcp_arg1                   ; address low
    sta rbcp_arg3                   ; address high
    lda ZP_APP5
    sta rbcp_arg2                   ; address middle, so page * 256
    lda ram_slot_spare
    sta rbcp_arg4
    jsr rbcp_cmd_slot_peek
    bcs @fail

    ldy #0                          ; 0 means 256 to checksum_fold too
    jsr checksum_fold

    inc ZP_APP5
    lda ZP_APP5
    cmp #(CONFIG_ROM_SIZE / $100)
    bne @page
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; session_end — leaves command-response mode.
;
; With a verified clean slot this switches to it, which is the only exit that
; leaves the served image byte-perfect: that slot has never held a back channel
; and SWITCH_AND_EXIT writes no response header.
;
; With no verified slot it exits silently and says so.  A silent exit is the
; only other one that adds no further header write, so it leaves the image
; dirty in the eight header bytes and no worse.
;
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

.export session_end
session_end:
    lda session_open
    beq @done
    lda exit_slot_valid
    beq @silent

    lda exit_slot
    jsr rbcp_cmd_switch_and_exit
    lda #0
    sta session_open
    rts

@silent:
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_EXIT_CMD_RESP_SILENT
    sta rbcp_zp_1
    lda #0
    jsr rbcp_send_cmd
    lda #0
    sta session_open
    lda #STAT_DIRTY_EXIT
    jsr display_status
@done:
    rts

; ---------------------------------------------------------------------------
; read_identity — device type, device version and protocol version into the
; buffers display.s reads.  Each response is ASCII, null-terminated, in the
; data section.
;
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

read_identity:
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

; ---------------------------------------------------------------------------
; checksum_image — Fletcher-16 over the whole served image, read as ordinary
; data before the knock.
;
; A linear sweep cannot form a knock: it produces consecutive low address
; bytes, and the knock is six specific non-consecutive ones.
;
; Fletcher rather than a plain sum because a plain sum cannot see a
; transposition, and the check exists to tell a pristine image from a variant
; of the same one.  Both accumulators are mod 255, which on a 6502 is an adc
; followed by adc #0 to fold the carry back in.
;
; 30 cycles a byte over 8192 bytes, about 250 ms, paid once.
;
; Result in image_sum1 and image_sum2.  Clobbers A, Y and the app zero page.
; ---------------------------------------------------------------------------

.export checksum_image
checksum_image:
    lda #0
    sta image_sum1
    sta image_sum2
    sta ZP_APP0
    lda #CONFIG_ROM_BASE_HI
    sta ZP_APP1
    ldx #(CONFIG_ROM_SIZE / $100)
@page:
    ldy #0
@byte:
    lda (ZP_APP0), y
    clc
    adc image_sum1
    adc #0                      ; fold the carry: 256 mod 255 is 1
    sta image_sum1
    clc
    adc image_sum2
    adc #0
    sta image_sum2
    iny
    bne @byte
    inc ZP_APP1
    dex
    bne @page
    rts

; ---------------------------------------------------------------------------
; checksum_fold — folds count bytes at RBCP_DATA_ADDR into a running Fletcher
; pair held in ZP_APP2 and ZP_APP3.  Used to check a slot read back through
; SLOT_PEEK against the image read before the knock.
;
; Y = count on entry, 0 meaning 256.  Clobbers A, Y.
; ---------------------------------------------------------------------------

.export checksum_fold
checksum_fold:
    sty ZP_APP4
    ldy #0
@byte:
    lda RBCP_DATA_ADDR, y
    clc
    adc ZP_APP2
    adc #0
    sta ZP_APP2
    clc
    adc ZP_APP3
    adc #0
    sta ZP_APP3
    iny
    cpy ZP_APP4
    bne @byte
    rts
