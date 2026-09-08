; plat.s — the C64 side of the auxiliary I/O tester
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Reset entry, the copy into RAM, the vectors, the screen, the keys, and
; blanking the VIC.
;
; Everything after boot_entry runs from RAM.  It has to, because the device is
; serving one of the machine's ROM sockets and the command page is a page of
; that socket, so a host fetching its instructions out of the image would be
; sending command bytes with every pass through a routine that happened to land
; there.  The whole of CODE and RODATA is copied down before the first knock,
; and after that nothing touches the socket except the command page reads the
; protocol makes and the back channel it writes.
;
; The screen has colour, so all three roles are drawn from the same characters
; and the colour says which: light green for a pin this machine is driving,
; white for one nobody is driving, medium grey for one the ROM is using.

    .include "auxio_defs.s"

.import auxio_run

.import c64_hw_init
.import c64_clear_screen
.import row_off_lo
.import row_scr_hi
.import row_col_hi

; Linker-generated symbols for the segments that run from RAM.
.import __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

shifted:         .res 1         ; 1 while a shift key is held during a scan
last_key:        .res 1         ; what the last scan found, so a held key
                                ; is reported once
dark_depth:      .res 1         ; how many callers have the screen off
dark_ctrl:       .res 1         ; VIC_CTRL1 as the outermost one found it

fill_char:       .res 1         ; plat_fill_row's two bytes, held across the
fill_col:        .res 1         ; loop so neither has to be worked out again

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
; Interrupts are masked here and never unmasked.  Nothing in this program has
; anything to do in an interrupt, and one landing in the middle of a command
; frame would stretch it in time at best.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

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

    jmp auxio_run               ; its RAM address, the linker having said so

; ---------------------------------------------------------------------------
; The interrupt stubs and the vector table.  A BASIC socket image holds no
; $FFFA, the machine's own kernal being fitted and owning both vectors, so it
; takes RESTORE through $0318 instead.  See basic_nmi.
; ---------------------------------------------------------------------------

.ifndef BASIC_SOCKET

; RESTORE, and interrupts that are masked and never unmasked.  Both stay in ROM
; so that they are valid from the first cycle after reset, before the copy has
; run.  These bytes are the only instructions ever fetched out of the served
; image once a session is open, and they are not on the command page, which is
; the page the device filters command bytes on.  So the device sees ordinary
; ROM reads and ignores them.
nmi_irq_stub:
    rti

.segment "VECTORS"

    .word nmi_irq_stub          ; $FFFA-$FFFB  NMI
    .word boot_entry            ; $FFFC-$FFFD  RESET
    .word nmi_irq_stub          ; $FFFE-$FFFF  IRQ/BRK

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
    rti

.endif

; ---------------------------------------------------------------------------
; plat_init — the display the tester draws on.  c64_hw_init left the VIC off,
; so this is where the picture comes up, and it comes up blank rather than as
; whatever the last program left in screen RAM.  auxio_run calls it, which is
; why the machine spends the copy with a dark screen.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export plat_init
plat_init:
    lda #0
    sta dark_depth
    sta last_key
    lda #COL_BLACK
    sta VIC_BORDER
    sta VIC_BACKGROUND
    jsr plat_cls
    lda #VIC_CTRL1_VAL
    sta VIC_CTRL1
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen.  The colour it clears to is what the text is
; drawn in, so a character written without a colour behind it still reads.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export plat_cls
plat_cls:
    ldy #COL_WHITE
    jmp c64_clear_screen

; ---------------------------------------------------------------------------
; plat_row — A = row.  Points the screen writer at it.  Clobbers A, X.
;
; Both rows are 40 bytes from a page-aligned base, so the low byte is the same
; for the characters and for the colour beside them.
; ---------------------------------------------------------------------------

.export plat_row
plat_row:
    tax
    lda row_off_lo, x
    sta ZP_SCR_LO
    sta ZP_COL_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    lda row_col_hi, x
    sta ZP_COL_HI
    rts

; ---------------------------------------------------------------------------
; plat_put — A = ASCII, Y = column, X = a COLR_ role.  Y and X come back as
; they went in, because the caller is walking a row with one and holding the
; role in the other.  Clobbers A.
; ---------------------------------------------------------------------------

.export plat_put
plat_put:
    jsr to_screen
    sta (ZP_SCR_LO), y
    lda role_col, x
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_glyph — A = a GLY_ index, Y = column, X = a COLR_ role.  Y and X come
; back as they went in.  Clobbers A.
;
; The glyphs are already screen codes, so there is no conversion here.  All
; three roles draw the same character and the colour says which, which is what
; a screen with colour is for.
; ---------------------------------------------------------------------------

.export plat_glyph
plat_glyph:
    stx ZP_TMP0                 ; the role, X being wanted for the index
    tax
    lda glyph_tab, x
    sta (ZP_SCR_LO), y
    ldx ZP_TMP0
    lda role_col, x
    sta (ZP_COL_LO), y
    rts

; ---------------------------------------------------------------------------
; plat_fill_row — A = ASCII, X = a COLR_ role.  Fills the selected row.
; Clobbers A, Y.
; ---------------------------------------------------------------------------

.export plat_fill_row
plat_fill_row:
    jsr to_screen
    sta fill_char
    lda role_col, x
    sta fill_col
    ldy #SCREEN_COLS - 1
@loop:
    lda fill_char
    sta (ZP_SCR_LO), y
    lda fill_col
    sta (ZP_COL_LO), y
    dey
    bpl @loop
    rts

; ---------------------------------------------------------------------------
; to_screen — A = ASCII, and comes back as the screen code for it.  This
; character set holds one case, so a lower case letter is drawn as the upper
; case one.  A device that calls itself One ROM is the reason there is a
; second branch here at all.
; ---------------------------------------------------------------------------

to_screen:
    cmp #'@'
    bcc @done                   ; $20-$3F are their own screen codes
    cmp #'_' + 1
    bcs @lower
    sec
    sbc #$40                    ; $40-$5F, which is @ A-Z [ \ ] ^ _
    rts
@lower:
    cmp #'a'
    bcc @done
    cmp #'z' + 1
    bcs @done
    sec
    sbc #$60
@done:
    rts

; ---------------------------------------------------------------------------
; plat_reverse — A = row, X = column, Y = length.  Sets bit 7 on the screen
; codes already there, which is what reverse video is.  The colour is left
; alone, so a run turned over keeps whatever it was drawn in.
; Clobbers A, X, Y and the c64_hw.s scratch.
; ---------------------------------------------------------------------------

.export plat_reverse
plat_reverse:
    stx ZP_TMP0                 ; before plat_row, which takes X for the row
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
; plat_dark and plat_light — the screen off while the host is talking to the
; device, and back on afterwards.
;
; A VIC-II fetching characters takes the bus off the processor, and on a badline
; it holds it for over forty cycles.  Across that handover the device can see an
; access that was not one, see one as two, or miss one, and any of those slips
; the command frame by a byte.  With the display off there are no fetches.
;
; A pair covers a whole operation — the session opening, a group being reread —
; not a command, so the screen goes dark once per pass rather than once per pin.
; The border is left as it is, so what a rescan costs is the picture for as long
; as it takes.
;
; Clearing the bit is not enough on its own.  The VIC-II reads it at raster
; line $30 and fetches for the rest of the frame on what it read there, so a
; bit cleared after that line stops nothing until the next frame.  A run that
; lasts seconds would not notice.  A rescan takes well under a frame, so every
; one would be sent into the fetches this frame was already committed to, and
; one exchange in a hundred came out mangled.  So this waits for line $30 to
; come round with the bit already clear, which costs at most a frame.
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
@wait:
    lda VIC_CTRL1
    and #VIC_CTRL1_RST8         ; so that line $130 is not taken for line $30
    bne @wait
    lda VIC_RASTER
    cmp #VIC_DEN_LINE
    bne @wait
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
    lda dark_ctrl
    sta VIC_CTRL1
@out:
    pla
    plp
    rts

; ---------------------------------------------------------------------------
; plat_key — a key code, once per press, or KEY_NONE_CODE.
;
; The matrix says what is held, not what has just been pressed, so a scan that
; finds what the last one found reports nothing.  That is what stops a held key
; from moving the cursor across the screen.
;
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_key
plat_key:
    jsr scan
    cmp last_key
    beq @nothing_new
    sta last_key
    ldx #DEBOUNCE_COUNT
@dly:
    dex
    bne @dly
    rts
@nothing_new:
    lda #KEY_NONE_CODE
    rts

; scan — what the matrix holds this instant, as a KEY_ code, or KEY_NONE_CODE.
scan:
    jsr shift_held
    lda #0
    rol a                       ; 1 while shift is held, 0 otherwise
    sta shifted

    ldx #0
@entry:
    lda key_table, x
    beq @none
    sta CIA1_PRA
    lda key_table + 1, x
    and CIA1_PRB
    beq @down
    inx
    inx
    inx
    inx
    bne @entry                  ; the table never reaches 64 entries
@none:
    lda #KEY_NONE_CODE
    rts

@down:
    txa
    clc
    adc #2                      ; the code, or the one after it under shift
    adc shifted
    tax
    lda key_table, x
    rts

; shift_held — carry set if either shift key is down.  Clobbers A.
shift_held:
    lda #KEY_LSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_LSH_ROW_BIT
    beq @yes
    lda #KEY_RSH_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RSH_ROW_BIT
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; The tier tables.  Forty columns, and fifteen rows between ROW_RINGS and
; ROW_RINGS_END.  tier_cap is what each size holds: rings across, times banks
; down, and never more than MAX_PINS.
; ---------------------------------------------------------------------------

.export tier_w
.export tier_h
.export tier_pitch
.export tier_perrow
.export tier_bankh
.export tier_cap

; The dot tier is one character wide and its pin number is two, so its pitch
; is three rather than two.  At a pitch of two the numbers of consecutive pins
; run into each other and the row reads as one long figure.
tier_w:         .byte 7, 5, 3, 1
tier_h:         .byte 5, 3, 3, 1
tier_pitch:     .byte 9, 7, 4, 3
tier_perrow:    .byte 4, 5, 9, 13
tier_bankh:     .byte 6, 4, 4, 2
tier_cap:       .byte 8, 15, 27, MAX_PINS

; ---------------------------------------------------------------------------
; The glyphs, in GLY_ order: the four rounded corners, the horizontal and
; vertical edges, a ring's inside high and low, and the one character tier high
; and low.  Screen codes, verified against chargen-901225-01.bin.
;
; There is one row and not three, because the colour says who owns a pin and
; the character does not have to.
; ---------------------------------------------------------------------------

glyph_tab:
    .byte $55, $49, $4A, $4B    ; rounded corners, clockwise from top left
    .byte $40, $5D              ; horizontal, vertical
    .byte $A0, $20              ; a ring's inside: reversed space, then space
    .byte $51, $57              ; filled circle, hollow circle

; ---------------------------------------------------------------------------
; What each role is drawn in.  Red has been changed by this machine, blue
; belongs to the ROM, and white is everything else — free pins and every word
; on the screen.
;
; Saturated ones, not pale ones.  On a black screen a pale colour reads as grey
; whatever it was meant to be, and these have to hold up at the single
; character the smallest ring tier draws.
; ---------------------------------------------------------------------------

role_col:
    .byte COL_BLUE              ; COLR_THEIRS
    .byte COL_WHITE             ; COLR_FREE
    .byte COL_RED               ; COLR_OURS
    .byte COL_WHITE             ; COLR_TEXT
    .byte COL_WHITE             ; COLR_TITLE

; ---------------------------------------------------------------------------
; The keyboard matrix, four bytes an entry: the column select, the row bit, the
; code, and the code a shift gives instead.  A column mask of zero ends it,
; which is never a valid one — a valid mask has exactly one bit clear.  Entries
; are tried in order and the first match wins.
;
; Shift reverses the two cursor keys, which is what a C64 does with them
; everywhere else.  Both shift keys are missing on purpose: they are read by
; shift_held, and an entry for either would match on its own.
; ---------------------------------------------------------------------------

key_table:
    .byte %11111110, %00000100, KEY_PIN_NEXT,    KEY_PIN_PREV     ; CRSR right
    .byte %11111110, %10000000, KEY_ROW_NEXT,    KEY_ROW_PREV     ; CRSR down
    .byte %11111110, %00000010, KEY_RETURN_CODE, KEY_RETURN_CODE  ; RETURN
    .byte %11011111, %00100000, KEY_PAGE_PREV,   KEY_PAGE_PREV    ; : and [
    .byte %10111111, %00000100, KEY_PAGE_NEXT,   KEY_PAGE_NEXT    ; ; and ]
    .byte %11111101, %00010000, KEY_REL_CODE,    KEY_REL_CODE     ; Z
    .byte %11111011, %00000010, KEY_RESET_CODE,  KEY_RESET_CODE   ; R
    .byte %11110111, %00010000, KEY_BLINK_CODE,  KEY_BLINK_CODE   ; B
    .byte %11110111, %00100000, KEY_HIGH_CODE,   KEY_HIGH_CODE    ; H
    .byte %11011111, %00000100, KEY_LOW_CODE,    KEY_LOW_CODE     ; L
    .byte 0
