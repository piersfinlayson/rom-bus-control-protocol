; pins_dev.s — the pins.s interface, against a real device
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything here runs with interrupts masked and the program executing from
; RAM.  Between the knock and the exit nothing may read $A000-$BFFF except the
; command page reads the protocol makes and the back-channel reads it requires.
; That is why the image checksum is taken before the knock and never again.
;
; The exit
; --------
; Every command writes the response header, and the header lives in the active
; slot, so the served image is dirty from the first command onwards.  The way
; out is not to repair it — the write that would repair it is itself a command
; — but to switch to a slot that has never held a back channel.  So this file
; finds a flash slot holding exactly the image being served, loads it into a
; spare RAM slot and checks it byte for byte, and keeps that slot for the exit.
; Without one there is no clean way out and the program refuses to start.
;
; This file has never run.  There is no 6502 emulator here and the demo build
; deliberately does not exercise it: hardware is the only thing that can.

    .include "aux_defs.s"

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
.import pins_slot
.import pins_truncated
.import pins_gone
.import pins_dev_type
.import pins_dev_ver
.import pins_proto
.import pins_flash_count
.import pins_flash_types
.import pins_flash_name

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export dev_spare_slot
.export dev_exit_slot

session_open:   .res 1          ; non-zero once ENTER_CMD_RESP has succeeded
image_sum1:     .res 1          ; Fletcher-16 of the served image, pre-knock
image_sum2:     .res 1

ram_total:      .res 1
ram_active:     .res 1
dev_spare_slot: .res 1          ; the RAM slot this program loads into
dev_exit_slot:  .res 1          ; a RAM slot holding a verified clean image
exit_valid:     .res 1

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
    sta session_open
    sta exit_valid
    sta pins_truncated
    sta pins_gone

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
    lda #FAIL_CLASH
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
    lda #FAIL_NO_DEVICE         ; token never moved, so nothing received it
    sec
    rts
@enter_refused:
    lda #FAIL_ENTER
    sec
    rts

@entered:
    lda #1
    sta session_open

    jsr rbcp_check_protocol_version
    bcc @ver_ok
    lda #FAIL_VERSION
    sec
    rts
@ver_ok:
    jsr read_identity

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
    lda #FAIL_RAM_SLOTS
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
    sta dev_spare_slot

    jsr read_flash_types
    jsr verify_image
    bcc @clean
    lda #FAIL_NO_CLEAN
    sec
    rts
@clean:
    jsr pins_scan_all
    bcc @done
    lda #FAIL_NO_DEVICE
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
    jmp mark_gone

; ---------------------------------------------------------------------------
; pins_switch_exit — as pins_set_exit, and activates pins_slot as well.
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
    lda pins_slot
    sta rbcp_arg6
    jsr rbcp_cmd_set_aux_switch_exit
    jmp mark_gone

mark_gone:
    lda #1
    sta pins_gone
    lda #0
    sta session_open
    rts

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
; pins_close — leaves command-response mode.
;
; With a verified clean slot this switches to it, which is the only exit that
; leaves the served image byte-perfect: that slot has never held a back channel
; and SWITCH_AND_EXIT writes no response header.
;
; With no verified slot it exits silently.  A silent exit is the only other one
; that adds no further header write, so it leaves the image dirty in the bytes
; already written and no worse.
; ---------------------------------------------------------------------------

.export pins_close
pins_close:
    lda session_open
    beq @done
    lda exit_valid
    beq @silent
    lda dev_exit_slot
    jsr rbcp_cmd_switch_and_exit
    jmp mark_gone
@silent:
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_EXIT_CMD_RESP_SILENT
    sta rbcp_zp_1
    lda #0
    jsr rbcp_send_cmd
    jmp mark_gone
@done:
    rts

; ---------------------------------------------------------------------------
; pins_load — A = flash slot.  Loads it into the spare RAM slot, so that a
; caller about to switch there has something to switch to.
; Carry set if the device refused.
; ---------------------------------------------------------------------------

.export pins_load
pins_load:
    tax
    lda dev_spare_slot
    jsr rbcp_cmd_load_slot
    bcs @fail
    lda dev_spare_slot
    sta pins_slot
    clc
    rts
@fail:
    sec
    rts

; ---------------------------------------------------------------------------
; pins_read_flash_name — A = flash slot.  Copies that slot's name into
; pins_flash_name, from a fresh GET_FLASH_SLOT_INFO_ALL.
;
; The records are 32 bytes each starting four bytes into the data section, so
; record 8 is already past what an eight bit index reaches.  This walks a
; pointer rather than indexing from the base.
;
; Carry set if the device refused, in which case the name is emptied rather
; than left as the last slot's.
; ---------------------------------------------------------------------------

.export pins_read_flash_name
pins_read_flash_name:
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
    sta pins_flash_name, x
    beq @done
    iny
    inx
    cpx #30
    bne @copy
@done:
    lda #0
    sta pins_flash_name + 30
    clc
    rts
@fail:
    lda #0
    sta pins_flash_name
    sec
    rts

; ---------------------------------------------------------------------------
; read_flash_types — the rom_type of every flash slot, kept because the reset
; screen has to know which slots hold an image this machine could boot.
; Clobbers A, X, Y and the app zero page.
; ---------------------------------------------------------------------------

read_flash_types:
    lda #0
    sta pins_flash_count
    jsr rbcp_cmd_get_flash_slot_info_all
    bcs @none

    lda RBCP_DATA_ADDR + 1          ; whole records returned
    cmp #17
    bcc @count_ok
    lda #16
@count_ok:
    sta pins_flash_count
    beq @none

    lda #<(RBCP_DATA_ADDR + 4)
    sta ZP_APP0
    lda #>(RBCP_DATA_ADDR + 4)
    sta ZP_APP1
    ldx #0
@types:
    ldy #0
    lda (ZP_APP0), y
    sta pins_flash_types, x
    lda ZP_APP0
    clc
    adc #32
    sta ZP_APP0
    bcc @no_carry
    inc ZP_APP1
@no_carry:
    inx
    cpx pins_flash_count
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
; Carry clear with dev_exit_slot set, or carry set if no slot matches.
; ---------------------------------------------------------------------------

verify_image:
    lda #0
    sta exit_valid
    lda pins_flash_count
    beq @none

    lda #0
    sta ZP_APP6                     ; candidate flash slot
@candidate:
    ldx ZP_APP6
    lda pins_flash_types, x
    cmp #ROM_TYPE_2364
    bne @next

    lda ZP_APP6
    jsr pins_load
    bcs @next

    jsr fold_spare_slot
    bcs @next

    lda ZP_APP2
    cmp image_sum1
    bne @next
    lda ZP_APP3
    cmp image_sum2
    bne @next

    lda dev_spare_slot
    sta dev_exit_slot
    lda #1
    sta exit_valid
    clc
    rts
@next:
    inc ZP_APP6
    lda ZP_APP6
    cmp pins_flash_count
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
    lda dev_spare_slot
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
; buffers display.s reads.  Each response is ASCII, null-terminated, in the
; data section.
; ---------------------------------------------------------------------------

read_identity:
    jsr rbcp_cmd_get_device_type
    bcs @no_type
    ldy #0
@type_loop:
    lda RBCP_DATA_ADDR, y
    sta pins_dev_type, y
    beq @type_done
    iny
    cpy #24
    bne @type_loop
@type_done:
    lda #0
    sta pins_dev_type + 24
@no_type:

    jsr rbcp_cmd_get_device_version
    bcs @no_ver
    ldy #0
@ver_loop:
    lda RBCP_DATA_ADDR, y
    sta pins_dev_ver, y
    beq @ver_done
    iny
    cpy #24
    bne @ver_loop
@ver_done:
    lda #0
    sta pins_dev_ver + 24
@no_ver:

    jsr rbcp_cmd_get_protocol_version
    bcs @no_proto
    lda #'R'
    sta pins_proto + 0
    lda #'B'
    sta pins_proto + 1
    lda #'C'
    sta pins_proto + 2
    lda #'P'
    sta pins_proto + 3
    lda #' '
    sta pins_proto + 4
    lda RBCP_DATA_ADDR + 0
    clc
    adc #'0'
    sta pins_proto + 5
    lda #'.'
    sta pins_proto + 6
    lda RBCP_DATA_ADDR + 1
    clc
    adc #'0'
    sta pins_proto + 7
    lda #'.'
    sta pins_proto + 8
    lda RBCP_DATA_ADDR + 2
    clc
    adc #'0'
    sta pins_proto + 9
    lda #0
    sta pins_proto + 10
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

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

all_grp:        .res 1
