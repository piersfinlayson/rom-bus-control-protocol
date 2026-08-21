; check_protocol_version.s — the version check helpers
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_cmd_get_protocol_version

.code

.export rbcp_check_protocol_version
.export rbcp_check_protocol_version_min

; rbcp_check_protocol_version: checks host's RBCP implementation version
; against this library's supported version.
; Output: carry clear = compatible, carry set = incompatible
rbcp_check_protocol_version:
    lda #RBCP_SUPPORTED_PROTOCOL_MAJOR
    sta rbcp_arg0
    lda #RBCP_SUPPORTED_PROTOCOL_MINOR
    sta rbcp_arg1
    lda #RBCP_SUPPORTED_PROTOCOL_PATCH
    sta rbcp_arg2
    ; fall through

; rbcp_check_protocol_version_min: checks hosts' RBCP implemenation verrsion
; against caller-supplied minimum
; Input: rbcp_arg0 = minimum major, rbcp_arg1 = minimum minor, rbcp_arg2 = minimum patch
; Output: carry clear = compatible, carry set = incompatible
rbcp_check_protocol_version_min:
    jsr rbcp_cmd_get_protocol_version
    bcs @fail

    lda RBCP_DATA_ADDR + 0      ; major must match exactly
    cmp rbcp_arg0
    bne @fail

    lda rbcp_arg0               ; which rule set?
    bne @major_nonzero

    ; major == 0: minor exact, patch >=
    lda RBCP_DATA_ADDR + 1
    cmp rbcp_arg1
    bne @fail
    lda RBCP_DATA_ADDR + 2
    cmp rbcp_arg2
    bcc @fail
    clc
    rts

@major_nonzero:
    lda RBCP_DATA_ADDR + 1      ; device minor >= expected minor
    cmp rbcp_arg1
    bcc @fail
    bne @ok                     ; device minor > expected, patch irrelevant
    lda RBCP_DATA_ADDR + 2      ; minor equal, check patch >=
    cmp rbcp_arg2
    bcc @fail
@ok:
    clc
    rts
@fail:
    sec
    rts
