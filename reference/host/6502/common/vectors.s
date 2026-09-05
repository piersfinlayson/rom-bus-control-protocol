; vectors.s — Back-channel fill, interrupt stubs, ROM vectors
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; A kernal socket image holds the 6502 vector table at $FFFA and is entered at
; reset.  A BASIC socket image (BASIC_SOCKET) has neither - the kernal enters
; BASIC through the word at $A000, and the interrupt vectors stay the kernal's.

    .import boot_entry

; ---------------------------------------------------------------------------
; FILL segment — the command page, then the 768 byte back-channel region
; ---------------------------------------------------------------------------

.segment "FILL"

.ifdef BASIC_SOCKET
    .word boot_entry        ; $A000-$A001  BASIC cold start
    .res 766, $00
.else
    .res 768, $00
.endif

; ---------------------------------------------------------------------------
; BOOT segment — irq_nmi_stub runs from ROM
;
; Both NMI and IRQ vectors point here. IRQs are masked by SEI at boot_entry
; and never cleared, so the IRQ vector is a safety net only. NMI (RESTORE)
; cannot be masked; RTI causes it to be silently ignored during boot.
; The stub must be in BOOT (ROM address) so the vectors are valid before
; the CODE segment has been copied to RAM.
; ---------------------------------------------------------------------------

.ifndef BASIC_SOCKET

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

.endif
