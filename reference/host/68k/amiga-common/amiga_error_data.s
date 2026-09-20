; amiga_error_data.s — the error heading and the rule the log prints
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.

        EVEN
str_err:
        DC.B    "RBCP ERROR",0
        EVEN
msg_rule:
        DC.B    "-----",0
