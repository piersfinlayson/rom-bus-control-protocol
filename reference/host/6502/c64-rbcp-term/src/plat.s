; plat.s — the C64 side of the RBCP terminal
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

    .include "term_defs.s"

.import c64_hw_init
.import c64_clear_screen
.import row_off_lo
.import row_scr_hi

.import term_run

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
; Interrupts are masked here and never unmasked.  Nothing in this terminal has
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

    jmp term_run                ; its RAM address, the linker having said so

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
; plat_init — the display the terminal draws on.  White on black rather than
; anything prettier, it being what reads on video.
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
    sta VIC_CTRL1               ; display on, which is where the typing starts
    rts

; ---------------------------------------------------------------------------
; plat_cls — a blank screen in the terminal's own colour.
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
;
; This character set holds one case, so a lower case letter is drawn as the
; upper case one.  A device that calls itself One ROM is the reason there is a
; second branch here at all.
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
; plat_scroll — the text area up one row, and the bottom row blanked.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.export plat_scroll
plat_scroll:
    ldx #ROW_TEXT_TOP
@row:
    lda row_off_lo, x
    sta ZP_SCR_LO
    lda row_scr_hi, x
    sta ZP_SCR_HI
    inx
    lda row_off_lo, x
    sta ZP_SRC_LO
    lda row_scr_hi, x
    sta ZP_SRC_HI
    ldy #0
@byte:
    lda (ZP_SRC_LO), y
    sta (ZP_SCR_LO), y
    iny
    cpy #SCREEN_COLS
    bne @byte
    cpx #ROW_TEXT_BOT
    bne @row

    ldy #0                      ; ZP_SRC is the bottom row, now copied up
    lda #' '
@blank:
    sta (ZP_SRC_LO), y
    iny
    cpy #SCREEN_COLS
    bne @blank
    rts

; ---------------------------------------------------------------------------
; plat_key — a key press in ASCII, once per press, or KEY_NONE_CODE.
;
; The matrix says what is held, not what has just been pressed, so a scan that
; finds what the last one found reports nothing.  That is what stops a held key
; from filling the line.
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

; scan — what the matrix holds this instant, in ASCII, or KEY_NONE_CODE.
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
    lda #KEY_LSHIFT_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_LSHIFT_BIT
    beq @yes
    lda #KEY_RSHIFT_COL
    sta CIA1_PRA
    lda CIA1_PRB
    and #KEY_RSHIFT_BIT
    beq @yes
    clc
    rts
@yes:
    sec
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
; A pair covers a whole operation — the session opening, a line going out — not
; a command, so the screen goes dark once per RETURN.  The border is left as it
; is, so what a line costs is the picture for as long as it takes.
;
; Clearing the bit is not enough on its own.  The VIC-II reads it at raster
; line $30 and fetches for the rest of the frame on what it read there, so a
; bit cleared after that line stops nothing until the next frame.  A run that
; lasts seconds would not notice.  A line takes well under a frame, so every
; line would be sent into the fetches this frame was already committed to, and
; a line in a hundred came out of the pipe mangled.  So this waits for line $30
; to come round with the bit already clear, which costs at most a frame.
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
.rodata
; ---------------------------------------------------------------------------

; The keyboard matrix, four bytes an entry: the column select, the row bit, the
; code, and the code a shift gives instead.  A column mask of zero ends it,
; which is never a valid one — a valid mask has exactly one bit clear.  Entries
; are tried in order and the first match wins.
;
; Both shift keys are missing on purpose: they are read by shift_held, and an
; entry for either would match on its own.  So are the keys with nothing to
; send — the function keys, the cursor keys, RUN/STOP, CTRL, the Commodore key,
; HOME, and the three whose characters these screens do not draw as themselves.

key_table:
    .byte %11111110, %00000001, KEY_DEL_CODE, KEY_DEL_CODE     ; INST/DEL
    .byte %11111110, %00000010, KEY_RET_CODE, KEY_RET_CODE     ; RETURN

    .byte %01111111, %00010000, ' ', ' '                   ; SPACE
    .byte %01111111, %00000001, '1', '!'
    .byte %01111111, %00001000, '2', '"'
    .byte %11111101, %00000001, '3', '#'
    .byte %11111101, %00001000, '4', '$'
    .byte %11111011, %00000001, '5', '%'
    .byte %11111011, %00001000, '6', '&'
    .byte %11110111, %00000001, '7', $27                   ; apostrophe
    .byte %11110111, %00001000, '8', '('
    .byte %11101111, %00000001, '9', ')'
    .byte %11101111, %00001000, '0', '0'

    .byte %11111101, %00000100, 'A', 'A'
    .byte %11110111, %00010000, 'B', 'B'
    .byte %11111011, %00010000, 'C', 'C'
    .byte %11111011, %00000100, 'D', 'D'
    .byte %11111101, %01000000, 'E', 'E'
    .byte %11111011, %00100000, 'F', 'F'
    .byte %11110111, %00000100, 'G', 'G'
    .byte %11110111, %00100000, 'H', 'H'
    .byte %11101111, %00000010, 'I', 'I'
    .byte %11101111, %00000100, 'J', 'J'
    .byte %11101111, %00100000, 'K', 'K'
    .byte %11011111, %00000100, 'L', 'L'
    .byte %11101111, %00010000, 'M', 'M'
    .byte %11101111, %10000000, 'N', 'N'
    .byte %11101111, %01000000, 'O', 'O'
    .byte %11011111, %00000010, 'P', 'P'
    .byte %01111111, %01000000, 'Q', 'Q'
    .byte %11111011, %00000010, 'R', 'R'
    .byte %11111101, %00100000, 'S', 'S'
    .byte %11111011, %01000000, 'T', 'T'
    .byte %11110111, %01000000, 'U', 'U'
    .byte %11110111, %10000000, 'V', 'V'
    .byte %11111101, %00000010, 'W', 'W'
    .byte %11111011, %10000000, 'X', 'X'
    .byte %11110111, %00000010, 'Y', 'Y'
    .byte %11111101, %00010000, 'Z', 'Z'

    .byte %11011111, %00000001, '+', '+'
    .byte %11011111, %00001000, '-', '-'
    .byte %10111111, %00000010, '*', '*'
    .byte %10111111, %10000000, '/', '?'
    .byte %10111111, %00100000, '=', '='
    .byte %11011111, %00010000, '.', '>'
    .byte %11011111, %10000000, ',', '<'
    .byte %11011111, %00100000, ':', ':'
    .byte %10111111, %00000100, ';', ';'

    .byte 0
