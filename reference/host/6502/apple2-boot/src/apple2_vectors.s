; apple2_vectors.s — Back-channel fill and ROM vectors
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

    .import boot_entry

; ---------------------------------------------------------------------------
; BCH segment — the back-channel region, 64 bytes of $00 at $FF00.
;
; The device overwrites these bytes while a session is open, so nothing the
; image needs can live here.
; ---------------------------------------------------------------------------

.segment "BCH"
    .res 64, $00

; ---------------------------------------------------------------------------
; MACHID segment — the Apple IIe machine identification bytes
;
; $FBB3 and $FBC0 are where an Apple II program looks to find out which
; machine it is running on, and a IIe answers $06 and $EA.  The twelve bytes
; between them are padding.
;
; Only the EF image covers those addresses.  The 2KB one has real code there.
; ---------------------------------------------------------------------------

.ifdef EF

.segment "MACHID"
    .byte $06                   ; $FBB3
    .res  12, $00               ; $FBB4-$FBBF
    .byte $EA                   ; $FBC0

.endif

; ---------------------------------------------------------------------------
; BOOT segment — irq_nmi_stub runs from ROM
;
; IRQs are masked by SEI at boot_entry and never unmasked, so the IRQ vector
; is a safety net only.  An Apple II motherboard has nothing that raises NMI,
; but a card can, and RTI leaves the boot undisturbed if one does.
; ---------------------------------------------------------------------------

.segment "BOOT"

irq_nmi_stub:
    rti

; ---------------------------------------------------------------------------
; Vector table at $FFFA-$FFFF
; ---------------------------------------------------------------------------

.segment "VECTORS"

    .word irq_nmi_stub      ; $FFFA-$FFFB  NMI
    .word boot_entry        ; $FFFC-$FFFD  RESET
    .word irq_nmi_stub      ; $FFFE-$FFFF  IRQ/BRK
