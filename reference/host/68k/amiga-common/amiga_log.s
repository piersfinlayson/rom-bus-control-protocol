; amiga_log.s — logging through a pipe
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  log_line and log_device say nothing unless VAR_PIPE_PRESENT is
; set, so an application calls them whether or not the device has a pipe.

; ---------------------------------------------------------------------------
; log_open — D0.B = the pipe every log line goes down.
;
; The application finds the pipe and names it here.
; Clobbers: nothing
; ---------------------------------------------------------------------------
log_open:
        MOVE.B  D0,VAR_LOG_PIPE
        CLR.B   VAR_LINE_CUT
        MOVE.B  #1,VAR_PIPE_PRESENT
        RTS

; ---------------------------------------------------------------------------
; log_write — D0.B = count, 1 to 4, from RBCP_ARG0 on, down VAR_LOG_PIPE.
;
; A write the device will not take is sent again, up to LOG_TRIES times.
; PIPE_WRITE is all or nothing, so the same bytes go out again rather than some
; part of them.  A device that refused took none of them.
;
; Bytes that will not go at all leave the line owing a newline, because that
; newline is the only thing separating what did go out from the line after it.
; Output: D0.B = 0 the bytes went, 1 they did not
; Clobbers: D0
; ---------------------------------------------------------------------------
log_write:
        MOVEM.L D1-D3,-(SP)
        MOVE.B  D0,D3                   ; the count, which each go needs again
        MOVEQ   #LOG_TRIES,D2
.lw_again:
        MOVE.B  D3,D0
        MOVE.B  VAR_LOG_PIPE,D1
        BSR     rbcp_cmd_pipe_write
        TST.B   D0
        BEQ.S   .lw_went
        SUBQ.B  #1,D2
        BNE.S   .lw_again
        MOVE.B  #1,VAR_LINE_CUT
        MOVEQ   #1,D0
        BRA.S   .lw_out
.lw_went:
        MOVEQ   #0,D0
.lw_out:
        MOVEM.L (SP)+,D1-D3
        RTS

; ---------------------------------------------------------------------------
; log_break — the newline a cut line owes, before anything else goes out.
;
; What did reach the far end stands as a short line.
; A pipe that will not take even this is a session that has stopped, and the
; log stops with it.
; Output: D0.B = 0 there is nothing owing, 1 the pipe still takes nothing
; Clobbers: D0
; ---------------------------------------------------------------------------
log_break:
        TST.B   VAR_LINE_CUT
        BNE.S   .lb_owed
        MOVEQ   #0,D0
        RTS
.lb_owed:
        MOVE.B  #10,RBCP_ARG0
        MOVEQ   #1,D0
        BSR     log_write
        TST.B   D0
        BNE.S   .lb_out
        CLR.B   VAR_LINE_CUT
.lb_out:
        RTS

; ---------------------------------------------------------------------------
; pipe_puts — A0 = null-terminated string, sent in four-byte chunks.
; Clobbers: nothing
; ---------------------------------------------------------------------------
pipe_puts:
        MOVEM.L D0-D2/A0-A1,-(SP)
        BSR     log_break
        TST.B   D0
        BNE.S   .pp_done
.pp_chunk:
        MOVEQ   #0,D2                   ; bytes gathered
        LEA     (RBCP_ARG0).W,A1
.pp_gather:
        MOVE.B  (A0),D0
        BEQ.S   .pp_flush
        MOVE.B  D0,(A1)+
        ADDQ.L  #1,A0
        ADDQ.B  #1,D2
        CMPI.B  #RBCP_PIPE_WRITE_MAX,D2
        BNE.S   .pp_gather
.pp_flush:
        TST.B   D2
        BEQ.S   .pp_done
        MOVE.B  D2,D0                   ; count
        BSR     log_write
        TST.B   D0
        BNE.S   .pp_done                ; the rest of the string goes with it
        CMPI.B  #RBCP_PIPE_WRITE_MAX,D2
        BEQ.S   .pp_chunk               ; a full chunk, so there may be more
.pp_done:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; log_line — A0 = string, sent with a trailing CRLF where a pipe is present.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_line:
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .ll_done
        BSR     pipe_puts
        BRA.S   log_crlf
.ll_done:
        RTS

; ---------------------------------------------------------------------------
; log_crlf — a CRLF, to end a line.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_crlf:
        MOVE.B  #13,RBCP_ARG0
        MOVE.B  #10,RBCP_ARG1
        MOVEQ   #2,D0
        BRA     log_write

; ---------------------------------------------------------------------------
; log_dec — D0.B = value, sent as one or two decimal digits with no leading
; zero.  Only the flash and RAM slot counts go this way, and neither reaches
; a hundred.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_dec:
        MOVEM.L D2-D3,-(SP)
        MOVEQ   #0,D3                   ; tens
.ld_tens:
        CMPI.B  #10,D0
        BCS.S   .ld_units
        SUBI.B  #10,D0
        ADDQ.B  #1,D3
        BRA.S   .ld_tens
.ld_units:
        ADDI.B  #'0',D0
        TST.B   D3
        BEQ.S   .ld_one
        MOVE.B  D0,RBCP_ARG1            ; units
        ADDI.B  #'0',D3
        MOVE.B  D3,RBCP_ARG0            ; tens
        MOVEQ   #2,D0
        BRA.S   .ld_send
.ld_one:
        MOVE.B  D0,RBCP_ARG0
        MOVEQ   #1,D0
.ld_send:
        BSR     log_write
        MOVEM.L (SP)+,D2-D3
        RTS

; ---------------------------------------------------------------------------
; log_name_end — A0 = name, sent with a closing quote and a CRLF.  The opening
; quote belongs to whatever prefix the caller sent.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_name_end:
        BSR     pipe_puts
        MOVE.B  #'"',RBCP_ARG0
        MOVE.B  #13,RBCP_ARG1
        MOVE.B  #10,RBCP_ARG2
        MOVEQ   #3,D0
        BRA     log_write

; ---------------------------------------------------------------------------
; log_device — one line naming the device and its slot counts.
; Clobbers: D0-D1/A0
; ---------------------------------------------------------------------------
log_device:
        TST.B   VAR_PIPE_PRESENT
        BEQ     .lgd_done
        BSR     rbcp_cmd_get_device_type
        TST.B   D0
        BNE.S   .lgd_counts
        MOVEQ   #24,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        BSR     pipe_puts
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .lgd_sep
        MOVEQ   #24,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (msg_sp).L,A0
        BSR     pipe_puts
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        BSR     pipe_puts
.lgd_sep:
        LEA     (msg_comma).L,A0
        BSR     pipe_puts
.lgd_counts:
        MOVEQ   #0,D0
        MOVE.B  VAR_TOTAL_FLASH,D0
        BSR     log_dec
        LEA     (msg_flash_slots).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  VAR_TOTAL_RAM,D0
        BSR     log_dec
        LEA     (msg_ram_slots).L,A0
        BRA     log_line
.lgd_done:
        RTS
