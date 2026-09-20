; amiga_time.s — the beam and the time of day counter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  The beam says where in the field the display is, and the
; CIA-B counter runs whether or not anything is watching it.

; ---------------------------------------------------------------------------
; beam_line — D0.W = the beam's line, all nine bits of it.  VPOSR carries the
; top bit and VHPOSR the rest, and a long read takes both at once.
; Clobbers: nothing beyond the return
; ---------------------------------------------------------------------------
beam_line:
        MOVE.L  (VPOSR).L,D0
        LSR.L   #8,D0
        ANDI.W  #$01FF,D0
        RTS

; ---------------------------------------------------------------------------
; tod_now — D0.L = the CIA-B time of day counter, 24 bits.
;
; Reading the high byte latches all three so the value cannot tear, and
; reading the low byte lets it go again.
; Clobbers: nothing
; ---------------------------------------------------------------------------
tod_now:
        MOVEM.L D1,-(SP)
        MOVEQ   #0,D0
        MOVE.B  (CIAB_TODHI).L,D0
        LSL.L   #8,D0
        MOVE.B  (CIAB_TODMID).L,D0
        LSL.L   #8,D0
        MOVE.B  (CIAB_TODLO).L,D0
        ANDI.L  #$00FFFFFF,D0
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; tod_start — set the counter going from zero.
;
; Writing the low byte starts it, and the high byte must be written
; first.  CRB bit 7 clear means the writes go to the counter and not the alarm.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
tod_start:
        MOVEM.L D0,-(SP)
        MOVE.B  (CIAB_CRB).L,D0
        ANDI.B  #$7F,D0
        MOVE.B  D0,(CIAB_CRB).L
        CLR.B   (CIAB_TODHI).L
        CLR.B   (CIAB_TODMID).L
        CLR.B   (CIAB_TODLO).L          ; this one starts it
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; wait_field — hold until the beam next leaves the display.  Chip registers
; only, so no ROM is read while it waits.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
wait_field:
        MOVEM.L D0,-(SP)
.wf_below:
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCC.S   .wf_below               ; still past it from last time
.wf_reach:
        BSR     beam_line
        CMP.W   VAR_TICK_LINE,D0
        BCS.S   .wf_reach
        MOVEM.L (SP)+,D0
        RTS
