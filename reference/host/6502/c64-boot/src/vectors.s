; vectors.s — Back-channel fill, interrupt stubs, ROM vectors
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

    .import boot_entry

; ---------------------------------------------------------------------------
; FILL segment — back-channel region ($E000-$E207, 520 bytes of $00)
; ---------------------------------------------------------------------------

.segment "FILL"
    .res 520, $00

; ---------------------------------------------------------------------------
; BOOT segment — irq_nmi_stub runs from ROM
;
; Both NMI and IRQ vectors point here. IRQs are masked by SEI at boot_entry
; and never cleared, so the IRQ vector is a safety net only. NMI (RESTORE)
; cannot be masked; RTI causes it to be silently ignored during boot.
; The stub must be in BOOT (ROM address) so the vectors are valid before
; the CODE segment has been copied to RAM.
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