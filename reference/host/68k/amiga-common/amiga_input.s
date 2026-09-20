; amiga_input.s — keyboard and mouse buttons
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  Each routine polls once and waits for nothing.

; ---------------------------------------------------------------------------
; amiga_getkey — one poll of the keyboard and the mouse buttons.
; Returns D0.B: 0 for nothing pressed, a character from $20 to $7E for a
; typing key, or one of the KEY_ tokens below $20 for a key with a name and
; for a mouse button.  README.md has the table.
; Clobbers: D0
;
; The keyboard arrives over the CIA-A serial port.  A received byte is the
; keycode rotated and inverted, and bit 7 after decoding is the key-up flag.
; The host must acknowledge each byte by driving the serial line as an output
; for a short pulse, or the keyboard stops sending.
;
; Shift is the one key whose release matters, because whether it is down picks
; which character table the next key comes out of.  Everything else is taken
; on the press.
;
; The keyboard holds each code until the host handshakes it, so a press an
; application leaves unread is late rather than lost.  After 143ms of no
; handshake the keyboard decides the code was missed and sends it a second
; time, with $F9 in front of it to say so.  The host has the first copy by
; then, so this drops the code behind a $F9.
;
; $F9 is the up code of scancode $79, which is not a key, so nothing else
; decodes to it.  The keyboard only ever sends it in front of the repeat, and
; one sent on its own would cost the next key struck.
; ---------------------------------------------------------------------------
amiga_getkey:
        MOVEM.L D1-D2/A0,-(SP)
        MOVE.B  (CIAA_ICR).L,D1         ; read and clear the CIA-A status
        BTST    #CIAA_ICR_SP,D1
        BEQ     .gk_lmb
        MOVE.B  (CIAA_SDR).L,D0         ; raw keycode
        BSET    #CIAA_CRA_SPMODE,(CIAA_CRA).L   ; drive the handshake
        MOVE.W  #250,D2
.gk_hs:
        DBF     D2,.gk_hs               ; the keyboard needs 85us, and this is about 350
        BCLR    #CIAA_CRA_SPMODE,(CIAA_CRA).L   ; back to input
        NOT.B   D0
        ROR.B   #1,D0                   ; keycode = ror(~raw)
        CMPI.B  #KBD_LOST_SYNC,D0
        BEQ     .gk_lost_sync
        TST.B   VAR_KEY_RESEND
        BNE     .gk_repeat
        MOVE.B  D0,D2
        ANDI.B  #$7F,D2                 ; the key, with the up flag off it
        CMPI.B  #KBD_SHIFT_L,D2
        BEQ     .gk_shift
        CMPI.B  #KBD_SHIFT_R,D2
        BEQ     .gk_shift
        BTST    #7,D0
        BNE     .gk_none                ; a key release, ignore
        MOVE.B  D2,D0
        CMPI.B  #KBD_NAMED_FIRST,D0
        BCC.S   .gk_named
        LEA     (kbd_plain).L,A0
        TST.B   VAR_SHIFT_HELD
        BEQ.S   .gk_pick
        LEA     (kbd_shifted).L,A0
        BRA.S   .gk_pick
.gk_named:
        SUBI.B  #KBD_NAMED_FIRST,D0
        CMPI.B  #KBD_NAMED_COUNT,D0
        BCC     .gk_none                ; above the last key with a name
        LEA     (kbd_named).L,A0
.gk_pick:
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        MOVE.B  (A0,D1.W),D0
        BEQ     .gk_none                ; a key this table has nothing for
.gk_out:
        MOVEM.L (SP)+,D1-D2/A0
        RTS
.gk_lmb:
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BNE.S   .gk_lmbup               ; bit set = not pressed
        CLR.W   VAR_LMB_UP_CNT          ; down again, so the settle count restarts
        TST.B   VAR_LMB_HELD
        BNE.S   .gk_rmb                 ; already reported this press
        MOVE.B  #1,VAR_LMB_HELD
        MOVEQ   #KEY_LMB,D0
        BRA.S   .gk_out
.gk_lmbup:
        ; Arm the next press once the button has read up long enough for the
        ; contact to have settled.  A bounce back down restarts the count.
        TST.B   VAR_LMB_HELD
        BEQ.S   .gk_rmb                 ; already armed
        ADDQ.W  #1,VAR_LMB_UP_CNT
        CMPI.W  #LMB_DEBOUNCE,VAR_LMB_UP_CNT
        BCS.S   .gk_rmb                 ; still settling
        CLR.B   VAR_LMB_HELD
.gk_rmb:
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .gk_rmbup               ; bit set = not pressed
        TST.B   VAR_RMB_HELD
        BNE.S   .gk_none
        MOVE.B  #1,VAR_RMB_HELD
        MOVEQ   #KEY_RMB,D0
        BRA.S   .gk_out
.gk_rmbup:
        CLR.B   VAR_RMB_HELD
.gk_none:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2/A0
        RTS
.gk_shift:
        ; Bit 7 is the up flag, so shift is down where the bit is clear.
        MOVEQ   #1,D1
        BTST    #7,D0
        BEQ     .gk_shift_put
        MOVEQ   #0,D1
.gk_shift_put:
        MOVE.B  D1,VAR_SHIFT_HELD
        BRA     .gk_none
.gk_lost_sync:
        MOVE.B  #1,VAR_KEY_RESEND       ; the code behind this one is a repeat
        BRA     .gk_none
.gk_repeat:
        CLR.B   VAR_KEY_RESEND
        BRA     .gk_none

; ---------------------------------------------------------------------------
; both_buttons_held — D0.B = 1 where the left and right mouse buttons are both
; down, else 0.  The menu request at boot uses it.
; Clobbers: D0
; ---------------------------------------------------------------------------
both_buttons_held:
        MOVEM.L D1,-(SP)
        MOVEQ   #0,D0
        BTST    #CIAA_PRA_LMB,(CIAA_PRA).L
        BNE.S   .bbh_done               ; left not pressed
        MOVE.W  (POTGOR).L,D1
        BTST    #POTGOR_RMB,D1
        BNE.S   .bbh_done               ; right not pressed
        MOVEQ   #1,D0
.bbh_done:
        MOVEM.L (SP)+,D1
        RTS
