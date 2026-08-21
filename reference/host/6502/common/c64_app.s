; c64_app.s — taking the C64 over on entry and handing it back on exit
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; An application entered from BASIC by SYS and returning by rts must give the
; machine back exactly as it found it.  What is taken and given back, in order:
; the stack pointer, interrupts, zero page $D0-$FF, the border and background
; colours, and the NMI vector.
;
; sei comes second, before the zero page save and before anything reads the
; served ROM.  The kernal's raster IRQ scans the keyboard through KEYLOG at
; $F5/$F6 on every frame, which is inside the block about to be taken, so
; leaving interrupts on for even the save would have the two fighting.

    .include "app_defs.s"

.import c64_keys_wait_none

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

saved_sp:       .res 1
saved_zp:       .res ZP_SAVE_COUNT
saved_border:   .res 1
saved_bg:       .res 1
saved_nmi:      .res 2

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; c64_app_enter — called by jsr as the first thing the application does, with
; interrupts still on and the kernal live.
;
; The saved stack pointer is the caller's, which is two higher than the one
; seen here: this routine's own return address is on the stack.  c64_app_leave
; restores that value, so the rts it ends with is the application's rts to
; BASIC.
;
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export c64_app_enter
c64_app_enter:
    tsx
    inx                         ; skip this routine's return address
    inx
    stx saved_sp
    sei                         ; before the first use of $D0-$FF

    ldx #0
@save_zp:
    lda ZP_SAVE_BASE, x
    sta saved_zp, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @save_zp

    lda VIC_BORDER
    sta saved_border
    lda VIC_BACKGROUND
    sta saved_bg

    lda NMINV
    sta saved_nmi
    lda NMINV+1
    sta saved_nmi+1
    lda #<nmi_stub
    sta NMINV
    lda #>nmi_stub
    sta NMINV+1
    rts

; ---------------------------------------------------------------------------
; c64_app_leave — hands the machine back and returns to BASIC.  Never returns
; to its caller: restoring the stack pointer discards the jsr that reached it.
;
; Order is the reverse of enter's.  The kernal clear-screen call comes after
; the zero page restore because the screen editor works through LDTB1 at
; $D9-$F2, which the application has been using.
;
; The release wait comes first.  Without it the key that asked to quit is still
; held when cli runs, the kernal's IRQ scan puts it in the keyboard buffer, and
; BASIC echoes it after READY.  Zeroing NDX afterwards catches anything the IRQ
; managed to buffer between cli and here.
; ---------------------------------------------------------------------------

.export c64_app_leave
c64_app_leave:
    jsr c64_keys_wait_none

    lda saved_nmi
    sta NMINV
    lda saved_nmi+1
    sta NMINV+1

    lda saved_border
    sta VIC_BORDER
    lda saved_bg
    sta VIC_BACKGROUND

    ldx #0
@restore_zp:
    lda saved_zp, x
    sta ZP_SAVE_BASE, x
    inx
    cpx #ZP_SAVE_COUNT
    bne @restore_zp

    ldx saved_sp
    txs
    cli
    lda #0
    sta KEY_NDX
    jsr KERNAL_CLRSCR
    rts

; ---------------------------------------------------------------------------
; nmi_stub
;
; RESTORE is edge-triggered through its own monostable rather than through a
; CIA, so nothing needs acknowledging, and there is nothing this has to do
; except not be the kernal's.
;
; Without it the default handler reaches jmp ($A002) when RUN/STOP is held with
; RESTORE — a read of the command page in the middle of a session, which would
; inject a command byte.  Returning at once touches no register and no memory,
; so an NMI arriving mid-command stretches the frame in time but does not
; corrupt it.
; ---------------------------------------------------------------------------

nmi_stub:
    rti
