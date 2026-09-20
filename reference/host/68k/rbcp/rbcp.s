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
; A read at
;   CONFIG_RBCP_CMD_PAGE_ABS + (byte << CONFIG_RBCP_BUS_SHIFT)
; presents the byte on the address lines the device observes as A0-A7.  See
; the BUS MAPPING commentary in rbcp_defs.s for why the shift is there: the
; device's observed A0 is the CPU line immediately above the bus byte-select
; lines, so one command byte advances the CPU address by one bus cycle.
; The data returned by the read is discarded.

; ---------------------------------------------------------------------------
; RBCP_SEND_BYTE — encode one byte as a ROM address read
; Argument: the byte, in any addressing mode MOVE.B can read
; Input : A5 = CONFIG_RBCP_CMD_PAGE_ABS (must be set up by caller)
; Output: read data discarded
; Clobbers: D1
;
; A macro, not a subroutine.  On a 16-bit bus the four instructions take 34
; cycles from an immediate byte, and a BSR with its RTS takes another 34, so a
; call doubles the cost of sending a byte.
;
; MOVEQ clears the whole register before the byte goes in, so a byte above
; 127 does not arrive sign-extended.
; ---------------------------------------------------------------------------
RBCP_SEND_BYTE MACRO
        MOVEQ   #0,D1
        MOVE.B  \1,D1
        LSL.W   #CONFIG_RBCP_BUS_SHIFT,D1   ; byte index -> CPU byte offset
        MOVE.W  (A5,D1.W),D1                ; the read IS the transmission
        ENDM

; ---------------------------------------------------------------------------
; rbcp_knock — send the six-byte "!RBCP!" knock sequence
; Clobbers (saved/restored): D1/A5
; ---------------------------------------------------------------------------
rbcp_knock:
        MOVEM.L D1/A5,-(SP)
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5
        RBCP_SEND_BYTE #RBCP_KNOCK_0
        RBCP_SEND_BYTE #RBCP_KNOCK_1
        RBCP_SEND_BYTE #RBCP_KNOCK_2
        RBCP_SEND_BYTE #RBCP_KNOCK_3
        RBCP_SEND_BYTE #RBCP_KNOCK_4
        RBCP_SEND_BYTE #RBCP_KNOCK_5
        MOVEM.L (SP)+,D1/A5
        RTS

; ---------------------------------------------------------------------------
; rbcp_send_cmd — send GROUP, CMD and argument bytes as ROM reads
; Input : D0.B = argument count (0-9)
;         RBCP_GROUP, RBCP_CMD set in scratch RAM
;         RBCP_ARG0..N populated as needed
; Clobbers (saved/restored): D1-D2/A0/A5
;
; rbcp_send_cmd_core is the same code without the guard, for a caller that has
; already saved those four registers.  rbcp_issue_cmd_body has, and calling the
; core from there saves the 84 cycles the MOVEM pair costs.
; ---------------------------------------------------------------------------
rbcp_send_cmd:
        MOVEM.L D1-D2/A0/A5,-(SP)
        BSR.S   rbcp_send_cmd_core
        MOVEM.L (SP)+,D1-D2/A0/A5
        RTS

rbcp_send_cmd_core:
        MOVEQ   #0,D2               ; count clean for a later word DBF
        MOVE.B  D0,D2               ; argument count
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5

        RBCP_SEND_BYTE RBCP_GROUP
        RBCP_SEND_BYTE RBCP_CMD

        TST.B   D2
        BEQ.S   .rsc_done
        MOVEA.L #RBCP_ARG0,A0
        ; The loop counter lives in D2, not D1.  RBCP_SEND_BYTE ends with
        ; MOVE.W (A5,D1.W),D1, so D1 comes back holding whatever the ROM
        ; returned.  D2 it leaves alone.
        SUBQ.W  #1,D2
.rsc_loop:
        RBCP_SEND_BYTE (A0)+
        DBF     D2,.rsc_loop
.rsc_done:
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
;
; rbcp_poll_token_core is the same code without the guard.
; ---------------------------------------------------------------------------
rbcp_poll_token:
        MOVEM.L D1-D2,-(SP)
        BSR.S   rbcp_poll_token_core
        MOVEM.L (SP)+,D1-D2
        RTS

rbcp_poll_token_core:
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
        RTS
.rpt_inf:
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        CMP.B   D2,D0
        BEQ.S   .rpt_inf
.rpt_ok:
        MOVEQ   #0,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_poll_progress      — poll until progress = RBCP_COMPLETE
; rbcp_poll_progress_long — the same on the NV timeout, for NV write commands,
;                           where a flash erase can take milliseconds
; rbcp_poll_progress_aux  — the same on the auxiliary timeout, for SET_AUX,
;                           where the device holds the pin before it answers
; rbcp_poll_progress_core — the loop the three share, with no guard.
;                           Input: D1.L = poll turns, 0 to wait forever
; Output: D0=0/Z=1 success, D0=1/Z=0 timeout
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
rbcp_poll_progress:
        MOVEM.L D1-D2,-(SP)
        MOVE.L  #CONFIG_RBCP_POLL_TIMEOUT,D1
        BSR.S   rbcp_poll_progress_core
        MOVEM.L (SP)+,D1-D2
        RTS

rbcp_poll_progress_long:
        MOVEM.L D1-D2,-(SP)
        MOVE.L  #CONFIG_RBCP_NV_POLL_TIMEOUT,D1
        BSR.S   rbcp_poll_progress_core
        MOVEM.L (SP)+,D1-D2
        RTS

rbcp_poll_progress_aux:
        MOVEM.L D1-D2,-(SP)
        MOVE.L  #CONFIG_RBCP_AUX_POLL_TIMEOUT,D1
        BSR.S   rbcp_poll_progress_core
        MOVEM.L (SP)+,D1-D2
        RTS

rbcp_poll_progress_core:
        MOVE.B  #RBCP_COMPLETE,D2   ; MOVEQ sign-extends a value above 127
        TST.L   D1
        BEQ.S   .rpp_inf
.rpp_loop:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BEQ.S   .rpp_ok
        SUBQ.L  #1,D1
        BNE.S   .rpp_loop
        MOVEQ   #1,D0
        RTS
.rpp_inf:
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        CMP.B   D2,D0
        BNE.S   .rpp_inf
.rpp_ok:
        MOVEQ   #0,D0
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
; rbcp_issue_cmd_aux_poll  — the same on the auxiliary progress timeout
; rbcp_issue_cmd           — the same on the normal progress timeout
; rbcp_issue_cmd_body      — shared body (do not call directly)
;
; Implements the host polling sequence from the specification: snapshot the
; token LSB, send the command, poll the token, poll progress, read response.
;
; The body guards D1-D2/A0/A5 once for the whole sequence and then calls the
; unguarded cores, so the frame pays for one MOVEM pair rather than four.  The
; token snapshot is one instruction and the response check two, so both are
; written out rather than called.
;
; Input : D0.B = argument count
;         RBCP_GROUP, RBCP_CMD, RBCP_ARG0..N set by caller
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         RBCP_ERROR_CODE: 1=token timeout, 2=progress timeout, 3=device
;         reported failure
; ---------------------------------------------------------------------------
rbcp_issue_cmd_long_poll:
        MOVE.B  D0,RBCP_ARG_COUNT
        MOVE.B  #RBCP_POLL_NV,RBCP_POLL_KIND
        BRA.S   rbcp_issue_cmd_body

rbcp_issue_cmd_aux_poll:
        MOVE.B  D0,RBCP_ARG_COUNT
        MOVE.B  #RBCP_POLL_AUX,RBCP_POLL_KIND
        BRA.S   rbcp_issue_cmd_body

rbcp_issue_cmd:
        MOVE.B  D0,RBCP_ARG_COUNT
        CLR.B   RBCP_POLL_KIND
        ; fall through

rbcp_issue_cmd_body:
        MOVEM.L D1-D2/A0/A5,-(SP)
        CLR.B   RBCP_ERROR_CODE
        MOVE.B  #CONFIG_RBCP_TIMEOUT_RETRIES,RBCP_RETRY_CNT

.ric_tok_attempt:
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,RBCP_SAVED_TOK  ; rbcp_save_token
        MOVE.B  RBCP_ARG_COUNT,D0
        BSR     rbcp_send_cmd_core
        BSR     rbcp_poll_token_core    ; leaves Z set on success, so no TST
        BEQ.S   .ric_tok_ok
        TST.B   RBCP_RETRY_CNT
        BEQ.S   .ric_tok_fail
        SUBQ.B  #1,RBCP_RETRY_CNT
        BRA.S   .ric_tok_attempt
.ric_tok_fail:
        MOVEQ   #RBCP_ERR_TOKEN,D0
        BRA.S   .ric_fail

.ric_tok_ok:
        MOVE.L  #CONFIG_RBCP_POLL_TIMEOUT,D1
        MOVE.B  RBCP_POLL_KIND,D0
        BEQ.S   .ric_poll
        CMPI.B  #RBCP_POLL_AUX,D0
        BEQ.S   .ric_aux
        MOVE.L  #CONFIG_RBCP_NV_POLL_TIMEOUT,D1
        BRA.S   .ric_poll
.ric_aux:
        MOVE.L  #CONFIG_RBCP_AUX_POLL_TIMEOUT,D1
.ric_poll:
        BSR     rbcp_poll_progress_core
        BEQ.S   .ric_prog_ok
        MOVEQ   #RBCP_ERR_PROGRESS,D0
        BRA.S   .ric_fail

.ric_prog_ok:
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0   ; rbcp_check_response
        CMPI.B  #RBCP_STATUS_OK,D0
        BNE.S   .ric_resp_fail
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2/A0/A5
        RTS
.ric_resp_fail:
        MOVEQ   #RBCP_ERR_RESPONSE,D0
.ric_fail:
        MOVE.B  D0,RBCP_ERROR_CODE
        MOVEM.L (SP)+,D1-D2/A0/A5
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
; A device in command-response mode filters command bytes by page, so a reset
; sent anywhere else is ignored.  That is the state the reset is there to
; recover from.
; Clobbers (saved/restored): D1/A5
; ---------------------------------------------------------------------------
rbcp_cmd_reset_noknock:
        MOVEM.L D1/A5,-(SP)
        MOVEA.L #CONFIG_RBCP_CMD_PAGE_ABS,A5
        RBCP_SEND_BYTE #RBCP_GRP_RESET
        RBCP_SEND_BYTE #RBCP_CMD_RESET
        MOVEM.L (SP)+,D1/A5
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
; Clobbers: nothing
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
        BRA     rbcp_cmd_reset_noknock  ; tail call

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
; Clobbers: D0
; ---------------------------------------------------------------------------
rbcp_cmd_enter_cmd_resp:
        CLR.B   RBCP_ERROR_CODE

        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_ENTER_CMD_RESP,RBCP_CMD

        ; ARG0/ARG1: command page (16-bit LE)
        MOVE.B  #(RBCP_CMD_PAGE_REL&$FF),RBCP_ARG0
        MOVE.B  #((RBCP_CMD_PAGE_REL>>8)&$FF),RBCP_ARG1

        ; ARG2/ARG3/ARG4: back-channel start, device byte offset in slot (24-bit LE)
        MOVE.B  #(RBCP_BCH_START&$FF),RBCP_ARG2
        MOVE.B  #((RBCP_BCH_START>>8)&$FF),RBCP_ARG3
        MOVE.B  #((RBCP_BCH_START>>16)&$FF),RBCP_ARG4

        ; ARG5/ARG6: back-channel size in device bytes (16-bit LE)
        MOVE.B  #(CONFIG_RBCP_BCH_SIZE&$FF),RBCP_ARG5
        MOVE.B  #((CONFIG_RBCP_BCH_SIZE>>8)&$FF),RBCP_ARG6

        ; ARG7/ARG8: complete and status-OK sentinel values
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
; rbcp_cmd_nop — NOP in command-response mode.  A device that answers it is
; alive.
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
; Clobbers: D0
; ---------------------------------------------------------------------------
rbcp_cmd_nop:
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_NOP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_exit_cmd_resp_ack — leave command-response mode, acknowledged
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
; Clobbers: D0
; ---------------------------------------------------------------------------
rbcp_cmd_exit_cmd_resp_ack:
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_EXIT_CMD_RESP_ACK,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; ===========================================================================
; Reading the response data section
;
; On a word-organised ROM the data section's bytes are transposed in CPU
; address space, and a linear index into it is not a linear CPU offset.  These
; two routines undo that: rbcp_region_addr maps one region byte to its CPU
; address, and rbcp_read_data copies a run of the data section into a linear
; chip RAM buffer so the application reads records and strings with a plain
; incrementing pointer, exactly as an 8-bit host reads them in place.
; ===========================================================================

; ---------------------------------------------------------------------------
; rbcp_region_addr — CPU address of one back-channel region byte
; Input : D0.W = region byte index N
; Output: A0   = CPU address of that byte
; Clobbers (saved/restored): D1-D2
; ---------------------------------------------------------------------------
rbcp_region_addr:
        MOVEM.L D1-D2,-(SP)
        MOVE.W  D0,D1
    ifne CONFIG_RBCP_DEV_SHIFT
        LSR.W   #CONFIG_RBCP_DEV_SHIFT,D1   ; which bus cycle
    endc
    ifne CONFIG_RBCP_BUS_SHIFT
        LSL.W   #CONFIG_RBCP_BUS_SHIFT,D1   ; CPU bytes per bus cycle
    endc
        MOVE.W  D0,D2
        ANDI.W  #CONFIG_RBCP_DEV_MASK,D2     ; byte within the device word
        EORI.W  #CONFIG_RBCP_ENDIAN_XOR,D2   ; big-endian 68K transposes it
        ADD.W   D2,D1
    ifne CONFIG_RBCP_LANE_OFF
        ADDI.W  #CONFIG_RBCP_LANE_OFF,D1     ; this device's lane on the bus
    endc
        MOVEA.L #CONFIG_RBCP_BCH_ABS,A0
        ADDA.W  D1,A0
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; rbcp_read_data — un-swap a window of the data section into
;                  CONFIG_RBCP_DATA_BUF
; Input : D0.W = number of data bytes to copy (1..CONFIG_RBCP_DATA_BUF_SIZE)
;         D1.W = data byte offset to start at
; Output: CONFIG_RBCP_DATA_BUF holds those bytes in linear order
; Clobbers (saved/restored): D0-D4/A0-A1
;
; Call it after a command succeeds and before the next command is issued, as
; the next command overwrites the region.  Data byte i is region byte 8+i.
;
; The offset lets a caller read a reply longer than the buffer a window at a
; time.  The device holds the whole reply until the next command.
; ---------------------------------------------------------------------------
rbcp_read_data:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVEA.L #CONFIG_RBCP_DATA_BUF,A1
        MOVE.W  D0,D4
        SUBQ.W  #1,D4               ; DBF counter
        MOVE.W  D1,D3
        ADDQ.W  #8,D3
.rrd_loop:
        MOVE.W  D3,D0
        BSR     rbcp_region_addr
        MOVE.B  (A0),(A1)+
        ADDQ.W  #1,D3
        DBF     D4,.rrd_loop
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ===========================================================================
; Read-group command helpers (group 0x01)
; Each returns D0=0/Z=1 on success and clobbers nothing else, leaving the
; answer in the back-channel data section for rbcp_read_data.
; ===========================================================================

rbcp_cmd_get_proto_version:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_PROTO_VERSION,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

rbcp_cmd_get_ram_info_all:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_RAM_INFO_ALL,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

rbcp_cmd_get_flash_count:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_FLASH_COUNT,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_get_flash_info — D0.B = flash slot
rbcp_cmd_get_flash_info:
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_FLASH_INFO,RBCP_CMD
        MOVEQ   #1,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_get_flash_info_all — every flash slot in one reply
; Input : none
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: the preamble at RBCP_FLASH_ALL_TOTAL,
;         RBCP_FLASH_ALL_WHOLE and RBCP_FLASH_ALL_PARTIAL, then records of
;         RBCP_FLASH_RECORD_SIZE from RBCP_FLASH_ALL_RECORDS, in slot order.
; Clobbers: D0
;
; The reply runs to a record per slot, so a caller whose buffer is smaller than
; all of it reads one record at a time, giving rbcp_read_data the offset of the
; record it wants.
; ---------------------------------------------------------------------------
rbcp_cmd_get_flash_info_all:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_FLASH_INFO_ALL,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

rbcp_cmd_get_device_type:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_DEVICE_TYPE,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

rbcp_cmd_get_device_version:
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_DEVICE_VERSION,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_slot_peek — read bytes out of a RAM slot into the data section
; Input : RBCP_ARG0 = count, 0 meaning 256
;         RBCP_ARG1/2/3 = 24-bit slot offset, little-endian
;         RBCP_ARG4 = RAM slot
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: the bytes read, from offset 0.
; Clobbers: D0
;
; The slot read need not be the active one, and an inactive slot is not
; visible to the host any other way — the back-channel only ever shows the
; active slot.  The device fails the command where the data section cannot
; hold the count asked for.
;
; The final argument byte is the RAM slot, and $AA there is the reset marker,
; so this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_slot_peek:
        CMPI.B  #$AA,RBCP_ARG4
        BEQ.S   .rsp_refuse
        MOVE.B  #RBCP_GRP_READ,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SLOT_PEEK,RBCP_CMD
        MOVEQ   #5,D0
        BRA     rbcp_issue_cmd
.rsp_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_check_protocol_version — check the device's protocol version against
; this library's.  Major must match exactly.  With major 0 the minor must
; match and the patch be at least ours.  Above major 0 a greater minor is
; enough, and an equal one needs the patch at least ours.
; Output: D0=0/Z=1 compatible, D0=1/Z=0 not
; Clobbers (saved/restored): D1-D2/A0-A1
; ---------------------------------------------------------------------------
rbcp_check_protocol_version:
        MOVEM.L D1-D2/A0-A1,-(SP)
        BSR     rbcp_cmd_get_proto_version
        TST.B   D0
        BNE.S   .rcpv_fail
        MOVEQ   #4,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data          ; major, minor, patch, reserved
        MOVEA.L #CONFIG_RBCP_DATA_BUF,A0
        MOVE.B  (A0),D1                 ; device major
        CMPI.B  #RBCP_SUPPORTED_MAJOR,D1
        BNE.S   .rcpv_fail
    ifeq RBCP_SUPPORTED_MAJOR
        MOVE.B  1(A0),D1                ; major 0: minor must match
        CMPI.B  #RBCP_SUPPORTED_MINOR,D1
        BNE.S   .rcpv_fail
        MOVE.B  2(A0),D1                ; patch at least ours
        CMPI.B  #RBCP_SUPPORTED_PATCH,D1
        BCS.S   .rcpv_fail
    else
        MOVE.B  1(A0),D1                ; device minor at least ours
        CMPI.B  #RBCP_SUPPORTED_MINOR,D1
        BCS.S   .rcpv_fail
        BNE.S   .rcpv_ok                ; device minor greater, patch irrelevant
        MOVE.B  2(A0),D1
        CMPI.B  #RBCP_SUPPORTED_PATCH,D1
        BCS.S   .rcpv_fail
    endc
.rcpv_ok:
        MOVEQ   #0,D0
        MOVEM.L (SP)+,D1-D2/A0-A1
        RTS
.rcpv_fail:
        MOVEQ   #1,D0
        MOVEM.L (SP)+,D1-D2/A0-A1
        RTS

; ===========================================================================
; Modify-group helpers (group 0x02) and terminal control commands
; ===========================================================================

; rbcp_cmd_load_slot — D0.B = RAM slot, D1.B = flash slot
rbcp_cmd_load_slot:
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  D1,RBCP_ARG1
        MOVE.B  #RBCP_GRP_MODIFY,RBCP_GROUP
        MOVE.B  #RBCP_CMD_LOAD_SLOT,RBCP_CMD
        MOVEQ   #2,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_switch_and_exit — D0.B = RAM slot.  Terminal, send only, then pause.
rbcp_cmd_switch_and_exit:
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SWITCH_AND_EXIT,RBCP_CMD
        MOVEQ   #1,D0
        BSR     rbcp_send_cmd
        BRA     rbcp_pause

; rbcp_cmd_load_and_exit — D0.B = RAM slot, D1.B = flash slot.  Loads the
; flash image into the RAM slot and exits.  Where the RAM slot is the active
; one this replaces the whole served image, which is how a single-slot device
; boots a chosen image.  Terminal, send only, then pause.
rbcp_cmd_load_and_exit:
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  D1,RBCP_ARG1
        MOVE.B  #RBCP_GRP_CTRL,RBCP_GROUP
        MOVE.B  #RBCP_CMD_LOAD_AND_EXIT,RBCP_CMD
        MOVEQ   #2,D0
        BSR     rbcp_send_cmd
        BRA     rbcp_pause

; ===========================================================================
; NV-group helpers (group 0x03)
; ===========================================================================

rbcp_cmd_get_nv_cap:
        MOVE.B  #RBCP_GRP_NV,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_NV_CAP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_nv_peek — caller sets RBCP_ARG0=count, ARG1=locLSB, ARG2=locMSB
rbcp_cmd_nv_peek:
        MOVE.B  #RBCP_GRP_NV,RBCP_GROUP
        MOVE.B  #RBCP_CMD_NV_PEEK,RBCP_CMD
        MOVEQ   #3,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_nv_poke_commit_byte — caller sets ARG0=byte, ARG1=locLSB,
; ARG2=locMSB, ARG3=RAM slot.  A flash erase can take milliseconds, so it
; waits on the long poll.
rbcp_cmd_nv_poke_commit_byte:
        MOVE.B  #RBCP_GRP_NV,RBCP_GROUP
        MOVE.B  #RBCP_CMD_NV_POKE_COMMIT_BYTE,RBCP_CMD
        MOVEQ   #4,D0
        BRA     rbcp_issue_cmd_long_poll

; ===========================================================================
; Pipe-group helpers (group 0x04)
; ===========================================================================

rbcp_cmd_get_pipe_cap:
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_PIPE_CAP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_pipe_write — caller sets RBCP_ARG0..3 = payload.
; Input: D0.B = count (1..4), D1.B = pipe.  All or nothing.
rbcp_cmd_pipe_write:
        MOVE.B  D1,RBCP_ARG4        ; pipe
        MOVE.B  D0,RBCP_ARG5        ; count (final argument, so never $AA)
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_PIPE_WRITE,RBCP_CMD
        MOVEQ   #6,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_get_pipe_info — a pipe's type, flags and current room
; Input : D0.B = pipe
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: type, flags, free, waiting and far end — see the
;         RBCP_PIPE_INFO_* offsets.
; Clobbers: D0
;
; free and waiting both saturate at $FF, so each carries a real count only
; near its limit.
;
; The final argument byte is the pipe number, and $AA there is the reset
; marker, so this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_get_pipe_info:
        CMPI.B  #$AA,D0
        BEQ.S   .rgpi_refuse
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_PIPE_INFO,RBCP_CMD
        MOVEQ   #1,D0
        BRA     rbcp_issue_cmd
.rgpi_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_pipe_read — take bytes off a pipe, consuming what comes back
; Input : D0.B = count, 0 meaning 256
;         D1.B = pipe
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: count, flags and waiting at the RBCP_PIPE_READ_*
;         offsets, and the bytes from RBCP_PIPE_READ_DATA.
; Clobbers: D0
;
; How many came back is spread across the first two fields.  With
; RBCP_PIPE_READ_FLAG_FULL set the count asked for is the count that came,
; zero meaning 256 as it did in the command.  With it clear fewer arrived and
; RBCP_PIPE_READ_COUNT is how many.  A zero there is an empty pipe, which
; succeeds carrying no data.
;
; The device fails the command and reads nothing where the data section cannot
; hold 8 bytes plus the count asked for.
;
; The final argument byte is the pipe number, and $AA there is the reset
; marker, so this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_pipe_read:
        CMPI.B  #$AA,D1
        BEQ.S   .rpr_refuse
        MOVE.B  D0,RBCP_ARG0        ; count
        MOVE.B  D1,RBCP_ARG1        ; pipe
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_PIPE_READ,RBCP_CMD
        MOVEQ   #2,D0
        BRA     rbcp_issue_cmd
.rpr_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ===========================================================================
; Auxiliary I/O helpers (group 0x05)
;
; Pins the host can drive and read.  The device does not know what is wired to
; a pin, so nothing here names a purpose.  A pin is a group and a number, and
; the effect of moving it is the caller's business.
;
; Group indices are not stable across boards, so a caller reads the group
; count from GET_AUX_CAPABILITY and matches groups on the type byte
; GET_AUX_GROUP_INFO returns.  A pin's state outlives the session.  Leaving
; command-response mode does not put a driven pin back, and neither does
; RBCP_RESET.  Only a device reset does.
; ===========================================================================

; ---------------------------------------------------------------------------
; rbcp_cmd_get_aux_cap — the device's pin group count and its hold limit
; Input : none
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: RBCP_AUX_CAP_GROUPS is the group count, zero on a
;         device with no auxiliary pins, and RBCP_AUX_CAP_MAX_HOLD the largest
;         hold it accepts.
; Clobbers: D0
;
; This is also the version check.  The command takes no argument bytes, so a
; device implementing a protocol version without this group consumes nothing,
; fails it and stays in step.  Failure therefore means "no auxiliary pins
; here" whether the device is old or has none.
; ---------------------------------------------------------------------------
rbcp_cmd_get_aux_cap:
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_AUX_CAP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; ---------------------------------------------------------------------------
; rbcp_cmd_get_aux_group_info — one group's type and pin count
; Input : D0.B = group
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: RBCP_AUX_GROUP_TYPE and RBCP_AUX_GROUP_PINS.  A pin
;         count of zero means 256, and a group is never empty.
; Clobbers: D0
;
; The final argument byte is the group, and $AA there is the reset marker, so
; this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_get_aux_group_info:
        CMPI.B  #$AA,D0
        BEQ.S   .ragi_refuse
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_AUX_GROUP_INFO,RBCP_CMD
        MOVEQ   #1,D0
        BRA     rbcp_issue_cmd
.ragi_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_get_aux_pin_info — one pin's flags and current level
; Input : D0.B = pin
;         D1.B = group
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: flags, level and driven — see the RBCP_AUX_PIN_*
;         offsets.  Level and driven mean nothing unless
;         RBCP_AUX_FLAG_READABLE is set in flags.
; Clobbers: D0
;
; A host showing a whole group calls this once per pin every refresh.  It is
; the only command here issued in bulk.
;
; The final argument byte is the group, and $AA there is the reset marker, so
; this refuses it and sends nothing.  A pin number of $AA is valid.
; ---------------------------------------------------------------------------
rbcp_cmd_get_aux_pin_info:
        CMPI.B  #$AA,D1
        BEQ.S   .rapi_refuse
        MOVE.B  D0,RBCP_ARG0        ; pin
        MOVE.B  D1,RBCP_ARG1        ; group
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_AUX_PIN_INFO,RBCP_CMD
        MOVEQ   #2,D0
        BRA     rbcp_issue_cmd
.rapi_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_set_aux — drive a pin
; Input : RBCP_ARG0 = state, RBCP_ARG1 = after, RBCP_ARG2 = hold,
;         RBCP_ARG3 = pin, RBCP_ARG4 = group
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
; Clobbers: D0
;
; Hold is in units of 10ms, zero to hold the state until something else
; changes it.  Where it is non-zero the device holds the state, applies after,
; and only then completes the command, so this waits on
; CONFIG_RBCP_AUX_POLL_TIMEOUT rather than the ordinary poll.
;
; The final argument byte is the group, and $AA there is the reset marker, so
; this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_set_aux:
        CMPI.B  #$AA,RBCP_ARG4
        BEQ.S   .rsa_refuse
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SET_AUX,RBCP_CMD
        MOVEQ   #5,D0
        BRA     rbcp_issue_cmd_aux_poll
.rsa_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_set_aux_and_exit — as rbcp_cmd_set_aux, then leave command mode
; Input : arguments as rbcp_cmd_set_aux
; Output: none.  Terminal, send only, then pause.
; Clobbers: D0
;
; The device writes no response header, so there is nothing to poll and the
; caller must not try.  It returns as soon as the bytes are out, which is
; before the device has finished holding.  The caller owns the wait and must
; not knock again until the hold has elapsed.
;
; A group of $AA is not refused here.  The device sets no pin.  The exit the
; caller asked for still completes.
; ---------------------------------------------------------------------------
rbcp_cmd_set_aux_and_exit:
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SET_AUX_AND_EXIT,RBCP_CMD
        MOVEQ   #5,D0
        BSR     rbcp_send_cmd
        BRA     rbcp_pause

; ---------------------------------------------------------------------------
; rbcp_cmd_set_aux_switch_exit — drive a pin, activate a RAM slot, then leave
; Input : RBCP_ARG0 = state, RBCP_ARG1 = after, RBCP_ARG2 = hold,
;         RBCP_ARG3 = flags, RBCP_ARG4 = pin, RBCP_ARG5 = group,
;         RBCP_ARG6 = RAM slot
; Output: none.  Terminal, send only, then pause.
; Clobbers: D0
;
; Flags picks the order — RBCP_AUX_PIN_FIRST or RBCP_AUX_SLOT_FIRST.  A
; caller wants pin first where the pin stops the host, so the machine is held
; while the image underneath it changes.  Under that ordering the device
; does not apply after until the switch is done, so the hold lasts at least as
; long as the switch takes, however small a hold was asked for.
;
; Anything that must follow a slot switch belongs in the same command as the
; switch.  After a switch the new image may have no back-channel region, and
; the observed addresses may have moved.
;
; A slot of $AA is not refused here, for the reason given under
; rbcp_cmd_set_aux_and_exit.
; ---------------------------------------------------------------------------
rbcp_cmd_set_aux_switch_exit:
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SET_AUX_SWITCH_EXIT,RBCP_CMD
        MOVEQ   #7,D0
        BSR     rbcp_send_cmd
        BRA     rbcp_pause

; ===========================================================================
; LED-group helpers (group 0x06)
; ===========================================================================

rbcp_cmd_get_led_cap:
        MOVE.B  #RBCP_GRP_LEDS,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_LED_CAP,RBCP_CMD
        MOVEQ   #0,D0
        BRA     rbcp_issue_cmd

; rbcp_cmd_get_led_info — D0.B = LED.
; The final argument byte is the LED number, and $AA there is the reset
; marker, so this refuses it and sends nothing.
rbcp_cmd_get_led_info:
        CMPI.B  #$AA,D0
        BEQ.S   .rgli_refuse
        MOVE.B  D0,RBCP_ARG0
        MOVE.B  #RBCP_GRP_LEDS,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_LED_INFO,RBCP_CMD
        MOVEQ   #1,D0
        BRA     rbcp_issue_cmd
.rgli_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; ---------------------------------------------------------------------------
; rbcp_cmd_get_led_mode_info — one mode's period requirement on one LED
; Input : D0.B = LED
;         D1.B = mode
; Output: D0=0/Z=1 success, D0=error stage/Z=0 failure
;         Data section: RBCP_LED_MODE_FLAGS says whether the mode takes a
;         period on this LED, RBCP_LED_MODE_MIN_PERIOD the shortest it
;         accepts.
; Clobbers: D0
;
; A caller naming no period of its own gets the mode's default and never needs
; this command.
;
; The final argument byte is the LED number, and $AA there is the reset
; marker, so this refuses it and sends nothing.
; ---------------------------------------------------------------------------
rbcp_cmd_get_led_mode_info:
        CMPI.B  #$AA,D0
        BEQ.S   .rglmi_refuse
        MOVE.B  D0,RBCP_ARG1        ; LED
        MOVE.B  D1,RBCP_ARG0        ; mode
        MOVE.B  #RBCP_GRP_LEDS,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_LED_MODE_INFO,RBCP_CMD
        MOVEQ   #2,D0
        BRA     rbcp_issue_cmd
.rglmi_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS

; rbcp_cmd_set_led — caller sets RBCP_ARG0=mode, ARG1=red, ARG2=green,
; ARG3=blue, ARG4=brightness, ARG5=period, ARG6=hold.  Input: D0.B = LED.
; The final argument byte is the LED number, and $AA there is the reset
; marker, so this refuses it and sends nothing.
rbcp_cmd_set_led:
        CMPI.B  #$AA,D0
        BEQ.S   .rsl_refuse
        MOVE.B  D0,RBCP_ARG7
        MOVE.B  #RBCP_GRP_LEDS,RBCP_GROUP
        MOVE.B  #RBCP_CMD_SET_LED,RBCP_CMD
        MOVEQ   #8,D0
        BRA     rbcp_issue_cmd
.rsl_refuse:
        MOVE.B  #RBCP_ERR_RESPONSE,RBCP_ERROR_CODE
        MOVEQ   #1,D0
        RTS
