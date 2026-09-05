; rbcp_stage.s — how a command failed, and how many goes a recovery gets
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; rbcp_core.s leaves one of these in rbcp_zp_5 whenever a command comes back
; with carry set.  Only the last is a device that answered at all.
;
; Nothing here is a machine's business, so a host on any machine includes it.

STAGE_NOT_TAKEN  = $01      ; the token never moved, so nothing received it
STAGE_UNFINISHED = $02      ; it was received and never completed
STAGE_REFUSED    = $03      ; the device answered and said failure
STAGE_COUNT      = 4        ; entry 0 is a stage no host names

; Goes at a reset and a re-entry before a device is given up for lost.
RECOVER_TRIES    = 3
