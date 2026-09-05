; rbcp_recover.s — putting a device that has stopped answering back together
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; rbcp_reset's first stage is five RESET frames with no knock, and its job is
; to flush a partially received command of up to nine argument bytes and two
; framing bytes.  A frame that slipped by a byte and landed on a command taking
; arguments leaves the device waiting for exactly that, and one that landed on
; a silent exit leaves it out of command-response mode altogether.  The reset
; covers both, and RBCP_RESET changes no slot contents and no active slot, so a
; verified exit slot survives it.
;
; Command-response mode is entered again rather than the session opened from
; scratch.  The rest of opening a session is about deciding whether to talk to
; the device at all, and that was settled before anything called this.
;
; The sequence is all this holds.  What a host counts, and what it does to its
; own flags either way, stays with the host, because those differ between one
; host and the next while the sequence does not.

    .include "rbcp_stage.s"

.import rbcp_reset
.import rbcp_cmd_enter_cmd_resp

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

try_left:   .res 1

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; rbcp_recover — RECOVER_TRIES goes at a reset followed by a re-entry.
;
; Carry clear back in command-response mode, carry set gave up.
; Clobbers A, X, Y and the RBCP arguments.
; ---------------------------------------------------------------------------

.export rbcp_recover
rbcp_recover:
    lda #RECOVER_TRIES
    sta try_left
@try:
    jsr rbcp_reset
    jsr rbcp_cmd_enter_cmd_resp
    bcc @back
    dec try_left
    bne @try
    sec
    rts
@back:
    clc
    rts
