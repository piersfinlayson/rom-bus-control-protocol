; amiga_auxio_art.s — the shape of a pad and the words beside it
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.  Reached from RAM code by absolute long address.

; ---------------------------------------------------------------------------
; Pad sizes, largest first.  amiga_defs.s says how a page picks one.
;
; A box is a whole number of bytes wide so a row of it is written without
; shifting, and the pitch is the box, so pads never collide and redrawing one
; covers everything it covered before.
; ---------------------------------------------------------------------------
        EVEN
tier_d:                                 ; the pad's diameter
        DC.B    20,14,10,6
tier_pitch:                             ; the box, and so the pitch
        DC.B    32,24,16,8
tier_bytes:
        DC.B    4,3,2,1
tier_boxh:                              ; the box's depth, label included
        DC.B    36,28,24,12
tier_padx:                              ; the pad's place in the box
        DC.B    6,5,3,1
tier_pady:
        DC.B    4,3,3,3
tier_laby:                              ; the label's top row, or no label
        DC.B    26,19,15,TIER_NO_LABEL
tier_perrow:
        DC.B    8,12,18,36
tier_cap:                               ; pads this size holds on the board
        DC.B    24,48,72,255
tier_brx:                               ; the selection bracket's box
        DC.B    4,3,1,0
tier_brw:
        DC.B    24,18,14,8
        EVEN
tier_span:
        DC.L    pad20,pad14,pad10,pad6

; ---------------------------------------------------------------------------
; The pads themselves, four bytes a row.  The disc's start and width, then the
; centre's.  A centre of no width is a row the ring covers right across.
;
; Each shape mirrors along a row and along a column, so no side of it comes out
; cut.  pad20 is 20 rows deep and 18 columns across rather than square, because
; an Amiga lores pixel is not square and a disc drawn the same number of pixels
; each way does not look round on screen.
; ---------------------------------------------------------------------------
        EVEN
pad20:
        DC.B    7,6,0,0
        DC.B    5,10,0,0
        DC.B    4,12,0,0
        DC.B    3,14,8,4
        DC.B    2,16,6,8
        DC.B    2,16,5,10
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    1,18,4,12
        DC.B    2,16,5,10
        DC.B    2,16,6,8
        DC.B    3,14,8,4
        DC.B    4,12,0,0
        DC.B    5,10,0,0
        DC.B    7,6,0,0
        EVEN
pad14:
        DC.B    4,6,0,0
        DC.B    2,10,0,0
        DC.B    1,12,0,0
        DC.B    1,12,5,4
        DC.B    0,14,4,6
        DC.B    0,14,3,8
        DC.B    0,14,3,8
        DC.B    0,14,3,8
        DC.B    0,14,3,8
        DC.B    0,14,4,6
        DC.B    1,12,5,4
        DC.B    1,12,0,0
        DC.B    2,10,0,0
        DC.B    4,6,0,0
        EVEN
pad10:
        DC.B    3,4,0,0
        DC.B    1,8,0,0
        DC.B    1,8,4,2
        DC.B    0,10,3,4
        DC.B    0,10,2,6
        DC.B    0,10,2,6
        DC.B    0,10,3,4
        DC.B    1,8,4,2
        DC.B    1,8,0,0
        DC.B    3,4,0,0
        EVEN
pad6:
        DC.B    1,4,0,0
        DC.B    0,6,2,2
        DC.B    0,6,1,4
        DC.B    0,6,1,4
        DC.B    0,6,2,2
        DC.B    1,4,0,0

; ---------------------------------------------------------------------------
; The pen each role's ring takes, and the darker one its centre takes while
; the level is low.  A pin's owner therefore reads at either level.
; ---------------------------------------------------------------------------
        EVEN
role_pens:
        DC.B    PEN_THEIRS,PEN_FREE,PEN_OURS
role_pens_low:
        DC.B    PEN_THEIRS_LOW,PEN_FREE_LOW,PEN_OURS_LOW

; ---------------------------------------------------------------------------
; The legend under the count and the read rate beside it
; ---------------------------------------------------------------------------
        EVEN
str_leg_ours:
        DC.B    "AMIGA",0
        EVEN
str_leg_free:
        DC.B    "FREE",0
        EVEN
str_leg_theirs:
        DC.B    "ROM",0
        EVEN
str_leg_high:
        DC.B    "HIGH",0
        EVEN
str_leg_low:
        DC.B    "LOW",0
        EVEN
str_hz:
        DC.B    "HZ",0
        EVEN
str_blank:
        DC.B    "       ",0
        EVEN

; ---------------------------------------------------------------------------
; The command timer.  A command's name is T_LABEL_W characters so the four
; read as a column, and a figure that is not a number is T_FIG_W so the
; figures do too.
; ---------------------------------------------------------------------------
        EVEN
t_labels:
        DC.B    "AUX PIN ",0
        DC.B    "AUX GRP ",0
        DC.B    "PIPE WR ",0
        DC.B    "PIPE RD ",0
        EVEN
str_t_none:
        DC.B    "  ---",0
        EVEN
str_t_lost:
        DC.B    " LOST",0
        EVEN
str_t_absent:
        DC.B    " NONE",0
        EVEN
str_t_over:
        DC.B    " OVER",0
        EVEN

; The four bytes PIPE_WRITE carries.  They go down the pipe the log uses, so
; they are four dots in the middle of a log line.
        EVEN
str_t_payload:
        DC.B    "...."
        EVEN
str_t_units:
    ifne TIME_RUNS-256
    fail "the timer screen names the run count in str_t_units"
    endc
        DC.B    "MICROSECONDS A COMMAND OVER 256 RUNS",0
        EVEN
str_t_back:
        DC.B    "ANY KEY GOES BACK",0
        EVEN
str_t_min:
        DC.B    "MIN",0
        EVEN
str_t_max:
        DC.B    "MAX",0
        EVEN
str_t_frame:
        DC.B    "FRAME",0
        EVEN
str_t_bad:
        DC.B    "REFUSED",0
        EVEN
str_t_group:
        DC.B    "GROUP",0
        EVEN
str_t_pin:
        DC.B    "PIN",0
        EVEN
str_t_out:
        DC.B    "OUT PIPE",0
        EVEN
str_t_in:
        DC.B    "IN PIPE",0
        EVEN

; The same figures down the pipe.
        EVEN
str_log_timer:
        DC.B    "TIMER 256 RUNS GROUP ",0
        EVEN
str_log_t_pin:
        DC.B    " PIN ",0
        EVEN
str_log_time:
        DC.B    "TIME ",0
        EVEN
str_log_t_min:
        DC.B    " MIN ",0
        EVEN
str_log_t_max:
        DC.B    " MAX ",0
        EVEN
str_log_t_frame:
        DC.B    " FRAME ",0
        EVEN
str_log_t_bad:
        DC.B    " REFUSED ",0
        EVEN
