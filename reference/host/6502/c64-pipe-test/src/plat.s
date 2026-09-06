; plat.s — the C64 side of the pipe throughput test
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the vectors, the screen, the keys, the clock,
; and blanking the VIC.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving one of the machine's ROM sockets and the command page is a page of
; that socket, so a host fetching its instructions out of the image would be
; sending command bytes with every pass through a routine that happened to land
; there.  The whole of CODE and RODATA is copied down before the first knock,
; and after that nothing touches the socket except the command page reads the
; protocol makes and the back channel it writes.

    .include "pipe_defs.s"

.import c64_hw_init
.import c64_clear_screen
.import row_off_lo
.import row_scr_hi

.import pipe_run

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

.export plat_abort_flag
plat_abort_flag: .res 1         ; RESTORE was pressed

video_pal:       .res 1         ; non-zero PAL, worked out at plat_clock_start
dark_depth:      .res 1         ; how many callers have the screen off
dark_ctrl:       .res 1         ; VIC_CTRL1 as the outermost one found it
dark_border:     .res 1         ; and the border colour

; ===========================================================================
; FILL segment — the command page, then the back-channel region
; ===========================================================================

; A kernal socket image is entered at reset through $FFFC.  A BASIC socket
; image (BASIC_SOCKET) is entered by the machine's own kernal, which jumps
; through the word at $A000 once it has finished its own reset.  That word is
; the first two bytes of the command page, and the device reads the page rather
; than what is in it, so an address there costs the protocol nothing.

.segment "FILL"

.ifdef BASIC_SOCKET
    .word boot_entry            ; $A000-$A001  BASIC cold start
    .res 766, $00
.else
    .res 768, $00
.endif

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

    lda #0
    sta plat_abort_flag

    jsr c64_hw_init             ; also in BOOT, so safe to call from ROM

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

.ifdef BASIC_SOCKET
    lda #<basic_nmi             ; the copy is done, so this address is live
    sta NMINV
    lda #>basic_nmi
    sta NMINV + 1
.endif

    jmp pipe_run                ; its RAM address, the linker having said so

; ---------------------------------------------------------------------------
; The interrupt stubs and the vector table.  A BASIC socket image holds no
; $FFFA, the machine's own kernal being fitted and owning both vectors, so it
; takes RESTORE through $0318 instead.  See basic_nmi.
; ---------------------------------------------------------------------------

.ifndef BASIC_SOCKET

; ---------------------------------------------------------------------------
; nmi_entry — RESTORE.
;
; RESTORE is edge-triggered through its own monostable rather than through a
; CIA, so there is nothing to acknowledge.  All this does is raise the flag the
; run loop reads.
;
; It stays in ROM so that it is valid from the first cycle after reset, before
; the copy has run.  These few bytes are the only instructions ever fetched out
; of the served image once a session is open, and they are not on the command
; page, which is the page the device filters command bytes on.  So the device
; sees ordinary ROM reads and ignores them.
; ---------------------------------------------------------------------------

nmi_entry:
    pha
    lda #1
    sta plat_abort_flag
    pla
    rti

; IRQs are masked at boot_entry and never unmasked, so this is a safety net.
irq_stub:
    rti

; ---------------------------------------------------------------------------
; The vector table at $FFFA-$FFFF
; ---------------------------------------------------------------------------

.segment "VECTORS"

    .word nmi_entry             ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word irq_stub              ; $FFFE-$FFFF  IRQ/BRK

.endif

; ===========================================================================
; CODE segment — runs from RAM
; ===========================================================================

.code

.ifdef BASIC_SOCKET

; ---------------------------------------------------------------------------
; basic_nmi — RESTORE, on the image the machine's own kernal boots.
;
; NMI is not maskable, so the sei at boot_entry does not keep RESTORE away from
; the kernal's handler.  That handler ends at jmp ($A002) when RUN/STOP is held
; too, and $A002 is inside the command page, so those two reads would go into
; an open frame as command bytes.  Taking $0318 first is what stops it.
;
; This runs from RAM, so it reads nothing out of the served image.
; ---------------------------------------------------------------------------

basic_nmi:
    pha
    lda #1
    sta plat_abort_flag
    pla
    rti

.endif

; ---------------------------------------------------------------------------
; plat_init — the display the tester draws on.  White on black rather than
; anything prettier, it being what reads on video.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    lda #0
    sta dark_depth
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    jsr plat_cls
    lda #VIC_CTRL1_VAL
    sta VIC_CTRL1               ; display on, which is where a run starts
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the tester's own colour.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    ldy #COL_WHITE
    jmp c64_clear_screen

; ---------------------------------------------------------------------------
; plat_row — A = row.  Points the screen writer at it.  Clobbers A, X.
;
; Colour RAM is written once, by the clear, and never again — every character
; on this screen is the same colour — so plat_put has a screen pointer to keep
; up to date and nothing else.
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
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    cmp #'A'
    bcc @write
    cmp #'Z' + 1
    bcs @lower
    sec
    sbc #$40
    bcs @write                  ; always taken
@lower:
    cmp #'a'
    bcc @write
    cmp #'z' + 1
    bcs @write
    sec
    sbc #$60
@write:
    sta (ZP_SCR_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes already there, which is what reverse video is.
; Clobbers A, X, Y and the c64_hw.s scratch.
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
    ora #$80
    sta (ZP_SCR_LO), y
    iny
    dex
    bne @loop
    rts

; ---------------------------------------------------------------------------
; plat_key — a key code, or KEY_NONE_CODE if nothing is held.
;
; Four column selects cover the five keys.  A run does not call this — it
; calls plat_key_stop, which is one column.
;
; Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    lda #KEY_COL_7
    sta CIA1_PRA
    lda CIA1_PRB
    tax
    and #KEY_1_BIT
    bne @c7_2
    lda #KEY_1_CODE
    bne @debounce               ; always taken
@c7_2:
    txa
    and #KEY_2_BIT
    bne @col_1
    lda #KEY_2_CODE
    bne @debounce               ; always taken

@col_1:
    lda #KEY_COL_1
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_3_BIT
    bne @col_2
    lda #KEY_3_CODE
    bne @debounce               ; always taken

@col_2:
    lda #KEY_COL_2
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_T_BIT
    bne @col_0
    lda #KEY_T_CODE
    bne @debounce               ; always taken

@col_0:
    jsr plat_key_stop
    bne @none
    lda #KEY_RET_CODE
@debounce:
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts
@none:
    lda #KEY_NONE_CODE
    rts

; ---------------------------------------------------------------------------
; plat_key_stop — one column, about 13 cycles.  Z set means RETURN is held.
; A run calls this one line in sixteen, so a stop is seen within about 24 ms.
; Clobbers A.
; ---------------------------------------------------------------------------

.export plat_key_stop
plat_key_stop:
    lda #KEY_COL_0
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RETURN_BIT
    rts

; ---------------------------------------------------------------------------
; plat_key_wait_none — spins until nothing is held.  Clobbers A, X.
; ---------------------------------------------------------------------------

.export plat_key_wait_none
plat_key_wait_none:
    jsr plat_key
    cmp #KEY_NONE_CODE
    bne plat_key_wait_none
    rts

; ---------------------------------------------------------------------------
; plat_clock_start — works out the video standard and programs CIA2 for it.
;
; CIA2 rather than CIA1, which carries the keyboard matrix.  The interrupt mask
; at $DD0D is left alone, so neither timer can raise an NMI.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_clock_start
plat_clock_start:
    jsr detect_video

    lda #0                      ; stop both before loading the latches
    sta CIA2_CRA
    sta CIA2_CRB

    lda video_pal
    beq @ntsc
    lda #<PAL_TA_LATCH
    sta CIA2_TA_LO
    lda #>PAL_TA_LATCH
    sta CIA2_TA_HI
    jmp @latched
@ntsc:
    lda #<NTSC_TA_LATCH
    sta CIA2_TA_LO
    lda #>NTSC_TA_LATCH
    sta CIA2_TA_HI
@latched:
    lda #$FF                    ; Timer B just counts, so it free-runs
    sta CIA2_TB_LO
    sta CIA2_TB_HI

    lda #CIA2_CRB_RUN
    sta CIA2_CRB
    lda #CIA2_CRA_RUN
    sta CIA2_CRA
    rts

; ---------------------------------------------------------------------------
; detect_video — PAL or NTSC, from the VIC-II itself.
;
; The kernal works this out at reset and leaves the answer at $02A6, and there
; is no kernal here, so the tester asks the same question the kernal does.  A
; PAL VIC-II counts 312 raster lines and an NTSC one 263, so a line number of
; 264 or more can only be PAL.  The raster counter runs whether the display is
; enabled or not.
;
; The line number is nine bits, the top one in VIC_CTRL1, and the two registers
; are read one after the other rather than together.  The raster can step
; between the two reads, which can only lose a PAL machine a sample, never make
; an NTSC one look like PAL: the highest an NTSC line number reaches is 262,
; and a line or two on from that it has wrapped to 0 with the top bit clear.
;
; PAL spends 48 lines above 263, about 3000 cycles, and the loop below samples
; every eleven, so it cannot be missed.  The whole loop is about 45 ms, which is
; over two frames on either machine.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

detect_video:
    lda #0
    sta video_pal
    ldy #16
@outer:
    ldx #0
@inner:
    lda VIC_CTRL1
    bpl @next                   ; line under 256, nothing to learn from it
    lda VIC_RASTER
    cmp #<264
    bcs @pal
@next:
    dex
    bne @inner
    dey
    bne @outer
    rts
@pal:
    lda #1
    sta video_pal
    rts

; ---------------------------------------------------------------------------
; plat_dark and plat_light — the screen off while the host is talking to the
; device, and back to however it was found afterwards.
;
; A VIC-II fetching characters takes the bus off the processor, and on a badline
; it holds it for over forty cycles.  Across that handover the device can see an
; access that was not one, see one as two, or miss one, and any of those slips
; the command frame by a byte.  With the display off there are no fetches.
;
; A pair covers a whole operation — the session opening, a run — not a command,
; so the screen never changes state at loop rate.  Counters carry on being
; written while it is dark and are there to read the moment a run ends.
;
; The border goes blue because with the display off the whole screen takes the
; border colour, and black in both states would look like a stopped machine.
;
; The pair nests, so an inner one cannot put the screen back early.  Neither
; touches a register or a flag, so either can sit between a call and the branch
; on its carry.
; ---------------------------------------------------------------------------

.export plat_dark
plat_dark:
    php
    pha
    inc dark_depth
    lda dark_depth
    cmp #1
    bne @out
    lda VIC_CTRL1
    sta dark_ctrl
    and #<(~VIC_CTRL1_DEN)
    sta VIC_CTRL1
    lda VIC_BORDER
    sta dark_border
    lda #COL_BLUE
    sta VIC_BORDER
@out:
    pla
    plp
    rts

.export plat_light
plat_light:
    php
    pha
    dec dark_depth
    bne @out
    lda dark_border
    sta VIC_BORDER
    lda dark_ctrl
    sta VIC_CTRL1
@out:
    pla
    plp
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

.export plat_keys_1
plat_keys_1:
    .byte "RET STARTS AND STOPS A RUN", 0

.export plat_keys_2
plat_keys_2:
    .byte "T RUNS TEN SECONDS", 0
