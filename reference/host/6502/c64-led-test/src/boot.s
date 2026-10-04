; boot.s — reset entry, the unpack into RAM and the vectors
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Everything after boot_entry runs from RAM.  The command page is a page of the
; served socket, so an instruction fetched from the image could send a command
; byte.  After the knock the host reads the socket only on the command page and
; the back channel.
;
; The 8KB images contain CODE and RODATA packed by tools/pack_rom.py.  The 16KB
; image copies them separately because they are in different halves.

    .include "led_defs.s"

.import main

.import c64_hw_init

.import __CODE_RUN__, __CODE_SIZE__
.import __RODATA_SIZE__

.ifdef PACKED
.import __BOOT_LOAD__, __BOOT_SIZE__
.else
.import __CODE_LOAD__
.import __RODATA_LOAD__, __RODATA_RUN__
.endif

; ===========================================================================
; FILL segment — the command page, then the back-channel region
; ===========================================================================

; A BASIC socket image is entered through the word at $A000 once the machine's
; own kernal has reset.  That word is in the command page, which is harmless
; because the device decodes commands from the address read, not its contents.

.segment "FILL"

.ifdef BASIC_SOCKET
    .word boot_entry            ; $A000-$A001  BASIC cold start
    .res 766, $00
.else
    .res 768, $00
.endif

; ===========================================================================
; BOOT segment — runs from ROM, before there is anything in RAM
; ===========================================================================

.segment "BOOT"

; ---------------------------------------------------------------------------
; boot_entry — reset entry.
;
; Interrupts are masked here and never unmasked.  One in the middle of a
; command frame would stretch it.
; ---------------------------------------------------------------------------

.export boot_entry
boot_entry:
    sei
    cld
    ldx #$FF
    txs

    jsr c64_hw_init             ; in BOOT, so present before the unpack

.ifdef PACKED
    lda #<(__BOOT_LOAD__ + __BOOT_SIZE__)
    sta ZP_PTR_LO
    lda #>(__BOOT_LOAD__ + __BOOT_SIZE__)
    sta ZP_PTR_HI
    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1
    lda #<(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP2
    lda #>(__CODE_SIZE__ + __RODATA_SIZE__)
    sta ZP_TMP3
    jsr unpack
.else
    lda #<__CODE_LOAD__
    sta ZP_PTR_LO
    lda #>__CODE_LOAD__
    sta ZP_PTR_HI
    lda #<__CODE_RUN__
    sta ZP_TMP0
    lda #>__CODE_RUN__
    sta ZP_TMP1
    lda #<__CODE_SIZE__
    sta ZP_TMP2
    lda #>__CODE_SIZE__
    sta ZP_TMP3
    jsr copy_block

    lda #<__RODATA_LOAD__
    sta ZP_PTR_LO
    lda #>__RODATA_LOAD__
    sta ZP_PTR_HI
    lda #<__RODATA_RUN__
    sta ZP_TMP0
    lda #>__RODATA_RUN__
    sta ZP_TMP1
    lda #<__RODATA_SIZE__
    sta ZP_TMP2
    lda #>__RODATA_SIZE__
    sta ZP_TMP3
    jsr copy_block
.endif

.ifdef BASIC_SOCKET
    lda #<basic_nmi             ; the image is in RAM, so this address is live
    sta NMINV
    lda #>basic_nmi
    sta NMINV + 1
.endif

    jmp main

.ifdef PACKED

; ---------------------------------------------------------------------------
; Zero page for unpack, borrowed from the application before it starts.
; ---------------------------------------------------------------------------

UNP_FLAGS   = ZP_TMP4           ; the flag byte, shifted right as it is used
UNP_LEFT    = ZP_APP0           ; flags left in it
UNP_BACK_LO = ZP_APP1           ; the match source
UNP_BACK_HI = ZP_APP2
UNP_LEN     = ZP_APP3           ; match bytes left to copy

; ---------------------------------------------------------------------------
; unpack — the packed stream at ZP_PTR_LO/HI out to ZP_TMP0/1 until ZP_TMP2/3
; bytes have been written.  The format is in tools/pack_rom.py.  Clobbers A,
; Y and the zero page above.
; ---------------------------------------------------------------------------

unpack:
    ldy #0                      ; stays 0 throughout
    sty UNP_LEFT                ; forces a flag fetch on the first item
@item:
    lda UNP_LEFT
    bne @have_flags
    jsr next_byte
    sta UNP_FLAGS
    lda #8
    sta UNP_LEFT
@have_flags:
    dec UNP_LEFT
    lsr UNP_FLAGS
    bcc @match

    jsr next_byte               ; a set bit is a literal
    jsr put
    jmp @more

@match:
    jsr next_byte
    sta UNP_BACK_LO             ; the distance back, low eight bits
    jsr next_byte
    pha
    and #$0F
    clc
    adc #3
    sta UNP_LEN
    pla
    lsr a
    lsr a
    lsr a
    lsr a
    sta UNP_BACK_HI             ; and its top four

    clc                         ; the stream's distance is one less, and
    lda ZP_TMP0                 ; sbc with carry clear subtracts one more
    sbc UNP_BACK_LO
    sta UNP_BACK_LO
    lda ZP_TMP1
    sbc UNP_BACK_HI
    sta UNP_BACK_HI
@copy:
    lda (UNP_BACK_LO), y
    jsr put
    inc UNP_BACK_LO
    bne @same_page
    inc UNP_BACK_HI
@same_page:
    dec UNP_LEN
    bne @copy

@more:
    lda ZP_TMP2
    ora ZP_TMP3
    bne @item
    rts

; ---------------------------------------------------------------------------
; next_byte — the next byte of the stream, in A.  Clobbers A and ZP_PTR.
; ---------------------------------------------------------------------------

next_byte:
    lda (ZP_PTR_LO), y
    inc ZP_PTR_LO
    bne @same_page
    inc ZP_PTR_HI
@same_page:
    rts

; ---------------------------------------------------------------------------
; put — A to the output, counting it off.  Clobbers A and ZP_TMP0-3.
; ---------------------------------------------------------------------------

put:
    sta (ZP_TMP0), y
    inc ZP_TMP0
    bne @same_page
    inc ZP_TMP1
@same_page:
    lda ZP_TMP2
    bne @dec_lo
    dec ZP_TMP3
@dec_lo:
    dec ZP_TMP2
    rts

.else

; ---------------------------------------------------------------------------
; copy_block — ZP_TMP2/3 bytes from ZP_PTR_LO/HI to ZP_TMP0/1.
; Clobbers A, Y and all four pointers.
; ---------------------------------------------------------------------------

copy_block:
    ldy #0
@byte:
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
    bne @byte
    rts

.endif

; ---------------------------------------------------------------------------
; The interrupt stub and the vector table.  A BASIC socket image doesn't
; contain the vectors, so RESTORE is handled through $0318.  See basic_nmi.
; ---------------------------------------------------------------------------

.ifndef BASIC_SOCKET

; RESTORE, and the interrupts that stay masked.  The stub is in ROM so it is
; valid from reset.  It is the only code fetched from the served image during a
; session, and it isn't on the command page, so its reads aren't command bytes.
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

.ifdef BASIC_SOCKET

.code

; ---------------------------------------------------------------------------
; basic_nmi — RESTORE, on the BASIC socket image.
;
; NMI isn't maskable.  The kernal's handler jumps through ($A002) when RUN/STOP
; is held, and $A002 is in the command page, so those two reads would reach an
; open frame as command bytes.  Pointing $0318 here skips that handler.
; ---------------------------------------------------------------------------

basic_nmi:
    rti

.endif
