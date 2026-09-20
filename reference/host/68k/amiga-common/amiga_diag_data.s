; amiga_diag_data.s — the diagnostic field labels
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.  The same fields on screen and down the pipe.

; Field labels for the screen.
        EVEN
str_d_stage:
        DC.B    "STAGE:",0
        EVEN
str_d_sgrp:
        DC.B    "SGRP:",0
        EVEN
str_d_cmd:
        DC.B    "CMD:",0
        EVEN
str_d_dgrp:
        DC.B    "DGRP:",0
        EVEN
str_d_tok:
        DC.B    "TOK:",0
        EVEN
str_d_prg:
        DC.B    "PRG:",0
        EVEN
str_d_rsp:
        DC.B    "RSP:",0
        EVEN

; The same labels for the pipe, with the line's opening text and its separator.
msg_err_pre:
        DC.B    "RBCP ERROR: ",0
        EVEN
msg_err_st:
        DC.B    "  stage ",0
        EVEN
msg_err_sent:
        DC.B    " sent ",0
        EVEN
msg_err_slash:
        DC.B    "/",0
        EVEN
msg_err_dev:
        DC.B    " dev ",0
        EVEN
msg_err_tok:
        DC.B    " tok ",0
        EVEN
msg_err_prg:
        DC.B    " prg ",0
        EVEN
msg_err_rsp:
        DC.B    " rsp ",0
        EVEN
