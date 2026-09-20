; amiga_error.s — the RBCP error screen and its diagnostics
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  err_halt takes D0 = error number, says what went wrong and
; stops.  There is no way back, and the session is in an unknown state.
;
; The application supplies err_msgs, a table of message pointers the error
; number indexes, and draw_title_at, which draws its heading.

; ---------------------------------------------------------------------------
; err_halt — show the error screen and stop
; Input : D0.B = error number
; Does not return.
; ---------------------------------------------------------------------------
err_halt:
        MOVE.B  D0,VAR_ERR_NUM
        ; Every value below describes the command that failed, and every one
        ; of them is gone once the log has sent a byte.  Take the copy first.
        MOVE.B  RBCP_ERROR_CODE,VAR_ES_STAGE
        MOVE.B  RBCP_GROUP,VAR_ES_SGRP
        MOVE.B  RBCP_CMD,VAR_ES_SCMD
        MOVE.B  (RBCP_LASTCMD_GRP_ADDR).L,VAR_ES_DGRP
        MOVE.B  (RBCP_LASTCMD_CMD_ADDR).L,VAR_ES_DCMD
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,VAR_ES_TOK
        MOVE.B  (RBCP_PROGRESS_ADDR).L,VAR_ES_PRG
        MOVE.B  (RBCP_RESPONSE_ADDR).L,VAR_ES_RSP
        BSR     log_error               ; to the pipe, where there is one
    ifne CONFIG_BOOT_CHIME
        BSR     chime_stop              ; nothing left running behind the error
    endc
        ; Draw to the screen itself, wherever this was called from.
        MOVE.L  #BITPLANE_BASE,VAR_DRAW_BASE
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        BSR     screen_clear
        ; The copper writes COLOR00 every frame, so the background changes by
        ; writing the copper list, not the register.
        MOVE.W  #COL_RED,(COPPER_BASE+COP_OFF_COLOR00).W
        MOVE.B  #ERR_TITLE_ROW,D2
        BSR     draw_title_at
        LEA     (str_err).L,A0
        MOVE.B  #ERROR_COL,D1
        MOVE.B  #ERROR_ROW,D2
        BSR     screen_print
        MOVEQ   #0,D1
        MOVE.B  VAR_ERR_NUM,D1
        LSL.W   #2,D1                   ; a long per table entry
        LEA     (err_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        MOVE.B  #ERROR_COL,D1
        MOVE.B  #ERROR_ROW+2,D2
        BSR     screen_print
        BSR     draw_err_diag
.eh_halt:
        BRA.S   .eh_halt

; ---------------------------------------------------------------------------
; draw_err_diag — the raw state when the library gave up, from err_halt's copy.
;
; STAGE is how far the command got: 1 the device never acknowledged it, 2 it
; did but never completed, 3 it completed and reported failure.  SGRP/SCMD are
; the group and command the application was sending.  DGRP/DCMD are the last
; command the device says it processed, so a shifted frame shows as the device
; answering something other than what was asked.  TOK/PRG/RSP are the response
; header.
; Clobbers: nothing
; ---------------------------------------------------------------------------
draw_err_diag:
        MOVEM.L D0-D2/A0,-(SP)

        MOVE.B  #ERROR_ROW+4,D2
        MOVE.B  #ERROR_COL,D1
        LEA     (str_d_stage).L,A0
        MOVE.B  VAR_ES_STAGE,D0
        BSR     diag_field
        ADDQ.B  #2,D1
        LEA     (str_d_sgrp).L,A0
        MOVE.B  VAR_ES_SGRP,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_cmd).L,A0
        MOVE.B  VAR_ES_SCMD,D0
        BSR     diag_field

        MOVE.B  #ERROR_ROW+5,D2
        MOVE.B  #ERROR_COL,D1
        LEA     (str_d_dgrp).L,A0
        MOVE.B  VAR_ES_DGRP,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_cmd).L,A0
        MOVE.B  VAR_ES_DCMD,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_tok).L,A0
        MOVE.B  VAR_ES_TOK,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_prg).L,A0
        MOVE.B  VAR_ES_PRG,D0
        BSR     diag_field
        ADDQ.B  #1,D1
        LEA     (str_d_rsp).L,A0
        MOVE.B  VAR_ES_RSP,D0
        BSR     diag_field

        MOVEM.L (SP)+,D0-D2/A0
        RTS

; diag_field — A0 = label, D0.B = value, D1.B = column, D2.B = row.  Prints
; the label then the value as two hex digits, and leaves D1 past both so the
; next field chains on.  Clobbers D1 deliberately, and saves the rest.
diag_field:
        MOVEM.L D0/D3-D4/A0,-(SP)
        MOVE.B  D0,D4                   ; value
        BSR     screen_print            ; prints at D1, does not move it
.dgf_len:
        TST.B   (A0)+
        BEQ.S   .dgf_gotlen
        ADDQ.B  #1,D1
        BRA.S   .dgf_len
.dgf_gotlen:
        MOVE.B  D4,D0
        BSR     print_hex_byte          ; advances D1 by two
        MOVEM.L (SP)+,D0/D3-D4/A0
        RTS

; print_hex_byte — D0.B as two hex digits at (D1=col, D2=row), D1 advanced by
; two.  Saves everything but D1.
print_hex_byte:
        MOVEM.L D0/D3,-(SP)
        MOVE.B  D0,D3
        LSR.B   #4,D0
        BSR.S   .phb_conv
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVE.B  D3,D0
        ANDI.B  #$0F,D0
        BSR.S   .phb_conv
        BSR     screen_putchar
        ADDQ.B  #1,D1
        MOVEM.L (SP)+,D0/D3
        RTS
.phb_conv:
        CMPI.B  #10,D0
        BCS.S   .phb_dig
        ADDI.B  #'A'-10,D0
        RTS
.phb_dig:
        ADDI.B  #'0',D0
        RTS

; ---------------------------------------------------------------------------
; log_error — the same diagnostics down the pipe, where there is one.  Nothing
; is sent before log_open, because VAR_PIPE_PRESENT is clear until then.
; Clobbers: D0-D1/A0
; ---------------------------------------------------------------------------
log_error:
        TST.B   VAR_PIPE_PRESENT
        BEQ     .lge_done
        LEA     (msg_rule).L,A0
        BSR     log_line
        LEA     (msg_err_pre).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D1
        MOVE.B  VAR_ERR_NUM,D1
        LSL.W   #2,D1
        LEA     (err_msgs).L,A0
        MOVEA.L (A0,D1.W),A0
        BSR     pipe_puts
        BSR     log_crlf
        LEA     (msg_err_st).L,A0       ; "  stage "
        BSR     pipe_puts
        MOVE.B  VAR_ES_STAGE,D0
        BSR     log_hex_byte
        LEA     (msg_err_sent).L,A0     ; " sent "
        BSR     pipe_puts
        MOVE.B  VAR_ES_SGRP,D0
        BSR     log_hex_byte
        LEA     (msg_err_slash).L,A0
        BSR     pipe_puts
        MOVE.B  VAR_ES_SCMD,D0
        BSR     log_hex_byte
        LEA     (msg_err_dev).L,A0      ; " dev "
        BSR     pipe_puts
        MOVE.B  VAR_ES_DGRP,D0
        BSR     log_hex_byte
        LEA     (msg_err_slash).L,A0
        BSR     pipe_puts
        MOVE.B  VAR_ES_DCMD,D0
        BSR     log_hex_byte
        LEA     (msg_err_tok).L,A0      ; " tok "
        BSR     pipe_puts
        MOVE.B  VAR_ES_TOK,D0
        BSR     log_hex_byte
        LEA     (msg_err_prg).L,A0      ; " prg "
        BSR     pipe_puts
        MOVE.B  VAR_ES_PRG,D0
        BSR     log_hex_byte
        LEA     (msg_err_rsp).L,A0      ; " rsp "
        BSR     pipe_puts
        MOVE.B  VAR_ES_RSP,D0
        BSR     log_hex_byte
        BSR     log_crlf
.lge_done:
        RTS

; log_hex_byte — D0.B as two hex digits down the log's pipe.
log_hex_byte:
        MOVEM.L D0/D2-D3,-(SP)
        MOVE.B  D0,D3
        LSR.B   #4,D0
        BSR.S   .lhb_conv
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  D3,D0
        ANDI.B  #$0F,D0
        BSR.S   .lhb_conv
        MOVE.B  D0,RBCP_ARG1
        MOVEQ   #2,D0
        BSR     log_write
        MOVEM.L (SP)+,D0/D2-D3
        RTS
.lhb_conv:
        CMPI.B  #10,D0
        BCS.S   .lhb_dig
        ADDI.B  #'A'-10,D0
        RTS
.lhb_dig:
        ADDI.B  #'0',D0
        RTS
