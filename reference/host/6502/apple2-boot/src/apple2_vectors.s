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
