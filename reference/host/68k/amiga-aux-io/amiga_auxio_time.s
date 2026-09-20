; amiga_auxio_time.s — how long the device takes over one command
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  Four commands, each sent TIME_RUNS times, each run timed on
; its own from the last command byte leaving the host to the device saying
; complete.  Working the arguments out, sending the bytes and reading the
; reply back all sit outside that window, and the whole frame is reported
; beside it off the same counter, timed over the whole batch.
;
; The clock is the CIA-B time of day counter, which ticks once a scan line.
; One run therefore places the window to 64us, which is coarse against a
; command, but the runs are summed as ticks and divided once at the end.  A
; command frame is not a whole number of scan lines, so where a run starts
; walks against the tick and what is lost on one run is gained on another: the
; mean is good to about a microsecond over 256 runs.  MIN and MAX are one run
; each and so read in whole ticks.
;
; The beam places itself more finely, but MAME's A500 counts VHPOSR's low byte
; at twice the rate an Amiga does, so a beam figure would mean two different
; things on the two machines.
;
; What a reading costs: tod_now is three CIA reads and the first of them
; latches, so the reading is that first read and the two after it fall inside
; the window without moving it.  They hold the poll off by about four
; microseconds, which is time the device is working anyway.
;
; What the window cannot see: the host does not look at the progress byte at
; all until about 50us after the last command byte, and after that it looks
; once a poll turn, 46 cycles of the 68000 or about 6.5us.  So a
; device answering inside that first 50us reads as 50us whatever it really
; took, and above it a run reads up to one poll turn long.  Both floors are
; the same in all four commands, so a difference between two of them is clean.

; ---------------------------------------------------------------------------
; us_from — D0.L = a count, D1.W = the multiplier for the clock it came off.
; Output: D0.W = microseconds, $FFFF where the count is past what a word holds
; Clobbers: D0
; ---------------------------------------------------------------------------
us_from:
        MOVEM.L D1-D2,-(SP)
        CMPI.L  #$0000FFFF,D0
        BHI.S   .uf_over
        MULU    D1,D0
        MOVEQ   #US_SHIFT,D2
        LSR.L   D2,D0
        BRA.S   .uf_out
.uf_over:
        MOVE.W  #$FFFF,D0
.uf_out:
        MOVEM.L (SP)+,D1-D2
        RTS

; ---------------------------------------------------------------------------
; big_char — D0.B = character, D1.B = column, D2.B = row.  The ordinary font
; at three times the size, so a figure reads from across a room.
;
; Every pixel becomes three across and three down, which puts a character in
; three whole bytes and needs no shifting.  VAR_PEN and VAR_PEN_BG mean what
; they mean to screen_putchar.
; Clobbers (saved/restored): D0-D7/A0-A2
; ---------------------------------------------------------------------------
big_char:
        MOVEM.L D0-D7/A0-A2,-(SP)

        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MULU    #BIG_ROW_STRIDE,D3
        MOVEQ   #0,D6
        MOVE.B  D1,D6
        MULU    #BIG_W_BYTES,D6
        ADD.L   D6,D3
        MOVEA.L VAR_DRAW_BASE,A1
        ADDA.L  D3,A1

        MOVEQ   #0,D3
        MOVE.B  D0,D3
        ASL.W   #3,D3
        LEA     (font_data).L,A0
        ADDA.W  D3,A0

        MOVEQ   #0,D4
        MOVE.B  VAR_PEN,D4
        MOVEQ   #0,D5
        MOVE.B  VAR_PEN_BG,D5

        MOVEA.L A1,A2                   ; walks the planes and the pixel rows
        MOVEQ   #7,D7                   ; the eight rows of the glyph
.bc_row:
        MOVE.B  (A0)+,D0
        MOVEQ   #0,D3
        MOVEQ   #7,D1                   ; the bit, highest first
.bc_expand:
        LSL.L   #3,D3
        BTST    D1,D0
        BEQ.S   .bc_next_bit
        ADDQ.L  #7,D3
.bc_next_bit:
        DBF     D1,.bc_expand
        MOVE.L  D3,D6
        SWAP    D6
        MOVE.B  D6,(AUX_BIG_ROW).W
        MOVE.L  D3,D6
        LSR.L   #8,D6
        MOVE.B  D6,(AUX_BIG_ROW+1).W
        MOVE.B  D3,(AUX_BIG_ROW+2).W

        MOVEQ   #0,D2                   ; the plane
.bc_plane:
        MOVEQ   #0,D0                   ; what the rest of the cell is
        BTST    D2,D5
        BEQ.S   .bc_fore
        MOVEQ   #-1,D0
.bc_fore:
        MOVEQ   #0,D1
        BTST    D2,D4
        BEQ.S   .bc_select
        MOVEQ   #-1,D1
.bc_select:
        EOR.B   D0,D1                   ; the bits the glyph switches

        MOVE.B  (AUX_BIG_ROW).W,D3
        AND.B   D1,D3
        EOR.B   D0,D3
        MOVE.B  D3,(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES*2(A2)
        MOVE.B  (AUX_BIG_ROW+1).W,D3
        AND.B   D1,D3
        EOR.B   D0,D3
        MOVE.B  D3,1(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES+1(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES*2+1(A2)
        MOVE.B  (AUX_BIG_ROW+2).W,D3
        AND.B   D1,D3
        EOR.B   D0,D3
        MOVE.B  D3,2(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES+2(A2)
        MOVE.B  D3,SCREEN_ROW_BYTES*2+2(A2)

        ADDA.W  #SCREEN_BPL_W,A2
        ADDQ.B  #1,D2
        CMPI.B  #SCREEN_PLANES,D2
        BCS.S   .bc_plane
        ; four planes took A2 down one pixel row, and three were written
        ADDA.W  #SCREEN_ROW_BYTES*2,A2
        DBF     D7,.bc_row

        MOVEM.L (SP)+,D0-D7/A0-A2
        RTS

; ---------------------------------------------------------------------------
; big_print — A0 = string, D1.B = column, D2.B = row, in big characters.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
big_print:
        MOVEM.L D0-D2/A0,-(SP)
.bp_loop:
        MOVE.B  (A0)+,D0
        BEQ.S   .bp_done
        CMPI.B  #BIG_COLS,D1
        BCC.S   .bp_done
        BSR     big_char
        ADDQ.B  #1,D1
        BRA.S   .bp_loop
.bp_done:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; fmt_fig — D0.W = a figure, D1.B = what it is.  AUX_T_TEXT comes back holding
; T_FIG_W characters and a terminator, with the figure at the right of them.
;
; A figure that is not a number says why in the same width, so a column of
; them stays a column.
; Clobbers: nothing
; ---------------------------------------------------------------------------
fmt_fig:
        MOVEM.L D0-D3/A0-A1,-(SP)
        ANDI.L  #$0000FFFF,D0
        LEA     (AUX_T_TEXT).W,A0
        MOVEQ   #T_FIG_W-1,D3
.ff_pad:
        MOVE.B  #' ',(A0,D3.W)
        DBF     D3,.ff_pad
        CLR.B   T_FIG_W(A0)
        CMPI.B  #T_OK,D1
        BNE.S   .ff_word
        CMPI.W  #$FFFF,D0
        BEQ.S   .ff_over
        MOVEQ   #T_FIG_W-1,D3
.ff_digit:
        DIVU    #10,D0
        MOVE.L  D0,D2
        SWAP    D2                      ; the remainder
        ADDI.B  #'0',D2
        MOVE.B  D2,(A0,D3.W)
        SUBQ.W  #1,D3
        ANDI.L  #$0000FFFF,D0
        BNE.S   .ff_digit
        BRA.S   .ff_out
.ff_over:
        LEA     (str_t_over).L,A1
        BRA.S   .ff_copy
.ff_word:
        LEA     (str_t_none).L,A1
        CMPI.B  #T_LOST,D1
        BNE.S   .ff_absent
        LEA     (str_t_lost).L,A1
        BRA.S   .ff_copy
.ff_absent:
        CMPI.B  #T_ABSENT,D1
        BNE.S   .ff_copy
        LEA     (str_t_absent).L,A1
.ff_copy:
        MOVEQ   #T_FIG_W-1,D3
.ff_char:
        MOVE.B  (A1)+,(A0)+
        DBF     D3,.ff_char
.ff_out:
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS

; ---------------------------------------------------------------------------
; time_fig — A1 = one of the figure arrays, D0.B = which command.  AUX_T_TEXT
; comes back holding that command's figure from it.
; Clobbers: nothing
; ---------------------------------------------------------------------------
time_fig:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #0,D2
        MOVE.B  D0,D2
        LEA     (AUX_T_STATE).W,A0
        MOVE.B  (A0,D2.W),D1
        ADD.W   D2,D2
        MOVE.W  (A1,D2.W),D0
        BSR     fmt_fig
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; time_name — D0.B = which command.  A0 comes back at its name, eight
; characters and a terminator.
; Clobbers: D0/A0
; ---------------------------------------------------------------------------
time_name:
        ANDI.L  #$000000FF,D0
        MULU    #T_LABEL_W+1,D0
        LEA     (t_labels).L,A0
        ADDA.W  D0,A0
        RTS

; ---------------------------------------------------------------------------
; log_fig — AUX_T_TEXT down the pipe with the padding in front of it dropped.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_fig:
        MOVEM.L A0,-(SP)
        LEA     (AUX_T_TEXT).W,A0
.lf_skip:
        CMPI.B  #' ',(A0)
        BNE.S   .lf_send
        ADDQ.L  #1,A0
        BRA.S   .lf_skip
.lf_send:
        BSR     pipe_puts
        MOVEM.L (SP)+,A0
        RTS

; ---------------------------------------------------------------------------
; log_num — D0.W = a number, down the pipe as digits.
; Clobbers: D0
; ---------------------------------------------------------------------------
log_num:
        MOVEM.L D1,-(SP)
        MOVEQ   #T_OK,D1
        BSR     fmt_fig
        BSR     log_fig
        MOVEM.L (SP)+,D1
        RTS

; ---------------------------------------------------------------------------
; time_pipes — which pipe carries host to device and which carries the other
; way, or T_NO_PIPE where the device has none of that direction.
; Clobbers (saved/restored): D0-D3
; ---------------------------------------------------------------------------
time_pipes:
        MOVEM.L D0-D3,-(SP)
        MOVE.B  #T_NO_PIPE,AUX_T_PIPE_OUT
        MOVE.B  #T_NO_PIPE,AUX_T_PIPE_IN
        BSR     rbcp_cmd_get_pipe_cap
        TST.B   D0
        BNE.S   .tp_out
        MOVEQ   #1,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVEQ   #0,D2
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_CAP_COUNT).W,D2
        BEQ.S   .tp_out
        MOVEQ   #0,D3
.tp_try:
        MOVE.B  D3,D0
        BSR     rbcp_cmd_get_pipe_info
        TST.B   D0
        BNE.S   .tp_next
        MOVEQ   #2,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        MOVE.B  (CONFIG_RBCP_DATA_BUF+RBCP_PIPE_INFO_FLAGS).W,D1
        MOVE.B  D1,D0
        ANDI.B  #RBCP_PIPE_FLAG_OUT,D0
        BEQ.S   .tp_in
        CMPI.B  #T_NO_PIPE,AUX_T_PIPE_OUT
        BNE.S   .tp_in
        MOVE.B  D3,AUX_T_PIPE_OUT
.tp_in:
        ANDI.B  #RBCP_PIPE_FLAG_IN,D1
        BEQ.S   .tp_next
        CMPI.B  #T_NO_PIPE,AUX_T_PIPE_IN
        BNE.S   .tp_next
        MOVE.B  D3,AUX_T_PIPE_IN
.tp_next:
        ADDQ.B  #1,D3
        CMP.B   D2,D3
        BCS.S   .tp_try
.tp_out:
        MOVEM.L (SP)+,D0-D3
        RTS

; ---------------------------------------------------------------------------
; time_args — D0.B = which command.  Its group, its command byte and its
; arguments into the library's scratch.
; Output: D0.B = argument count, or T_NO_PIPE where there is no pipe to ask
; Clobbers: D0
; ---------------------------------------------------------------------------
time_args:
        MOVEM.L D1/A0,-(SP)
        CMPI.B  #T_CMD_GRP,D0
        BEQ.S   .ta_group
        CMPI.B  #T_CMD_WR,D0
        BEQ.S   .ta_write
        CMPI.B  #T_CMD_RD,D0
        BEQ.S   .ta_read
        MOVE.B  AUX_T_PIN,RBCP_ARG0
        MOVE.B  AUX_T_GROUP,RBCP_ARG1
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_AUX_PIN_INFO,RBCP_CMD
        MOVEQ   #2,D0
        BRA.S   .ta_out
.ta_group:
        MOVE.B  AUX_T_GROUP,RBCP_ARG0
        MOVE.B  #RBCP_GRP_AUX,RBCP_GROUP
        MOVE.B  #RBCP_CMD_GET_AUX_GROUP_INFO,RBCP_CMD
        MOVEQ   #1,D0
        BRA.S   .ta_out
.ta_write:
        MOVE.B  AUX_T_PIPE_OUT,D1
        CMPI.B  #T_NO_PIPE,D1
        BEQ.S   .ta_none
        LEA     (str_t_payload).L,A0
        MOVE.B  (A0)+,RBCP_ARG0
        MOVE.B  (A0)+,RBCP_ARG1
        MOVE.B  (A0)+,RBCP_ARG2
        MOVE.B  (A0)+,RBCP_ARG3
        MOVE.B  D1,RBCP_ARG4
        MOVE.B  #RBCP_PIPE_WRITE_MAX,RBCP_ARG5
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_PIPE_WRITE,RBCP_CMD
        MOVEQ   #6,D0
        BRA.S   .ta_out
.ta_read:
        MOVE.B  AUX_T_PIPE_IN,D1
        CMPI.B  #T_NO_PIPE,D1
        BEQ.S   .ta_none
        MOVE.B  #1,RBCP_ARG0            ; one byte asked for
        MOVE.B  D1,RBCP_ARG1
        MOVE.B  #RBCP_GRP_PIPES,RBCP_GROUP
        MOVE.B  #RBCP_CMD_PIPE_READ,RBCP_CMD
        MOVEQ   #2,D0
        BRA.S   .ta_out
.ta_none:
        MOVE.B  #T_NO_PIPE,D0
.ta_out:
        MOVEM.L (SP)+,D1/A0
        RTS

; ---------------------------------------------------------------------------
; time_one — one command, timed from the last byte of it leaving the host to
; the device saying complete.
;
; The library's guarded entry points are not called, because the MOVEM pair
; each one costs would land inside the window.  The unguarded cores are called
; instead.  What they use is saved here once around the whole sequence, D1
; apart, because D1 comes back as the result.
;
; Input : RBCP_GROUP, RBCP_CMD and the arguments set by time_args
;         D0.B = argument count
; Output: D0.L = CIA-B ticks the device took, -1 where it stopped answering
;         D1.B = 0 where the device took the command, 1 where it refused it
; Clobbers: D0-D1
; ---------------------------------------------------------------------------
time_one:
        MOVEM.L D2/D4-D5/A0/A5,-(SP)
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,RBCP_SAVED_TOK
        BSR     rbcp_send_cmd_core
        BSR     tod_now                 ; the last byte is on the bus
        MOVE.L  D0,D4
        BSR     rbcp_poll_token_core
        BNE.S   .to_lost
        MOVE.L  #CONFIG_RBCP_POLL_TIMEOUT,D1
        BSR     rbcp_poll_progress_core
        MOVE.B  D0,D2                   ; whether the poll gave up
        BSR     tod_now                 ; the device says complete
        MOVE.L  D0,D5
        TST.B   D2
        BNE.S   .to_lost
        MOVEQ   #0,D1
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0
        CMPI.B  #RBCP_STATUS_OK,D0
        BEQ.S   .to_span
        MOVEQ   #1,D1
.to_span:
        MOVE.L  D5,D0
        SUB.L   D4,D0
        ANDI.L  #$00FFFFFF,D0           ; the counter is 24 bits and wraps
        BRA.S   .to_out
.to_lost:
        MOVEQ   #-1,D0
        MOVEQ   #1,D1
.to_out:
        MOVEM.L (SP)+,D2/D4-D5/A0/A5
        RTS

; ---------------------------------------------------------------------------
; time_batch — D0.B = which command.  TIME_RUNS runs of it, and what they came
; to written into that command's entry.
;
; One run goes first and is thrown away.  The device claims a pipe the first
; time a host writes or reads it, and that claim would otherwise be in the
; mean.
;
; A device that stops answering ends the batch there rather than waiting out
; TIME_RUNS timeouts.
; Clobbers (saved/restored): D0-D4/A0
; ---------------------------------------------------------------------------
time_batch:
        MOVEM.L D0-D4/A0,-(SP)
        MOVE.B  D0,D4                   ; the command, across the batch
        BSR     time_args
        CMPI.B  #T_NO_PIPE,D0
        BEQ     .tb_absent
        MOVE.B  D0,AUX_T_NARGS
        CLR.L   AUX_T_SUM
        MOVE.L  #$7FFFFFFF,AUX_T_MIN
        CLR.L   AUX_T_MAX
        CLR.W   AUX_T_BAD
        MOVE.B  AUX_T_NARGS,D0
        BSR     time_one                ; thrown away
        TST.L   D0
        BMI.S   .tb_lost
        BSR     tod_now
        MOVE.L  D0,AUX_T_TOD
        MOVE.W  #TIME_RUNS-1,D3
.tb_run:
        MOVE.B  AUX_T_NARGS,D0
        BSR     time_one
        TST.L   D0
        BMI.S   .tb_lost
        TST.B   D1
        BEQ.S   .tb_taken
        ADDQ.W  #1,AUX_T_BAD
.tb_taken:
        ADD.L   D0,AUX_T_SUM
        CMP.L   AUX_T_MIN,D0
        BCC.S   .tb_keep_min
        MOVE.L  D0,AUX_T_MIN
.tb_keep_min:
        CMP.L   AUX_T_MAX,D0
        BLS.S   .tb_keep_max
        MOVE.L  D0,AUX_T_MAX
.tb_keep_max:
        DBF     D3,.tb_run
        BSR     tod_now
        SUB.L   AUX_T_TOD,D0
        ANDI.L  #$00FFFFFF,D0           ; the counter is 24 bits and wraps
        MOVE.L  D0,AUX_T_TOD
        CMPI.B  #T_CMD_WR,D4
        BNE.S   .tb_store
        MOVE.B  #1,VAR_LINE_CUT         ; the payload went down the log's pipe
.tb_store:
        MOVE.B  D4,D0
        BSR     time_store
        BRA.S   .tb_out
.tb_lost:
        MOVEQ   #T_LOST,D0
        BRA.S   .tb_mark
.tb_absent:
        MOVEQ   #T_ABSENT,D0
.tb_mark:
        MOVEQ   #0,D1
        MOVE.B  D4,D1
        LEA     (AUX_T_STATE).W,A0
        MOVE.B  D0,(A0,D1.W)
.tb_out:
        MOVEM.L (SP)+,D0-D4/A0
        RTS

; ---------------------------------------------------------------------------
; time_store — D0.B = which command.  The batch's sums turned into
; microseconds and written to that command's entry.
;
; The multiplier carries the division by TIME_RUNS, so the sum of the runs goes
; through it as it stands and a single run is shifted up by TIME_RUNS_SHIFT
; first.  A run past 255 ticks comes out as OVER, which is 16ms.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
time_store:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #0,D2
        MOVE.B  D0,D2
        ADD.W   D2,D2                   ; a word an entry
        MOVE.W  AUX_T_TOD_MUL,D1
        MOVE.L  AUX_T_SUM,D0
        BSR     us_from
        LEA     (AUX_T_US).W,A0
        MOVE.W  D0,(A0,D2.W)
        MOVE.W  AUX_T_TOD_MUL,D1
        MOVE.L  AUX_T_MIN,D0
        LSL.L   #TIME_RUNS_SHIFT,D0
        BSR     us_from
        LEA     (AUX_T_MINS).W,A0
        MOVE.W  D0,(A0,D2.W)
        MOVE.W  AUX_T_TOD_MUL,D1
        MOVE.L  AUX_T_MAX,D0
        LSL.L   #TIME_RUNS_SHIFT,D0
        BSR     us_from
        LEA     (AUX_T_MAXS).W,A0
        MOVE.W  D0,(A0,D2.W)
        MOVE.W  AUX_T_TOD_MUL,D1
        MOVE.L  AUX_T_TOD,D0
        BSR     us_from
        LEA     (AUX_T_FRAMES).W,A0
        MOVE.W  D0,(A0,D2.W)
        LEA     (AUX_T_BADS).W,A0
        MOVE.W  AUX_T_BAD,(A0,D2.W)
        LSR.W   #1,D2                   ; the state is a byte an entry
        LEA     (AUX_T_STATE).W,A0
        MOVE.B  #T_OK,(A0,D2.W)
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; time_pipe_col — D0.B = a pipe number, D1.B = column, D2.B = row.  A dash
; where the device has no pipe of that direction.
; Clobbers (saved/restored): D0-D1
; ---------------------------------------------------------------------------
time_pipe_col:
        MOVEM.L D0-D1,-(SP)
        CMPI.B  #T_NO_PIPE,D0
        BEQ.S   .tpc_none
        ANDI.L  #$000000FF,D0
        BSR     print_dec_w
        BRA.S   .tpc_out
.tpc_none:
        MOVEQ   #'-',D0
        BSR     screen_putchar
.tpc_out:
        MOVEM.L (SP)+,D0-D1
        RTS

; ---------------------------------------------------------------------------
; time_asked — the pin the two auxiliary commands ask about and the pipes the
; two pipe commands use, so a figure can be put back beside what it was
; measured on.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
time_asked:
        MOVEM.L D0-D2/A0,-(SP)
        MOVEQ   #ROW_T_ASKED,D0
        BSR     clear_row
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  #ROW_T_ASKED,D2

        LEA     (str_t_group).L,A0
        MOVE.B  #COL_T_GROUP,D1
        BSR     screen_print
        LEA     (str_t_pin).L,A0
        MOVE.B  #COL_T_PIN,D1
        BSR     screen_print
        LEA     (str_t_out).L,A0
        MOVE.B  #COL_T_OUT,D1
        BSR     screen_print
        LEA     (str_t_in).L,A0
        MOVE.B  #COL_T_IN,D1
        BSR     screen_print

        MOVE.B  #PEN_TEXT,VAR_PEN
        MOVEQ   #0,D0
        MOVE.B  AUX_T_GROUP,D0
        MOVE.B  #COL_T_GROUPV,D1
        BSR     print_dec_w
        MOVEQ   #0,D0
        MOVE.B  AUX_T_PIN,D0
        MOVE.B  #COL_T_PINV,D1
        BSR     print_dec_w
        MOVE.B  AUX_T_PIPE_OUT,D0
        MOVE.B  #COL_T_OUTV,D1
        BSR     time_pipe_col
        MOVE.B  AUX_T_PIPE_IN,D0
        MOVE.B  #COL_T_INV,D1
        BSR     time_pipe_col
        BSR     plain_pens
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; time_draw_one — D0.B = which command.  Its big figure and the row of detail
; that goes under the four of them.
; Clobbers (saved/restored): D0-D2/D4/A0-A1
; ---------------------------------------------------------------------------
time_draw_one:
        MOVEM.L D0-D2/D4/A0-A1,-(SP)
        MOVEQ   #0,D4
        MOVE.B  D0,D4                   ; the entry, across the row

        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  #PEN_BG,VAR_PEN_BG
        MOVE.B  D4,D0
        BSR     time_name
        MOVEQ   #0,D1
        MOVE.B  D4,D2
        BSR     big_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        LEA     (AUX_T_US).W,A1
        MOVE.B  D4,D0
        BSR     time_fig
        LEA     (AUX_T_TEXT).W,A0
        MOVE.B  #COL_T_FIG,D1
        MOVE.B  D4,D2
        BSR     big_print

        MOVEQ   #ROW_T_DETAIL,D0
        ADD.B   D4,D0
        BSR     clear_row
        MOVE.B  #ROW_T_DETAIL,D2
        ADD.B   D4,D2
        MOVE.B  #PEN_LABEL,VAR_PEN
        MOVE.B  D4,D0
        BSR     time_name
        MOVEQ   #0,D1
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN

        LEA     (AUX_T_MINS).W,A1
        MOVE.B  D4,D0
        BSR     time_fig
        LEA     (AUX_T_TEXT).W,A0
        MOVE.B  #COL_T_MINV,D1
        BSR     screen_print
        LEA     (AUX_T_MAXS).W,A1
        MOVE.B  D4,D0
        BSR     time_fig
        LEA     (AUX_T_TEXT).W,A0
        MOVE.B  #COL_T_MAXV,D1
        BSR     screen_print
        LEA     (AUX_T_FRAMES).W,A1
        MOVE.B  D4,D0
        BSR     time_fig
        LEA     (AUX_T_TEXT).W,A0
        MOVE.B  #COL_T_FRAMEV,D1
        BSR     screen_print
        LEA     (AUX_T_BADS).W,A1
        MOVE.B  D4,D0
        BSR     time_fig
        LEA     (AUX_T_TEXT).W,A0
        MOVE.B  #COL_T_BADV,D1
        BSR     screen_print

        BSR     plain_pens
        MOVEM.L (SP)+,D0-D2/D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; time_frame — the timer screen with nothing timed yet.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
time_frame:
        MOVEM.L D0-D2/A0,-(SP)
        BSR     screen_clear
        BSR     plain_pens
        MOVE.B  #PEN_LABEL,VAR_PEN
        LEA     (str_t_units).L,A0
        MOVE.B  #ROW_T_UNITS,D2
        BSR     screen_print_centred
        LEA     (str_t_back).L,A0
        MOVE.B  #ROW_T_BACK,D2
        BSR     screen_print_centred

        MOVE.B  #ROW_T_HEAD,D2
        LEA     (str_t_min).L,A0
        MOVE.B  #COL_T_MIN,D1
        BSR     screen_print
        LEA     (str_t_max).L,A0
        MOVE.B  #COL_T_MAX,D1
        BSR     screen_print
        LEA     (str_t_frame).L,A0
        MOVE.B  #COL_T_FRAME,D1
        BSR     screen_print
        LEA     (str_t_bad).L,A0
        MOVE.B  #COL_T_BAD,D1
        BSR     screen_print
        BSR     plain_pens

        BSR     time_asked
        MOVEQ   #0,D0
.tf_row:
        BSR     time_draw_one
        ADDQ.B  #1,D0
        CMPI.B  #TIME_CMDS,D0
        BCS.S   .tf_row
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; time_header — what the timer is about to do, down the pipe.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
time_header:
        MOVEM.L D0/A0,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ.S   .th_out
        LEA     (str_log_timer).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  AUX_T_GROUP,D0
        BSR     log_num
        LEA     (str_log_t_pin).L,A0
        BSR     pipe_puts
        MOVEQ   #0,D0
        MOVE.B  AUX_T_PIN,D0
        BSR     log_num
        BSR     log_crlf
.th_out:
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; time_report — D0.B = which command.  One line saying what it came to.
; Clobbers (saved/restored): D0-D2/A0-A1
; ---------------------------------------------------------------------------
time_report:
        MOVEM.L D0-D2/A0-A1,-(SP)
        TST.B   VAR_PIPE_PRESENT
        BEQ     .tr_out
        MOVE.B  D0,D2                   ; the entry, across the line
        LEA     (str_log_time).L,A0
        BSR     pipe_puts
        MOVE.B  D2,D0
        BSR     time_name
        BSR     pipe_puts
        LEA     (msg_sp).L,A0
        BSR     pipe_puts
        LEA     (AUX_T_US).W,A1
        MOVE.B  D2,D0
        BSR     time_fig
        BSR     log_fig
        LEA     (str_log_t_min).L,A0
        BSR     pipe_puts
        LEA     (AUX_T_MINS).W,A1
        MOVE.B  D2,D0
        BSR     time_fig
        BSR     log_fig
        LEA     (str_log_t_max).L,A0
        BSR     pipe_puts
        LEA     (AUX_T_MAXS).W,A1
        MOVE.B  D2,D0
        BSR     time_fig
        BSR     log_fig
        LEA     (str_log_t_frame).L,A0
        BSR     pipe_puts
        LEA     (AUX_T_FRAMES).W,A1
        MOVE.B  D2,D0
        BSR     time_fig
        BSR     log_fig
        LEA     (str_log_t_bad).L,A0
        BSR     pipe_puts
        LEA     (AUX_T_BADS).W,A1
        MOVE.B  D2,D0
        BSR     time_fig
        BSR     log_fig
        BSR     log_crlf
.tr_out:
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

; ---------------------------------------------------------------------------
; time_setup — the clock's multiplier, the pipes the device has, and the pin
; the auxiliary commands will ask about.
;
; The pin is the one under the cursor, so a figure can be read against a pad
; on the page the timer was opened from.  A group with nothing drivable on it
; gets pin zero, which every group has.
; Clobbers (saved/restored): D0-D1/A0
; ---------------------------------------------------------------------------
time_setup:
        MOVEM.L D0-D1/A0,-(SP)
        MOVE.W  #TOD_US_NTSC,AUX_T_TOD_MUL
        TST.B   VAR_IS_PAL
        BEQ.S   .tsu_pipes
        MOVE.W  #TOD_US_PAL,AUX_T_TOD_MUL
.tsu_pipes:
        BSR     time_pipes
        MOVE.B  AUX_CUR_GROUP,AUX_T_GROUP
        CLR.B   AUX_T_PIN
        MOVE.B  AUX_CUR_GROUP,D0
        BSR     group_drv
        BEQ.S   .tsu_clear
        MOVE.B  AUX_CUR_SLOT,D0
        MOVE.B  AUX_CUR_GROUP,D1
        BSR     pins_drv_at
        MOVE.B  D0,AUX_T_PIN
.tsu_clear:
        LEA     (AUX_T_STATE).W,A0
        MOVEQ   #TIME_CMDS-1,D0
.tsu_state:
        CLR.B   (A0,D0.W)
        DBF     D0,.tsu_state
        MOVEM.L (SP)+,D0-D1/A0
        RTS

; ---------------------------------------------------------------------------
; time_screen — the timer, until a key is pressed.
;
; A round sends every command TIME_RUNS times and puts its figure up as soon
; as it has one, so the screen fills a command at a time.  The keyboard is
; looked at between commands, so a key waits at most one batch.
; Clobbers (saved/restored): D0/D2/A0-A1
; ---------------------------------------------------------------------------
time_screen:
        MOVEM.L D0/D2/A0-A1,-(SP)
        BSR     time_setup
        BSR     time_frame
        BSR     time_header
.ts_round:
        MOVEQ   #0,D2
.ts_cmd:
        MOVE.B  D2,D0
        BSR     time_batch
        MOVE.B  D2,D0
        BSR     time_draw_one
        MOVE.B  D2,D0
        BSR     time_report
        BSR     amiga_getkey
        TST.B   D0
        BNE.S   .ts_leave
        ADDQ.B  #1,D2
        CMPI.B  #TIME_CMDS,D2
        BCS.S   .ts_cmd
        BRA.S   .ts_round
.ts_leave:
        BSR     screen_clear
        BSR     draw_title
        BSR     draw_device_row
        BSR     draw_keys
        BSR     pins_repaint
        BSR     paint_page
        MOVEM.L (SP)+,D0/D2/A0-A1
        RTS
