; rbcp_session.s — opening an RBCP session from a C64, and leaving the served
; ROM as it was found
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything here runs with interrupts masked and the program executing from
; RAM.  Between the knock and the exit nothing may read the served ROM except
; the command page reads the protocol makes and the back-channel reads it
; requires.  That is why the image checksum is taken before the knock and never
; again.
;
; The exit
; --------
; Every command writes the response header, and the header lives in the active
; slot, so the served image is dirty from the first command onwards.  The way
; out is not to repair it — the write that would repair it is itself a command
; — but to switch to a slot that has never held a back channel.  So this file
; finds a flash slot holding exactly the image being served, loads it into a
; spare RAM slot and checks it byte for byte, and keeps that slot for the exit.
; Without one there is no clean way out and the caller is refused.
;
; This file has never run.  There is no 6502 emulator here that speaks RBCP and
; the demo builds deliberately do not exercise it: hardware is the only thing
; that can.
;
; What the application must define in its rbcp_config.s, beyond what the RBCP
; library needs: CONFIG_ROM_TYPE, the spec's ROM type code for the image being
; served.  Only flash slots reporting that type are candidates.

    .include "app_defs.s"

.import rbcp_reset
.import rbcp_send_cmd
.import rbcp_cmd_enter_cmd_resp
.import rbcp_check_protocol_version
.import rbcp_cmd_get_device_type
.import rbcp_cmd_get_device_version
.import rbcp_cmd_get_protocol_version
.import rbcp_cmd_get_ram_slot_info_all
.import rbcp_cmd_get_flash_slot_info_all
.import rbcp_cmd_load_slot
.import rbcp_cmd_slot_peek
.import rbcp_cmd_switch_and_exit

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

opened:         .res 1          ; non-zero once ENTER_CMD_RESP has succeeded
exit_valid:     .res 1
image_sum1:     .res 1          ; Fletcher-16 of the served image, pre-knock
image_sum2:     .res 1

ram_total:      .res 1
ram_active:     .res 1
sess_spare_slot: .res 1         ; the RAM slot this program loads into
sess_exit_slot:  .res 1         ; a RAM slot holding a verified clean image
sess_slot:       .res 1         ; the slot a switch-and-exit should activate
sess_gone:       .res 1         ; a terminal command has been issued

; What the device calls itself.  Read once, while the session is opening.
sess_dev_type:  .res 25
sess_dev_ver:   .res 25
sess_proto:     .res 12

; The flash slots, because a program offering a choice of what the machine
; comes back as has to know which slots hold an image it could boot.  Only the
; name of the slot being looked at is held — all of them at once would not fit
; the back channel in one reply anyway.
sess_flash_count: .res 1
sess_flash_types: .res 16
sess_flash_name:  .res 32

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; sess_open — knocks, enters command-response mode, reads the device's
; identity, finds a clean exit and leaves the session open.
;
; Carry clear open, carry set refused with a SESS_FAIL_ code in A.
; ---------------------------------------------------------------------------

.export sess_open
sess_open:
    lda #0
    sta opened
    sta exit_valid
    sta sess_gone

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
    lda #SESS_FAIL_CLASH
    sec
    rts

@image_ok:
    jsr checksum_image

    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @entered
    lda rbcp_zp_5
    cmp #1
    bne @enter_refused
    lda #SESS_FAIL_NO_DEVICE     ; token never moved, so nothing received it
    sec
    rts
@enter_refused:
    lda #SESS_FAIL_ENTER
    sec
    rts

@entered:
    lda #1
    sta opened

    jsr rbcp_check_protocol_version
    bcc @ver_ok
    lda #SESS_FAIL_VERSION
    sec
    rts
@ver_ok:
    jsr read_identity

    jsr rbcp_cmd_get_ram_slot_info_all
    bcs @slots_bad
    lda RBCP_DATA_ADDR + 0
    sta ram_total
    lda RBCP_DATA_ADDR + 1
    sta ram_active
    lda ram_total
    cmp #2
    bcs @slots_ok
@slots_bad:
    lda #SESS_FAIL_RAM_SLOTS
    sec
    rts
@slots_ok:
    ; The spare slot is the first that is not the active one.  It is where a
    ; pristine image is loaded and verified, and it never holds a back channel,
    ; so it is clean when it goes live.
    lda #0
    cmp ram_active
    bne @spare_found
    lda #1
@spare_found:
    sta sess_spare_slot

    jsr read_flash_types
    jsr verify_image
    bcc @clean
    lda #SESS_FAIL_NO_CLEAN
    sec
    rts
@clean:
    clc
    rts

; ---------------------------------------------------------------------------
; sess_close — leaves whatever mode was entered.
;
; The clean exit is a switch to the verified slot, which activates an image
; that has never held a back channel and writes no response header on the way.
; Without one, a silent exit: the served image stays dirty, but it is already
; written and no worse.
; ---------------------------------------------------------------------------

.export sess_close
sess_close:
    lda opened
    beq @done
    lda sess_gone
    bne @done
    lda exit_valid
    beq @silent
    lda sess_exit_slot
    jsr rbcp_cmd_switch_and_exit
    jmp sess_mark_gone
@silent:
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_EXIT_CMD_RESP_SILENT
    sta rbcp_zp_1
    lda #0
    jsr rbcp_send_cmd
    jmp sess_mark_gone
@done:
    rts

; ---------------------------------------------------------------------------
; sess_mark_gone — the session is over and no further command may be sent.
; Called by this file, and by an application that has issued a terminal command
; of its own.  Clobbers A.
; ---------------------------------------------------------------------------

.export sess_mark_gone
sess_mark_gone:
    lda #1
    sta sess_gone
    lda #0
    sta opened
    rts

; ---------------------------------------------------------------------------
; sess_load — A = flash slot.  Loads it into the spare RAM slot, so that a
; caller about to switch there has something to switch to, and puts that slot
; in sess_slot.
; Carry set if the device refused.
; ---------------------------------------------------------------------------

.export sess_load
sess_load:
    tax
    lda sess_spare_slot
    jsr rbcp_cmd_load_slot
    bcs @fail
    lda sess_spare_slot
    sta sess_slot
    clc
    rts
@fail:
    sec
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
; read_flash_types — the rom_type of every flash slot.
; Clobbers A, X, Y and the app zero page.
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
; verify_image — finds a flash slot holding exactly the image being served.
;
; Each candidate is loaded into the spare RAM slot and read back with
; SLOT_PEEK, because an inactive slot is not mapped anywhere the host can see.
; Its Fletcher pair is compared with the one taken from the served image before
; the knock.
;
; About 8ms a peek and 32 peeks a slot, so a quarter of a second per candidate,
; paid once at startup.
;
; Carry clear with sess_exit_slot set, or carry set if no slot matches.
; ---------------------------------------------------------------------------

verify_image:
    lda #0
    sta exit_valid
    lda sess_flash_count
    beq @none

    lda #0
    sta ZP_APP6                     ; candidate flash slot
@candidate:
    ldx ZP_APP6
    lda sess_flash_types, x
    cmp #CONFIG_ROM_TYPE
    bne @next

    lda ZP_APP6
    jsr sess_load
    bcs @next

    jsr fold_spare_slot
    bcs @next

    lda ZP_APP2
    cmp image_sum1
    bne @next
    lda ZP_APP3
    cmp image_sum2
    bne @next

    lda sess_spare_slot
    sta sess_exit_slot
    lda #1
    sta exit_valid
    clc
    rts
@next:
    inc ZP_APP6
    lda ZP_APP6
    cmp sess_flash_count
    bne @candidate
@none:
    sec
    rts

; ---------------------------------------------------------------------------
; fold_spare_slot — reads the spare RAM slot back 256 bytes at a time and folds
; the whole image into ZP_APP2 and ZP_APP3.
; Carry set if the device refused a read.
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
    lda sess_spare_slot
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
; read_identity — device type, device version and protocol version into the
; buffers a display reads.  Each response is ASCII, null-terminated, in the
; data section.
; ---------------------------------------------------------------------------

read_identity:
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
; 30 cycles a byte over 8192 bytes, about 250ms, paid once.
; ---------------------------------------------------------------------------

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
; pair held in ZP_APP2 and ZP_APP3.
; Y = count on entry, 0 meaning 256.  Clobbers A, Y.
; ---------------------------------------------------------------------------

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
