; amiga_log_data.s — the pieces a device line is built from
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.

        EVEN
msg_sp:
        DC.B    " ",0
        EVEN
msg_comma:
        DC.B    ", ",0
        EVEN
msg_flash_slots:
        DC.B    " flash ROM slots, ",0
        EVEN
msg_ram_slots:
        DC.B    " RAM slots",0
