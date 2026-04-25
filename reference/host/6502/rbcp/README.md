# 6502 RBCP Host Routines

This directory contains generic 6502 assembly routines for communicating with an RBCP device. These can be used as building blocks for implementing an RBCP host on any 6502-based system.

For a complete example of an RBCP host implementation on a real 6502-based system, see the [C64 kernal bootloader](../c64-boot/README.md).

For a list of the routines, see the exported symbols in [`rbcp.s`](rbcp.s).

To configure the RBCP implementation's settings for a particular platform, you must provide an `rbcp_config.s` file with the appropriate definitions.  See [`sample_rbcp_config.s`](sample_rbcp_config.s).

## Example Usage

An example usage of this library is provided below.  This example is for a 6502 based platform, running as the device's primary firmware, loaded at the top of the 6502's address space.  It loads a new ROM image from flash to an unused RAM slot, enables it, then jumps to its reset vector.  This can be the basis for a firmware bootloader.

For a fuller implementation, see the [C64 kernal bootloader](../c64-boot/README.md), which implements this example on a real C64 with One ROM and its RBCP plugin, and includes additional features such as displaying device and ROM information on the screen, and allowing the user to select from multiple ROM images in flash.

In addition to the code below, an `rbcp_config.s` file must be provided with the appropriate configuration for the platform.  See [`sample_rbcp_config.s`](sample_rbcp_config.s) for an example.

```asm
; Required imports
.import rbcp_reset
.import rbcp_cmd_config_and_enter_cmd_resp
.import rbcp_cmd_load_slot
.import rbcp_cmd_switch_and_exit

start:
    ; Perform any platform or application specific initialization here, such
    ; as setting up the stack pointer, initializing RAM, copying the code
    ; below to RAM, etc.
    ...

; This code MUST execute from RAM, not from ROM, as the RBCP device interprets
; reads from ROM as commands.
start_from_ram:
    ; Disable interrupts - this is important for reliable RBCP operation, as
    ; interrupts will cause reads from the ROM that the RBCP device will
    ; interpret as commands.
    sei

    ; Reset the device's RBCP implemenation, to ensure it's in a known state
    ; before attempting to communicate.
    jsr rbcp_reset

    ; Put the device into command-respond mode, with a 512-byte back channel, at
    ; the start of the currently loaded ROM image.
    lda #RBCP_LOCATION_START
    sta rbcp_arg0
    lda #RBCP_SIZE_512
    sta rbcp_arg1
    jsr rbcp_cmd_config_and_enter_cmd_resp
    bcc @ok_enter
    jmp halt        ; Hit error entering command response mode

    ; Check the device's RBCP protocol version is compatible with this library.
@ok_enter:
    jsr rbcp_check_protocol_version
    bcc @ok_version
    jmp halt        ; Incompatible protocol version

    ; This example obviates the calls to find out which RAM slots are free, and
    ; what kernal images are available in flash.  For simplicity it assumes RAM
    ; slot 1 is free, and flash slot 1 contains the desired ROM image.

    ; Load another ROM image from flash to an unused RAM slot
@ok_version:
    lda #1          ; RAM slot
    ldx #1          ; Flash slot
    jsr rbcp_cmd_load_slot
    bcc @ok_load
    jmp halt        ; Hit error loading slot

    ; Switch to the new RAM slot and exit command-respond mode, which will
    ; cause the device to start executing from the new RAM slot.
@ok_load:
    lda #1          ; RAM slot to switch to
    jsr rbcp_cmd_switch_and_exit

    ; Now jump to the reset vector for the newly loaded ROM image.
    jmp ($FFFC)     ; 6502 reset vector

halt:
    jmp halt
```