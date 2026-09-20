; amiga_device.s — the device identity line
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; RAM section.  Asks the device what it is and puts the answer along the
; bottom of the screen.

; ---------------------------------------------------------------------------
; draw_device — the device's own name and version along the bottom, with the
; author beside them.  A device that will not name itself gets the author line
; alone.
;
; Forty columns leave no room for a long device name beside "piers.rocks", so
; the print limit is pulled in and a name that would reach it is cut short.
; Clobbers: D0-D3/A0
; ---------------------------------------------------------------------------
draw_device:
        MOVE.B  #PEN_LIGHT,VAR_PEN
        MOVE.B  #ROCKS_COL-1,VAR_COL_MAX
        BSR     rbcp_cmd_get_device_type
        TST.B   D0
        BNE.S   .rocks
        MOVEQ   #24,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.B  #DEVICE_COL,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
        ; measure the type to place the version after it
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVEQ   #DEVICE_COL,D3
.dd_len:
        TST.B   (A0)+
        BEQ.S   .dd_gotlen
        ADDQ.B  #1,D3
        BRA.S   .dd_len
.dd_gotlen:
        ADDQ.B  #1,D3                   ; a space between
        MOVE.B  D3,VAR_SAVED_KEY        ; the column, which the query clobbers
        BSR     rbcp_cmd_get_device_version
        TST.B   D0
        BNE.S   .rocks
        MOVEQ   #24,D0
        MOVEQ   #0,D1
        BSR     rbcp_read_data
        LEA     (CONFIG_RBCP_DATA_BUF).W,A0
        MOVE.B  VAR_SAVED_KEY,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
.rocks:
        MOVE.B  #SCREEN_COLS,VAR_COL_MAX
        MOVE.B  #PEN_GOLD,VAR_PEN
        LEA     (str_rocks).L,A0
        MOVE.B  #ROCKS_COL,D1
        MOVE.B  #DEVICE_ROW,D2
        BSR     screen_print
        MOVE.B  #PEN_TEXT,VAR_PEN
        RTS
