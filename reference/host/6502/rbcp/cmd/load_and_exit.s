; load_and_exit.s — LOAD_AND_EXIT
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_pause, rbcp_send_cmd

.code

; rbcp_cmd_load_and_exit: A = RAM slot, X = flash slot. Loads the flash image
; into the RAM slot and leaves command-response mode. Where the RAM slot is the
; active one this replaces the whole served image, back-channel region
; included. Send only, no polling.
;
; Terminal: the device writes no response header, so the caller must not poll.
; It returns as soon as the bytes are out, which is before the device has
; finished loading — the caller owns the wait.
;
; Since protocol 0.1.2. An older device takes the two slot numbers as the next
; frame's GROUP and CMD, so check the device's version first.
.export rbcp_cmd_load_and_exit
rbcp_cmd_load_and_exit:
    sta rbcp_arg0
    stx rbcp_arg1
    lda #RBCP_GRP_CTRL
    sta rbcp_zp_0
    lda #RBCP_CMD_LOAD_AND_EXIT
    sta rbcp_zp_1
    lda #2
    jsr rbcp_send_cmd
    jmp rbcp_pause
