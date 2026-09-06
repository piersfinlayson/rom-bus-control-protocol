; plat.s — the Apple IIe side of the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the vectors, the screen, the keys and the
; clock.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving the EF socket and the command page is a page of that socket, so a
; host fetching its instructions out of the image would be sending command
; bytes with every pass through a routine that happened to land there.  The
; whole of CODE and RODATA is copied down before the first knock, and after
; that nothing touches the socket except the command page reads the protocol
; makes and the back channel it writes.

    .include "pipe_defs.s"

.import pipe_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

; There is no NMI on this motherboard, so nothing ever raises this.  The shared
; code reads it on every line of every run and it stays zero.
.export plat_abort_flag
plat_abort_flag: .res 1

; ===========================================================================
; BOOT segment — runs from ROM, before the copy
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — the RESET vector's target.
;
; Interrupts are masked here and never unmasked.  Nothing in this tester has
; anything to do in an interrupt, and one landing in the middle of a command
; frame would stretch it in time at best.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    ; 40 column text, page 1, the primary character set.  Done here rather
    ; than after the copy so that a machine which cannot get that far still
    ; shows a text screen rather than whatever the graphics mode held.
    sta TXTSET
    sta MIXCLR
    sta TXTPAGE1
    sta LORES
    sta CLR80COL
    sta CLRALTCHAR
    sta KBDSTRB

    lda #0
    sta plat_abort_flag

    ; CODE and RODATA are laid out next to each other in the image and next to
    ; each other in RAM, so one copy moves both.
    lda #<__CODE_LOAD__
    sta ZP_PTR_LO
    lda #>__CODE_LOAD__
    sta ZP_PTR_HI
    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1
    lda #<(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP2
    lda #>(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP3

    ldy #0
@copy:
    lda (ZP_PTR_LO), y
    sta (ZP_TMP0), y
    iny
    bne @same_page
    inc ZP_PTR_HI
    inc ZP_TMP1
@same_page:
    lda ZP_TMP2
    bne @dec_lo
    dec ZP_TMP3
@dec_lo:
    dec ZP_TMP2
    lda ZP_TMP2
    ora ZP_TMP3
    bne @copy

    jmp pipe_run                ; its RAM address, the linker having said so

; ---------------------------------------------------------------------------
; irq_nmi_stub — both vectors point here.  Interrupts are masked and never
; unmasked, and an Apple II motherboard raises no NMI, but a card can.
;
; It stays in ROM so that it is valid from the first cycle after reset, before
; the copy has run.  These two bytes are the only instructions ever fetched out
; of the served image once a session is open, and they are not on the command
; page, which is the page the device filters command bytes on.  So the device
; sees an ordinary ROM read and ignores it.
; ---------------------------------------------------------------------------

irq_nmi_stub:
    rti

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

; ---------------------------------------------------------------------------
; Row addresses.  Screen rows are interleaved, so a table is cheaper than
; working the address out each time.
; ---------------------------------------------------------------------------

row_off_lo:
    .repeat SCREEN_ROWS, i
        .byte <(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

row_scr_hi:
    .repeat SCREEN_ROWS, i
        .byte >(SCREEN_BASE + (i .mod 8) * $80 + (i / 8) * $28)
    .endrepeat

; ---------------------------------------------------------------------------
; plat_init — the display the tester draws on.  Everything it needs was set at
; reset, so there is nothing left to do.  Clobbers nothing.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen.  The whole of text page 1, the holes included,
; which is four pages and no tail to count.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    lda #$A0                    ; a space, in normal video
    ldx #0
@page:
    sta SCREEN_BASE + $000, x
    sta SCREEN_BASE + $100, x
    sta SCREEN_BASE + $200, x
    sta SCREEN_BASE + $300, x
    inx
    bne @page
    rts

; ---------------------------------------------------------------------------
; plat_row — A = row.  Points the screen writer at it.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_row
plat_row:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column.  Y comes back as it went in, because the
; caller is walking a row with it.  Clobbers A.
;
; The screen has no colour, and a character with bit 7 set is normal video, so
; a write is one ora.  The title bar and the selected path name are put down
; this way and turned over afterwards by plat_reverse.
;
; The clock is polled here.  Redrawing the counters is tens of thousands of
; cycles and sends nothing, and the poll in the send paths cannot see a frame
; go by while that is happening.  One character costs a few hundred cycles at
; the very most, which is well inside a frame.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    pha
    jsr plat_clock_poll
    pla
    ora #$80
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Clears bits 7 and 6 of the
; characters already there, which is what inverse video is.
; Clobbers A, X, Y and ZP_TMP0/1.
; ---------------------------------------------------------------------------

.export plat_reverse
plat_reverse:
    stx ZP_TMP0                 ; column
    sty ZP_TMP1                 ; length
    jsr plat_row
    ldy ZP_TMP0
    ldx ZP_TMP1
@loop:
    lda (ZP_SCR_LO), y
    and #$3F
    sta (ZP_SCR_LO), y
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; plat_key — a key code, or KEY_NONE_CODE if nothing has been pressed.
;
; The keyboard latches the last key pressed and holds it until the strobe is
; cleared, so this reads and clears.  A key this tester has no use for is
; cleared too, rather than left to be read as the next one.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda KBD
    bpl @none
    sta KBDSTRB
    and #$7F
    cmp #KEY_1_ASCII
    bne @not_1
    lda #KEY_1_CODE
    rts
@not_1:
    cmp #KEY_2_ASCII
    bne @not_2
    lda #KEY_2_CODE
    rts
@not_2:
    cmp #KEY_3_ASCII
    bne @not_3
    lda #KEY_3_CODE
    rts
@not_3:
    cmp #KEY_T_ASCII
    beq @t
    cmp #KEY_T_LOWER
    bne @not_t
@t:
    lda #KEY_T_CODE
    rts
@not_t:
    cmp #KEY_RET_ASCII
    bne @none
    lda #KEY_RET_CODE
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
; plat_key_stop — Z set means the run should stop.
;
; Neither the key register nor the strobe says whether a key is still held, so
; there is no way to name one key as the stop key without stopping on every
; other key as well by the time the finger comes off it.  So any key stops a
; run, which is what the second row of key names says.  The strobe is left for
; plat_key to clear, in run_finish.
;
; A run calls this one line in sixteen, and the stall in fault.s calls it on
; every round.  That second caller is why the clock is polled here: a pipe that
; has gone full sends nothing, and the stall is bounded in ticks.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key_stop
plat_key_stop:
    jsr plat_clock_poll
    lda KBD
    and #$80
    eor #$80                    ; zero, and so Z set, when a key is waiting
    rts

; ---------------------------------------------------------------------------
; plat_key_wait_none — drains the keyboard.  Clobbers A.
;
; The caller means "wait until the finger comes off", and the machine cannot
; answer that.  What it can say is that no further key has arrived, which is
; the same thing once the hardware's own repeat has stopped.
; ---------------------------------------------------------------------------

.export plat_key_wait_none
plat_key_wait_none:
    jsr plat_key
    cmp #KEY_NONE_CODE
    bne plat_key_wait_none
    rts

; ---------------------------------------------------------------------------
; plat_clock_start — zeroes the tick and takes the blanking bit as it stands,
; so that the first edge counted is a real one.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_clock_start
plat_clock_start:
    lda VBLBAR
    and #$80
    sta ZP_VBL
    lda #0
    sta ZP_HALF
    sta ZP_TICK
    rts

; ---------------------------------------------------------------------------
; plat_clock_poll — counts a tick when two frames have gone by.
;
; Twenty-two cycles including the call when nothing has changed, which is all
; but sixty of the times it runs in a second.  That is what the tick costs the
; measurement, and it is charged to every send path equally.
;
; One edge of the blanking bit is counted and the other ignored, so a frame is
; counted once.  Which of the two edges falls inside the blanking interval does
; not matter — either way there is one of each a frame.  The shorter of the two
; phases is about 4500 cycles, so anything that polls more often than that
; cannot miss one.
;
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_clock_poll
plat_clock_poll:
    lda VBLBAR
    eor ZP_VBL
    bpl @out                    ; the bit is where it was, so no edge
    lda ZP_VBL
    eor #$80
    sta ZP_VBL
    bpl @out                    ; the edge that is not counted
    lda ZP_HALF
    eor #$01
    sta ZP_HALF
    bne @out                    ; the first frame of the pair
    inc ZP_TICK
@out:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

.export plat_keys_1
plat_keys_1:
    .byte "RETURN STARTS A RUN, ANY KEY STOPS IT", 0

.export plat_keys_2
plat_keys_2:
    .byte "T RUNS TEN SECONDS", 0

; ===========================================================================
; CMD — the command page, which the device reads and the image never does
; ===========================================================================

.segment "CMD"
    .res 256, $00

; ===========================================================================
; BCH — the back-channel region, which the device writes and the image does not
; ===========================================================================

.segment "BCH"
    .res 64, $00

; ===========================================================================
; The 6502 vectors, read at reset and never again
; ===========================================================================

.segment "VECTORS"
    .word irq_nmi_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub          ; $FFFE-$FFFF  IRQ/BRK
