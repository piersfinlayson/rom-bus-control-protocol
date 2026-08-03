; rbcp.s — RBCP protocol library for 68K hosts
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Include rbcp_config.s then rbcp_defs.s before this file.
;
; Calling convention
; ------------------
; All public routines preserve every register they use (callee-save) except
; where documented.  D0 is the return value: 0 (Z set) on success, non-zero
; (Z clear) on failure.  Callers set RBCP_GROUP, RBCP_CMD and RBCP_ARG0-N in
; scratch RAM before calling command helpers, mirroring the 6502 ZP
; convention.
;
; Execution environment
; ---------------------
; This code MUST execute from RAM, not from the ROM the device is serving.
; Instruction fetches from that ROM place their own addresses on the bus,
; and outside command-response mode the device treats every address read as
; command data.  Once command-response mode is established the device
; filters on the command page, so ROM fetches outside that page become
; harmless — but the knock and the ENTER_CMD_RESP that establish it do not
; have that protection.
;
; Sending a command byte
; ----------------------
; No self-modification is needed on the 68K.  A read at
;   CONFIG_RBCP_CMD_PAGE_ABS + (byte << CONFIG_RBCP_BUS_SHIFT)
; presents the byte on the address lines the device observes as A0-A7.  See
; the BUS MAPPING commentary in rbcp_defs.s for why the shift is there: the
; device's observed A0 is the CPU line immediately above the bus byte-select
; lines, so one command byte advances the CPU address by one bus cycle.
; The data returned by the read is discarded.

; ---------------------------------------------------------------------------
; rbcp_send_byte_internal — encode one byte as a ROM address read
; Input : D0.B = byte to place on the device's A0-A7
;         A5   = CONFIG_RBCP_CMD_PAGE_ABS (must be set up by caller)
; Output: read data discarded
; Clobbers: D1
; ---------------------------------------------------------------------------
rbcp_send_byte_internal:
        MOVEQ   #0,D1
        MOVE.B  D0,D1
        LSL.W   #CONFIG_RBCP_BUS_SHIFT,D1   ; byte index -> CPU byte offset
        MOVE.W  (A5,D1.W),D1                ; the read IS the transmission
        RTS

; ---------------------------------------------------------------------------
; rbcp_knock — send the six-byte "!RBCP!" knock sequence
; Clobbers (saved/restored): D0/D1/A5
; ---------------------------------------------------------------------------
rbcp_knock:
        MOVEM.L D0-D1/A5,-(SP)
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5
        MOVEQ   #RBCP_KNOCK_0,D0
        BSR.S   rbcp_send_byte_internal
        MOVEQ   #RBCP_KNOCK_1,D0
        BSR.S   rbcp_send_byte_internal
        MOVEQ   #RBCP_KNOCK_2,D0
        BSR.S   rbcp_send_byte_internal
        MOVEQ   #RBCP_KNOCK_3,D0
        BSR.S   rbcp_send_byte_internal
        MOVEQ   #RBCP_KNOCK_4,D0
        BSR.S   rbcp_send_byte_internal
        MOVEQ   #RBCP_KNOCK_5,D0
        BSR.S   rbcp_send_byte_internal
        MOVEM.L (SP)+,D0-D1/A5
        RTS

; ---------------------------------------------------------------------------
; rbcp_send_cmd — send GROUP, CMD and argument bytes as ROM reads
; Input : D0.B = argument count (0-9)
;         RBCP_GROUP, RBCP_CMD set in scratch RAM
;         RBCP_ARG0..N populated as needed
; Clobbers (saved/restored): D0-D2/A0/A5
; ---------------------------------------------------------------------------
rbcp_send_cmd:
        MOVEM.L D0-D2/A0/A5,-(SP)
        MOVE.B  D0,D2               ; save argument count
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5

        MOVE.B  RBCP_GROUP,D0
        BSR.S   rbcp_send_byte_internal

        MOVE.B  RBCP_CMD,D0
        BSR.S   rbcp_send_byte_internal

        TST.B   D2
        BEQ.S   .rsc_done
        MOVEA.L #RBCP_ARG0,A0
        MOVEQ   #0,D1
        MOVE.B  D2,D1
        SUBQ.W  #1,D1
.rsc_loop:
        MOVE.B  (A0)+,D0
        BSR.S   rbcp_send_byte_internal
        DBF     D1,.rsc_loop
.rsc_done:
        MOVEM.L (SP)+,D0-D2/A0/A5
        RTS

; ---------------------------------------------------------------------------
; rbcp_save_token — snapshot current token LSB to scratch RAM
;
; The LSB alone is read.  The specification guarantees atomicity only for
; individual byte writes, so the 16-bit token must never be read as a word:
; a word read can catch the LSB updated and the MSB not.  The polling
; sequence needs only the LSB.
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
rbcp_save_token:
        MOVEM.L D0,-(SP)
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        MOVE.B  D0,RBCP_SAVED_TOK
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_poll_token — poll until token LSB differs from the saved value
; Output: D0=0/Z=1 success, D0=1/Z=0 timeout
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
rbcp_poll_token:
        MOVEM.L D1-D2,-(SP)
        MOVE.B  RBCP_SAVED_TOK,D2
        MOVE.L  #CONFIG_RBCP_POLL_TIMEOUT,D1
        BEQ.S   .rpt_inf               ; 0 = wait forever
.rpt_loop:
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        CMP.B   D2,D0
        BNE.S   .rpt_ok
        SUBQ.L  #1,D1
        BNE.S   .rpt_loop
        MOVEQ   #1,D0                  ; timeout
        MOVEM.L (SP)+,D1-D2
        RTS
.rpt_inf:
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        CMP.B   D2,D0
        BEQ.S   .rpt_inf
.rpt_ok:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; rbcp_poll_progress — poll until progress = RBCP_COMPLETE
; Output: D0=0/Z=1 success, D0=1/Z=0 timeout
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
rbcp_poll_progress:
        MOVEM.L D1-D2,-(SP)
        MOVE.B  #RBCP_COMPLETE,D2   ; MOVEQ sign-extends; $BB > 127
        MOVE.L  #CONFIG_RBCP_POLL_TIMEOUT,D1
        BEQ.S   .rpp_inf
.rpp_loop:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BEQ.S   .rpp_ok
        SUBQ.L  #1,D1
        BNE.S   .rpp_loop
        MOVEQ   #1,D0
        MOVEM.L (SP)+,D1-D2
        RTS
.rpp_inf:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BNE.S   .rpp_inf
.rpp_ok:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; rbcp_poll_progress_long — as rbcp_poll_progress with the NV timeout
; Used for NV write commands, where a flash erase can take milliseconds.
; Output: D0=0/Z=1 success, D0=1/Z=0 timeout
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
rbcp_poll_progress_long:
        MOVEM.L D1-D2,-(SP)
        MOVE.B  #RBCP_COMPLETE,D2
        MOVE.L  #CONFIG_RBCP_NV_POLL_TIMEOUT,D1
        BEQ.S   .rppl_inf
.rppl_loop:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BEQ.S   .rppl_ok
        SUBQ.L  #1,D1
        BNE.S   .rppl_loop
        MOVEQ   #1,D0
        MOVEM.L (SP)+,D1-D2
        RTS
.rppl_inf:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BNE.S   .rppl_inf
.rppl_ok:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; rbcp_check_response — verify the response field = RBCP_STATUS_OK
; Output: D0=0/Z=1 success, D0=1/Z=0 failed
; Clobbers: D0
; ---------------------------------------------------------------------------
rbcp_check_response:
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0
        CMP.B   #RBCP_STATUS_OK,D0
        BNE.S   .rcr_fail
        MOVEQ   #0,D0
        RTS
.rcr_fail:
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_issue_cmd_long_poll — full command issue cycle, NV progress timeout
; rbcp_issue_cmd           — full command issue cycle, normal timeout
; rbcp_issue_cmd_body      — shared body (do not call directly)
;
; Implements the host polling sequence from the specification: snapshot the
; token LSB, send the command, poll the token, poll progress, read response.
;
; Input : D0.B = argument count
;         RBCP_GROUP, RBCP_CMD, RBCP_ARG0..N set by caller
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         RBCP_ERROR_CODE: 1=token timeout, 2=progress timeout, 3=FAILED
; ---------------------------------------------------------------------------
rbcp_issue_cmd_long_poll:
        MOVE.B  D0,RBCP_ARG_COUNT
        MOVE.B  #1,RBCP_LONG_POLL
        BRA.S   rbcp_issue_cmd_body

rbcp_issue_cmd:
        MOVE.B  D0,RBCP_ARG_COUNT
        CLR.B   RBCP_LONG_POLL
        ; fall through

rbcp_issue_cmd_body:
        CLR.B   RBCP_ERROR_CODE
        MOVE.B  #CONFIG_RBCP_TIMEOUT_RETRIES,RBCP_RETRY_CNT

.ric_tok_attempt:
        BSR     rbcp_save_token
        MOVE.B  RBCP_ARG_COUNT,D0
        BSR     rbcp_send_cmd
        BSR     rbcp_poll_token
        TST.B   D0
        BEQ.S   .ric_tok_ok
        TST.B   RBCP_RETRY_CNT
        BEQ.S   .ric_tok_fail
        SUBQ.B  #1,RBCP_RETRY_CNT
        BRA.S   .ric_tok_attempt
.ric_tok_fail:
        MOVE.B  #RBCP_ERR_TOKEN,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_TOKEN,D0
        RTS

.ric_tok_ok:
        TST.B   RBCP_LONG_POLL
        BNE.S   .ric_long
        BSR     rbcp_poll_progress
        BRA.S   .ric_prog_done
.ric_long:
        BSR     rbcp_poll_progress_long
.ric_prog_done:
        TST.B   D0
        BEQ.S   .ric_prog_ok
        MOVE.B  #RBCP_ERR_PROGRESS,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_PROGRESS,D0
        RTS

.ric_prog_ok:
        BSR     rbcp_check_response
        TST.B   D0
        BEQ.S   .ric_ok
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_RESPONSE,D0
        RTS
.ric_ok:
        MOVEQ   #0,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_pause — busy-wait delay for inter-command gaps in command mode
; Clobbers (saved/restored): D0
; ---------------------------------------------------------------------------
rbcp_pause:
        MOVEM.L D0,-(SP)
        MOVE.L  #CONFIG_RBCP_CMD_PAUSE,D0
        BEQ.S   .rp_done
.rp_loop:
        SUBQ.L  #1,D0
        BNE.S   .rp_loop
.rp_done:
        MOVEM.L (SP)+,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_reset_noknock — send RBCP_RESET without a preceding knock
; Group $AA, command $AA, no arguments.
;
; Sent on the command page: if the device is in command-response mode it is
; filtering command bytes by page, and a reset sent anywhere else would be
; ignored — which is precisely the state the reset needs to recover from.
; Clobbers (saved/restored): D0-D1/A5
; ---------------------------------------------------------------------------
rbcp_cmd_reset_noknock:
        MOVEM.L D0-D1/A5,-(SP)
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5
        MOVE.B  #RBCP_GRP_RESET,D0      ; MOVEQ sign-extends; $AA > 127
        BSR     rbcp_send_byte_internal
        MOVE.B  #RBCP_CMD_RESET,D0
        BSR     rbcp_send_byte_internal
        MOVEM.L (SP)+,D0-D1/A5
        RTS

; ---------------------------------------------------------------------------
; rbcp_reset — the three-stage reset sequence from the specification
;
; Stage 1: 5 x RBCP_RESET, no knock — flushes any in-progress command
;   pause  — allow that command to complete
; Stage 2: 1 x RBCP_RESET, no knock — resets the now-idle device
;   pause  — allow the reset to settle
; Stage 3: knock + RBCP_RESET       — covers the command-response-mode case
;   pause  — allow the reset to settle
;
; The stages are individually exported for diagnostics.
; Clobbers (saved/restored): D0/D1 via sub-routines
; ---------------------------------------------------------------------------
rbcp_reset_stage1:
        MOVEM.L D0-D1,-(SP)
        MOVEQ   #5-1,D0
.rs1_loop:
        BSR     rbcp_cmd_reset_noknock
        DBF     D0,.rs1_loop
        MOVEM.L (SP)+,D0-D1
        RTS

rbcp_reset_stage2:
        BRA     rbcp_cmd_reset_noknock  ; tail call; saves/restores registers

rbcp_reset_stage3:
        BSR     rbcp_knock
        BRA     rbcp_cmd_reset_noknock  ; tail call

rbcp_reset:
        BSR     rbcp_reset_stage1
        BSR     rbcp_pause
        BSR     rbcp_reset_stage2
        BSR     rbcp_pause
        BSR     rbcp_reset_stage3
        BSR     rbcp_pause
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_enter_cmd_resp — knock + ENTER_CMD_RESP with config-derived args
;
; The knock is required: this opens a new session.  All nine arguments come
; from rbcp_config.s, via the values rbcp_defs.s derives from it — note that
; the command page and back-channel start are expressed in the DEVICE's
; terms, not the CPU's.
;
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         RBCP_ERROR_CODE holds the stage on failure.
; ---------------------------------------------------------------------------
rbcp_cmd_enter_cmd_resp:
        CLR.B   RBCP_ERROR_CODE

        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_ENTER_CMD_RESP,RBCP_CMD

        ; A0/A1: command page (16-bit LE)
        MOVE.B  #(RBCP_CMD_PAGE_REL&$FF),RBCP_ARG0
        MOVE.B  #((RBCP_CMD_PAGE_REL>>8)&$FF),RBCP_ARG1

        ; A2/A3/A4: back-channel start, device byte offset in slot (24-bit LE)
        MOVE.B  #(RBCP_BCH_START&$FF),RBCP_ARG2
        MOVE.B  #((RBCP_BCH_START>>8)&$FF),RBCP_ARG3
        MOVE.B  #((RBCP_BCH_START>>16)&$FF),RBCP_ARG4

        ; A5/A6: back-channel size in device bytes (16-bit LE)
        MOVE.B  #(CONFIG_RBCP_BCH_SIZE&$FF),RBCP_ARG5
        MOVE.B  #((CONFIG_RBCP_BCH_SIZE>>8)&$FF),RBCP_ARG6

        ; A7/A8: complete and status-OK sentinel values
        MOVE.B  #RBCP_COMPLETE,RBCP_ARG7
        MOVE.B  #RBCP_STATUS_OK,RBCP_ARG8

        MOVE.B  #CONFIG_RBCP_TIMEOUT_RETRIES,RBCP_RETRY_CNT

.ece_attempt:
        BSR     rbcp_save_token
        BSR     rbcp_knock              ; opens the session
        MOVEQ   #9,D0
        BSR     rbcp_send_cmd
        BSR     rbcp_poll_token
        TST.B   D0
        BEQ.S   .ece_tok_ok
        TST.B   RBCP_RETRY_CNT
        BEQ.S   .ece_tok_fail
        SUBQ.B  #1,RBCP_RETRY_CNT
        BRA.S   .ece_attempt
.ece_tok_fail:
        MOVE.B  #RBCP_ERR_TOKEN,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_TOKEN,D0
        RTS
.ece_tok_ok:
        BSR     rbcp_poll_progress
        TST.B   D0
        BEQ.S   .ece_prog_ok
        MOVE.B  #RBCP_ERR_PROGRESS,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_PROGRESS,D0
        RTS
.ece_prog_ok:
        BSR     rbcp_check_response
        TST.B   D0
        BEQ.S   .ece_ok
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #RBCP_ERR_RESPONSE,D0
        RTS
.ece_ok:
        MOVEQ   #0,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_nop — NOP in command-response mode; proves the device is alive
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
; ---------------------------------------------------------------------------
rbcp_cmd_nop:
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_NOP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_exit_cmd_resp_ack — leave command-response mode, acknowledged
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
; ---------------------------------------------------------------------------
rbcp_cmd_exit_cmd_resp_ack:
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_EXIT_CMD_RESP_ACK,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd
