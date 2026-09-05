; display.s — the screen, and nothing else
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Nothing outside this file holds a string that goes on a screen.  Where each
; part of the display sits is the machine's business and comes from its
; plat_defs.s, and putting a character on the screen is plat_put's.  What is
; here is the layout and the words.
;
; The screen is drawn in two halves.  The words are drawn once, by
; display_frame, and the numbers over them by display_counts as they change.
; A loop that redrew the whole thing every turn would spend more time on the
; screen than on the device, and the point of this program is how many
; commands it can put through in a minute.

    .include "stress_defs.s"

.import plat_cls
.import plat_row
.import plat_put
.if PLAT_VARY
.import plat_vary_word
.import plat_key_word
.endif

.import num_val
.import num_den
.import num_txt
.import num_first
.import num_div
.import num_dec

.import cmd_sent
.import cmd_bad
.import vary_sent
.import vary_bad
.import lost
.import vary_idx
.import tot_bad
.import total_sent
.import total_bad

.import fail_stage
.import fail_group
.import fail_cmd
.import fail_args
.import fail_tok
.import fail_hdr

.import report_pipe
.import report_have_pipe

.import sess_dev_type
.import sess_dev_ver
.import sess_proto

; ---------------------------------------------------------------------------
; Field widths.  Ten digits is every value a 32-bit count can take, and every
; count here is a 32-bit count.  A narrow screen cannot spare ten in the
; per-command rows and takes eight for what each command sent and five for
; what it got wrong, both of which fill with plus signs rather than show a
; wrong number once the count outgrows them.  Lost gets the width of the error
; count, being the part of the errors the device never answered.
;
; The heading over the error column is as much of the word as the column is
; wide.
; ---------------------------------------------------------------------------

.if SCREEN_COLS >= 32
W_ROW_SENT  = 10
W_CMD_BAD   = 10
W_HEAD_BAD  = 5             ; "ERROR"
.else
W_ROW_SENT  = 8
W_CMD_BAD   = 5
W_HEAD_BAD  = 3             ; "ERR"
.endif
W_SENT      = 10
W_BAD       = 10

; ---------------------------------------------------------------------------
; The number fields
;
; Every count on the screen has a slot here, and the slot holds the characters
; that go in that field rather than the count they came from.  A refresh fills
; every slot and then writes them to the screen, which is what keeps the
; totals and the rows under them from being a photograph of two different
; moments.  See display_counts.
;
; There are two of each slot, one for what the numbers say now and one for
; what the screen already has, and only the characters that differ are
; written.  Most of a ten digit count is the same as it was last time.
;
; Ten characters a slot, which is the widest field there is, and the tables
; below say where each one goes.
; ---------------------------------------------------------------------------

FLD_STRIDE = 10

.if PLAT_VARY
F_BIG_ON    = 0
F_BIG_OFF   = 1
F_RAW_SENT  = 2
.else
F_BIG       = 0
F_RAW_SENT  = 1
.endif
F_RAW_BAD   = F_RAW_SENT + 1
F_LOST      = F_RAW_BAD + 1
F_CMD       = F_LOST + 1                    ; sent then wrong, a command each
.if PLAT_VARY
F_VARY      = F_CMD + TEST_COUNT * 2        ; sent then wrong, a setting each
FLD_COUNT   = F_VARY + VARY_COUNT * 2
.else
FLD_COUNT   = F_CMD + TEST_COUNT * 2
.endif

; ---------------------------------------------------------------------------
.bss
; ---------------------------------------------------------------------------

cur_colr:   .res 1
fld_w:      .res 1
fld_i:      .res 1
fld_x:      .res 1
fld_n:      .res 1
row_hold:   .res 1
.if PLAT_VARY
rat_idx:    .res 1
rat_fld:    .res 1
.endif

stage:      .res FLD_COUNT * FLD_STRIDE
shown:      .res FLD_COUNT * FLD_STRIDE
dirty_at:   .res FLD_COUNT      ; first character of the slot to write, or $FF
dirty_to:   .res FLD_COUNT      ; and the last

; ---------------------------------------------------------------------------
.code
; ---------------------------------------------------------------------------

.macro set_ptr addr
    lda #<addr
    sta ZP_PTR_LO
    lda #>addr
    sta ZP_PTR_HI
.endmacro

; LOAD32 — num_val = the four bytes at base + X.
.macro LOAD32 base
    lda base + 0, x
    sta num_val + 0
    lda base + 1, x
    sta num_val + 1
    lda base + 2, x
    sta num_val + 2
    lda base + 3, x
    sta num_val + 3
.endmacro

; ---------------------------------------------------------------------------
; emit — A = ASCII, Y = column.  Writes it in the colour last asked for and
; steps Y past it.  plat_put leaves Y alone for exactly this.
; Clobbers A, X.
; ---------------------------------------------------------------------------

emit:
    ldx cur_colr
    jsr plat_put
    iny
    rts

; ---------------------------------------------------------------------------
; put_str — the string at ZP_PTR, from column Y.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

put_str:
    sty fld_i
@loop:
    lda fld_i
    cmp #SCREEN_COLS            ; a name longer than the screen stops here
    bcs @done
    ldy #0
    lda (ZP_PTR_LO), y
    beq @done
    ldy fld_i
    jsr emit
    sty fld_i
    inc ZP_PTR_LO
    bne @loop
    inc ZP_PTR_HI
    bne @loop                   ; always taken
@done:
    ldy fld_i
    rts

; ---------------------------------------------------------------------------
; put_hex8 — A = value, Y = column.  Two digits, Y left past the second.
; Clobbers A, X.
; ---------------------------------------------------------------------------

put_hex8:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr @nybble
    pla
    and #$0F
@nybble:
    cmp #10
    bcc @digit
    clc
    adc #'A' - 10
    bne @out                    ; always taken
@digit:
    clc
    adc #'0'
@out:
    jmp emit

; ---------------------------------------------------------------------------
; stage_num — A = a field.  num_val as decimal into its slot, right aligned in
; the field's own width.  A value too big for the field fills it with plus
; signs rather than staging the wrong number.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

stage_num:
    sta fld_n
    jsr num_dec
    ldx fld_n
    lda fld_wid, x
    sta fld_w
    lda fld_ofs, x
    sta fld_x
    lda #10
    sec
    sbc fld_w
    sta fld_i                   ; digits the field has no room for
    ldx #0
@check:
    cpx fld_i
    beq @copy
    lda num_txt, x
    cmp #' '
    bne @over
    inx
    bne @check                  ; always taken
@copy:
    ldy fld_x
    ldx fld_i
@one:
    lda num_txt, x
    sta stage, y
    iny
    inx
    cpx #10
    bne @one
    rts
@over:
    ldy fld_x
    ldx fld_w
@plus:
    lda #'+'
    sta stage, y
    iny
    dex
    bne @plus
    rts

; ---------------------------------------------------------------------------
; stage_num_left — A = a field.  num_val as decimal into its slot, left
; aligned, the ten wide field padded out behind it.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

stage_num_left:
    sta fld_n
    jsr num_dec
    ldx fld_n
    lda fld_ofs, x
    tay
    ldx num_first
@one:
    lda num_txt, x
    sta stage, y
    iny
    inx
    cpx #10
    bne @one
    ldx num_first
    beq @done
@pad:
    lda #' '
    sta stage, y
    iny
    dex
    bne @pad
@done:
    rts

; ---------------------------------------------------------------------------
; stage_unknown — A = a field.  Dashes into its slot, for a ratio taken from
; no failures, which is not a measurement.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

stage_unknown:
    tax
    lda fld_ofs, x
    tay
    ldx #0
@dash:
    lda #'-'
    sta stage, y
    iny
    inx
    cpx #5
    bne @dash
@blank:
    lda #' '
    sta stage, y
    iny
    inx
    cpx #10
    bne @blank
    rts

; ---------------------------------------------------------------------------
; mark — the run of characters in each slot the screen does not already have.
;
; All of the comparing happens here, before the first character goes out, so
; the time it takes is not time the screen spends half old and half new.  A
; count that has gone up by a few hundred moves its last two or three digits
; and no more, so the run is usually shorter than the field.
; Clobbers A, X, Y.
; ---------------------------------------------------------------------------

mark:
    lda #0
    sta fld_n
@field:
    ldx fld_n
    lda #$FF
    sta dirty_at, x             ; nothing found yet
    lda fld_wid, x
    sta fld_w
    lda fld_ofs, x
    sta fld_x
    lda #0
    sta fld_i                   ; where in the slot
@char:
    ldy fld_x
    lda stage, y
    cmp shown, y
    beq @same
    ldx fld_n
    lda fld_i
    sta dirty_to, x             ; the last one differing, so far
    lda dirty_at, x
    bpl @same
    lda fld_i
    sta dirty_at, x
@same:
    inc fld_x
    inc fld_i
    dec fld_w
    bne @char
    inc fld_n
    lda fld_n
    cmp #FLD_COUNT
    bne @field
    rts

; ---------------------------------------------------------------------------
; paint — what mark found, in one run.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

paint:
    lda #0
    sta fld_n
@field:
    ldx fld_n
    lda dirty_at, x
    bmi @next
    sta fld_i
    lda dirty_to, x
    sec
    sbc fld_i
    tay
    iny
    sty fld_w                   ; how many characters
    lda fld_row, x
    jsr plat_row
    ldx fld_n
    lda fld_clr, x
    sta cur_colr
    lda fld_ofs, x
    clc
    adc fld_i
    sta fld_x
    lda fld_colm, x
    clc
    adc fld_i
    tay
@char:
    ldx fld_x
    lda stage, x
    sta shown, x
    jsr emit                    ; which steps Y past the column
    inc fld_x
    dec fld_w
    bne @char
@next:
    inc fld_n
    lda fld_n
    cmp #FLD_COUNT
    bne @field
    rts

; ---------------------------------------------------------------------------
; clear_row — A = row.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

clear_row:
    jsr plat_row
    lda #COLR_PLAIN
    sta cur_colr
    ldy #0
@cell:
    lda #' '
    jsr emit
    cpy #SCREEN_COLS
    bne @cell
    rts

; ---------------------------------------------------------------------------
; display_init — the machine's screen and the title bar, before anything has
; been asked of the device.
; ---------------------------------------------------------------------------

.export display_init
display_init:
    jsr plat_cls

    ; A blank screen agrees with no slot, so the first refresh writes them all.
    lda #0
    ldx #0
@fresh:
    sta shown, x
    inx
    cpx #FLD_COUNT * FLD_STRIDE
    bne @fresh

    lda #ROW_TITLE
    jsr plat_row
    lda #COLR_TITLE
    sta cur_colr
    ldy #0
@bar:
    lda #' '
    jsr emit
    cpy #SCREEN_COLS
    bne @bar

    lda #ROW_TITLE
    jsr plat_row
    set_ptr str_title
.if SCREEN_COLS >= 32
    ldy #1
.else
    ldy #0                      ; 22 columns hold the name and the brand only
.endif                          ; if the name starts hard against the edge
    jsr put_str
    lda #ROW_TITLE
    jsr plat_row
    set_ptr str_brand
.if SCREEN_COLS >= 32
    ldy #SCREEN_COLS - 12
.else
    ldy #SCREEN_COLS - 11
.endif
    jsr put_str
    rts

; ---------------------------------------------------------------------------
; display_frame — everything on the screen that does not change: what the
; device calls itself, which pipe the report goes down, the headings the
; counts sit under, and what there is to press.
; ---------------------------------------------------------------------------

.export display_frame
display_frame:
    lda #COLR_DIM
    sta cur_colr

    lda #ROW_DEV
    jsr plat_row
    set_ptr sess_dev_type
    ldy #1
    jsr put_str

    lda #ROW_VER
    jsr plat_row
    set_ptr sess_dev_ver
    ldy #1
    jsr put_str

    lda #ROW_PROTO
    jsr plat_row
    set_ptr sess_proto
    ldy #1
    jsr put_str

    ; Which pipe the report goes down, or that there is none and the only
    ; record of this run is the screen.
    lda #ROW_PIPE
    jsr plat_row
    lda report_have_pipe
    beq @no_pipe
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_pipe
    ldy #1
    jsr put_str
    lda report_pipe
    jsr put_hex8
    jmp @big
@no_pipe:
    lda #COLR_WARN
    sta cur_colr
    set_ptr str_no_pipe
    ldy #1
    jsr put_str

    ; The headline gets a band of its own, so that the numbers somebody is
    ; meant to read off the screen are the thing on it that cannot be missed.
@big:
    lda #ROW_BIG
    jsr plat_row
    lda #COLR_BAND
    sta cur_colr
    ldy #0
@band:
    lda #' '
    jsr emit
    cpy #SCREEN_COLS
    bne @band
    lda #ROW_BIG
    jsr plat_row
.if PLAT_VARY
    set_ptr str_big_on
    ldy #COL_BIG_ON_LBL
    jsr put_str
    set_ptr str_big_off
    ldy #COL_BIG_OFF_LBL
    jsr put_str
.else
    set_ptr str_one_in
    ldy #COL_BIG - 5
    jsr put_str
.endif

    lda #ROW_RAW
    jsr plat_row
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_sent_lbl
    ldy #COL_RAW_SENT_LBL
    jsr put_str
    lda #ROW_RAW_BAD
    jsr plat_row
    set_ptr str_bad_lbl
    ldy #COL_RAW_BAD_LBL
    jsr put_str
    lda #ROW_RAW_LOST
    jsr plat_row
    set_ptr str_lost_lbl
    ldy #COL_RAW_LOST_LBL
    jsr put_str

    lda #ROW_HEAD
    jsr plat_row
    lda #COLR_HEAD
    sta cur_colr
    set_ptr str_head_cmd
    ldy #COL_NAME
    jsr put_str
    set_ptr str_head_sent
    ldy #COL_SENT + W_ROW_SENT - 4
    jsr put_str
    set_ptr str_head_bad
    ldy #COL_BAD + W_CMD_BAD - W_HEAD_BAD
    jsr put_str

    ldx #0
@name:
    txa
    pha
    clc
    adc #ROW_FIRST
    jsr plat_row
    pla
    pha
    asl a
    tax
    lda test_names, x
    sta ZP_PTR_LO
    lda test_names + 1, x
    sta ZP_PTR_HI
    lda #COLR_PLAIN
    sta cur_colr
    ldy #COL_NAME
    jsr put_str
    pla
    tax
    inx
    cpx #TEST_COUNT
    bne @name

.if PLAT_VARY
    ; A setting's row is named ON or OFF and no more.  Two ten digit counts
    ; and their labels take the rest of the row, and what is being switched is
    ; already on the band above and on the key line below.
    lda #ROW_VARY
    jsr plat_row
    lda #COLR_HEAD
    sta cur_colr
    set_ptr str_on
    ldy #COL_NAME
    jsr put_str

    lda #ROW_VARY + 1
    jsr plat_row
    set_ptr str_off
    ldy #COL_NAME
    jsr put_str

    lda #ROW_VARY
    jsr plat_row
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_sent_lbl
    ldy #COL_VARY_SENTLBL
    jsr put_str
    set_ptr str_bad_lbl
    ldy #COL_VARY_BADLBL
    jsr put_str
    lda #ROW_VARY + 1
    jsr plat_row
    set_ptr str_sent_lbl
    ldy #COL_VARY_SENTLBL
    jsr put_str
    set_ptr str_bad_lbl
    ldy #COL_VARY_BADLBL
    jsr put_str
.endif

    lda #ROW_KEYS
    jsr plat_row
    lda #COLR_HEAD
    sta cur_colr
.if PLAT_VARY
    set_ptr str_press
    ldy #1
    jsr put_str
    set_ptr plat_key_word
    jsr put_str
    set_ptr str_switches
    jsr put_str
    set_ptr plat_vary_word
    jsr put_str
.else
    set_ptr str_nothing
    ldy #1
    jsr put_str
.endif
.if PLAT_VARY
    jmp display_vary
.else
    rts
.endif

; ---------------------------------------------------------------------------
; display_vary — which setting of the machine's own variable is running now.
; A marker in the left hand column, so that nothing has to be redrawn.
; ---------------------------------------------------------------------------

.if PLAT_VARY
.export display_vary
display_vary:
    lda #COLR_PLAIN
    sta cur_colr
    lda #ROW_VARY
    jsr plat_row
    ldy #COL_NAME - 1
    lda vary_idx
    beq @on_here
    lda #' '
    bne @put_on                 ; always taken
@on_here:
    lda #'>'
@put_on:
    jsr emit

    lda #ROW_VARY + 1
    jsr plat_row
    ldy #COL_NAME - 1
    lda vary_idx
    bne @off_here
    lda #' '
    bne @put_off                ; always taken
@off_here:
    lda #'>'
@put_off:
    jmp emit
.endif

; ---------------------------------------------------------------------------
; vary_ratio — A = a vary index, Y = the field.  One command wrong in how many
; at that setting, or dashes where the device has not got one wrong at that
; setting yet.  Clobbers A, X, Y.
; ---------------------------------------------------------------------------

.if PLAT_VARY
vary_ratio:
    sta rat_idx
    sty rat_fld
    asl a
    asl a
    tax
    lda vary_bad + 0, x
    sta num_den + 0
    lda vary_bad + 1, x
    sta num_den + 1
    lda vary_bad + 2, x
    sta num_den + 2
    lda vary_bad + 3, x
    sta num_den + 3
    ora num_den + 0
    ora num_den + 1
    ora num_den + 2
    bne @have
    lda rat_fld
    jmp stage_unknown
@have:
    lda rat_idx
    asl a
    asl a
    tax
    LOAD32 vary_sent
    jsr num_div
    lda rat_fld
    jmp stage_num_left
.endif

; ---------------------------------------------------------------------------
; display_counts — the numbers, and only the numbers.
;
; Every number is worked out into its slot first and the slots go on the
; screen afterwards, in one run.  The point of this program is a photograph of
; the screen, and the totals row has to be the sum of the rows under it in
; that photograph.  Drawing a field as soon as it is worked out leaves the top
; of the screen carrying this pass's figures and the bottom carrying the last
; pass's for as long as the arithmetic takes, which is a 32-bit divide and ten
; decimal conversions — long enough to photograph, and measured at a sixth of
; every frame on an emulated Apple IIe.  Splitting the two leaves only the
; character writes between the first figure changing and the last.
;
; Nothing else runs while this does.  Interrupts are masked from reset, so the
; counts cannot move under it and there is no need to copy them.  What has to
; be held still is the screen, not the counters.
; ---------------------------------------------------------------------------

.export display_counts
display_counts:
    jsr total_bad

    ; The headline.  A ratio taken from no failures is not a measurement, so
    ; until the first one it says so rather than showing a figure.  Where the
    ; machine varies something there is a figure for each setting, because one
    ; covering both says how long the run spent in each and nothing about the
    ; machine.
.if PLAT_VARY
    lda #VARY_ON
    ldy #F_BIG_ON
    jsr vary_ratio
    lda #VARY_OFF
    ldy #F_BIG_OFF
    jsr vary_ratio
.else
    lda tot_bad + 0
    ora tot_bad + 1
    ora tot_bad + 2
    ora tot_bad + 3
    bne @have
    lda #F_BIG
    jsr stage_unknown
    jmp @raw
@have:
    jsr total_sent
    lda tot_bad + 0
    sta num_den + 0
    lda tot_bad + 1
    sta num_den + 1
    lda tot_bad + 2
    sta num_den + 2
    lda tot_bad + 3
    sta num_den + 3
    jsr num_div
    lda #F_BIG
    jsr stage_num_left
.endif

@raw:
    jsr total_sent
    lda #F_RAW_SENT
    jsr stage_num
    lda tot_bad + 0
    sta num_val + 0
    lda tot_bad + 1
    sta num_val + 1
    lda tot_bad + 2
    sta num_val + 2
    lda tot_bad + 3
    sta num_val + 3
    lda #F_RAW_BAD
    jsr stage_num
    ldx #0
    LOAD32 lost
.if VARY_COUNT > 1
    clc                         ; the whole run, both settings added
    lda num_val + 0
    adc lost + 4
    sta num_val + 0
    lda num_val + 1
    adc lost + 5
    sta num_val + 1
    lda num_val + 2
    adc lost + 6
    sta num_val + 2
    lda num_val + 3
    adc lost + 7
    sta num_val + 3
.endif
    lda #F_LOST
    jsr stage_num

    ldx #0
@row:
    stx row_hold                ; two fields a row, sent then wrong
    txa
    asl a
    asl a
    tax
    LOAD32 cmd_sent
    lda row_hold
    asl a
    clc
    adc #F_CMD
    jsr stage_num

    lda row_hold
    asl a
    asl a
    tax
    LOAD32 cmd_bad
    lda row_hold
    asl a
    clc
    adc #F_CMD + 1
    jsr stage_num

    ldx row_hold
    inx
    cpx #TEST_COUNT
    bne @row

.if PLAT_VARY
    ldx #0
@vrow:
    stx row_hold

    ; How many commands went out at this setting.  Without it a row saying
    ; nothing has gone wrong reads the same after half a million commands as
    ; it does before the first one, and those are opposite results.
    txa
    asl a
    asl a
    tax
    LOAD32 vary_sent
    lda row_hold
    asl a
    clc
    adc #F_VARY
    jsr stage_num

    lda row_hold
    asl a
    asl a
    tax
    LOAD32 vary_bad
    lda row_hold
    asl a
    clc
    adc #F_VARY + 1
    jsr stage_num

    ldx row_hold
    inx
    cpx #VARY_COUNT
    bne @vrow
.endif
    jsr mark
    jmp paint

; ---------------------------------------------------------------------------
; display_record — what the last failure was, whole.
;
; Three rows.  What went wrong, the frame that went out, and what the device
; had written into the response header by the time the host gave up.  Reading
; the last two together is the diagnosis.  A GOT row naming a command other
; than the one on the SENT row is a frame the device did not receive as it was
; sent.
; ---------------------------------------------------------------------------

.export display_record
display_record:
    lda #ROW_NOTE
    jsr clear_row
    lda #ROW_REC_SENT
    jsr clear_row
    lda #ROW_REC_GOT
    jsr clear_row

    lda fail_stage
    cmp #STAGE_COUNT
    bcc @known
    lda #0                      ; a stage this program does not name
@known:
    asl a
    tax
    lda stage_tab, x
    sta ZP_PTR_LO
    lda stage_tab + 1, x
    sta ZP_PTR_HI
    lda #ROW_NOTE
    jsr plat_row
    lda #COLR_BAD
    sta cur_colr
    ldy #1
    jsr put_str

    lda #ROW_REC_SENT
    jsr plat_row
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_rec_sent
    ldy #1
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_group
    jsr put_hex8
    iny
    lda fail_cmd
    jsr put_hex8
    iny
    lda fail_args + 0
    jsr put_hex8
    iny
    lda fail_args + 1
    jsr put_hex8
    iny
    lda fail_args + 2
    jsr put_hex8
    iny
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_tok
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_tok
    jsr put_hex8

    lda #ROW_REC_GOT
    jsr plat_row
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_rec_got
    ldy #1
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_hdr + 0
    jsr put_hex8
    iny
    lda fail_hdr + 1
    jsr put_hex8
    iny
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_tok
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_hdr + 2
    jsr put_hex8
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_prg
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_hdr + 4
    jsr put_hex8
    lda #COLR_DIM
    sta cur_colr
    set_ptr str_rsp
    jsr put_str
    lda #COLR_PLAIN
    sta cur_colr
    lda fail_hdr + 5
    jmp put_hex8

; ---------------------------------------------------------------------------
; display_fail — A = a FAIL_ code.  Why the session never opened.
; ---------------------------------------------------------------------------

.export display_fail
display_fail:
    cmp #FAIL_COUNT
    bcs @out
    asl a
    tax
    lda fail_tab, x
    sta ZP_PTR_LO
    lda fail_tab + 1, x
    sta ZP_PTR_HI
    lda #ROW_NOTE
    jsr plat_row
    lda #COLR_BAD
    sta cur_colr
    ldy #1
    jmp put_str
@out:
    rts

; ---------------------------------------------------------------------------
.rodata
; ---------------------------------------------------------------------------

; Where each field goes, in the order display_counts fills the slots.
fld_row:
.if PLAT_VARY
    .byte ROW_BIG, ROW_BIG
.else
    .byte ROW_BIG
.endif
    .byte ROW_RAW, ROW_RAW_BAD
    .byte ROW_RAW_LOST
    .repeat TEST_COUNT, i
    .byte ROW_FIRST + i, ROW_FIRST + i
    .endrepeat
.if PLAT_VARY
    .repeat VARY_COUNT, i
    .byte ROW_VARY + i, ROW_VARY + i
    .endrepeat
.endif

fld_colm:
.if PLAT_VARY
    .byte COL_BIG_ON, COL_BIG_OFF
.else
    .byte COL_BIG
.endif
    .byte COL_RAW_SENT, COL_RAW_BAD
    .byte COL_RAW_LOST
    .repeat TEST_COUNT
    .byte COL_SENT, COL_BAD
    .endrepeat
.if PLAT_VARY
    .repeat VARY_COUNT
    .byte COL_VARY_SENT, COL_VARY_BAD
    .endrepeat
.endif

fld_wid:
.if PLAT_VARY
    .byte 10, 10
.else
    .byte 10
.endif
    .byte W_SENT, W_BAD
.if VARY_COUNT > 1
    .byte W_BAD, W_BAD
.else
    .byte W_BAD
.endif
    .repeat TEST_COUNT
    .byte W_ROW_SENT, W_CMD_BAD
    .endrepeat
.if PLAT_VARY
    .repeat VARY_COUNT
    .byte W_SENT, W_BAD
    .endrepeat
.endif

fld_clr:
.if PLAT_VARY
    .byte COLR_BAND, COLR_BAND
.else
    .byte COLR_BAND
.endif
    .byte COLR_PLAIN, COLR_BAD
.if VARY_COUNT > 1
    .byte COLR_BAD, COLR_BAD
.else
    .byte COLR_BAD
.endif
    .repeat TEST_COUNT
    .byte COLR_PLAIN, COLR_BAD
    .endrepeat
.if PLAT_VARY
    .repeat VARY_COUNT
    .byte COLR_PLAIN, COLR_BAD
    .endrepeat
.endif

; Where each field's slot starts.  The whole staging area is under 256 bytes,
; so a slot is reached with an index and no pointer arithmetic.
fld_ofs:
    .repeat FLD_COUNT, i
    .byte i * FLD_STRIDE
    .endrepeat

.if SCREEN_COLS >= 32
str_title:      .byte "RBCP RELIABILITY METER", 0
str_brand:      .byte "PIERS.ROCKS", 0
.if PLAT_VARY
str_big_on:     .byte "ON 1 IN", 0
str_big_off:    .byte "OFF 1 IN", 0
.else
str_one_in:     .byte "1 IN", 0
.endif
str_sent_lbl:   .byte "SENT", 0
str_bad_lbl:    .byte "ERR", 0
str_lost_lbl:   .byte "LOST", 0
str_head_cmd:   .byte "COMMAND", 0
str_head_sent:  .byte "SENT", 0
str_head_bad:   .byte "ERROR", 0
str_pipe:       .byte "REPORTING ON PIPE ", 0
str_no_pipe:    .byte "NO OUT PIPE AVAILABLE", 0
str_on:         .byte " ON", 0
str_off:        .byte " OFF", 0
str_press:      .byte "PRESS ", 0
str_switches:   .byte " TO SWITCH THE ", 0
str_nothing:    .byte "NO QUIT KEY - SWITCH OFF WHEN DONE", 0
str_rec_sent:   .byte "SENT ", 0
str_rec_got:    .byte "GOT  ", 0
str_tok:        .byte "  TOK ", 0
str_prg:        .byte "  PRG ", 0
str_rsp:        .byte "  RSP ", 0
.else
str_title:      .byte "RBCP METER", 0
str_brand:      .byte "PIERS.ROCKS", 0
str_one_in:     .byte "1 IN", 0
str_sent_lbl:   .byte "SENT", 0
str_bad_lbl:    .byte "ERR", 0
str_lost_lbl:   .byte "LOST", 0
str_head_cmd:   .byte "CMD", 0
str_head_sent:  .byte "SENT", 0
str_head_bad:   .byte "ERR", 0
str_pipe:       .byte "PIPE ", 0
str_no_pipe:    .byte "NO OUT PIPE", 0
str_nothing:    .byte "SWITCH OFF WHEN DONE", 0
str_rec_sent:   .byte "S", 0
str_rec_got:    .byte "G", 0
str_tok:        .byte " T", 0
str_prg:        .byte " P", 0
str_rsp:        .byte " R", 0
.endif

.export test_names
test_names:
    .word str_t_nop, str_t_proto, str_t_led_info, str_t_led_mode
.if SCREEN_COLS >= 32
str_t_nop:      .byte "NOP", 0
str_t_proto:    .byte "PROTO VER", 0
str_t_led_info: .byte "LED INFO", 0
str_t_led_mode: .byte "LED MODE", 0
.else
str_t_nop:      .byte "NOP", 0
str_t_proto:    .byte "PROTO", 0
str_t_led_info: .byte "LED INFO", 0
str_t_led_mode: .byte "LED MODE", 0
.endif

; What the library reached before it gave up, in the order rbcp_core.s numbers
; the stages.  Entry 0 is a stage this program does not name.
stage_tab:
    .word str_s_unknown, str_s_not_taken, str_s_unfinished, str_s_refused
.if SCREEN_COLS >= 32
str_s_unknown:    .byte "THE DEVICE STOPPED ANSWERING", 0
str_s_not_taken:  .byte "THE DEVICE DID NOT TAKE THE COMMAND", 0
str_s_unfinished: .byte "THE DEVICE TOOK IT AND NEVER FINISHED", 0
str_s_refused:    .byte "THE DEVICE REFUSED THE COMMAND", 0
.else
str_s_unknown:    .byte "STOPPED ANSWERING", 0
str_s_not_taken:  .byte "NOT TAKEN", 0
str_s_unfinished: .byte "NEVER FINISHED", 0
str_s_refused:    .byte "REFUSED", 0
.endif

; Why a session refused to start, in the order stress_defs.s numbers them.
fail_tab:
    .word str_f_nodev, str_f_enter, str_f_version
.if SCREEN_COLS >= 32
str_f_nodev:    .byte "NO DEVICE ANSWERED THE KNOCK", 0
str_f_enter:    .byte "THE DEVICE REFUSED THE SESSION", 0
str_f_version:  .byte "THE DEVICE SPEAKS A VERSION WE DO NOT", 0
.else
str_f_nodev:    .byte "NO DEVICE", 0
str_f_enter:    .byte "SESSION REFUSED", 0
str_f_version:  .byte "WRONG VERSION", 0
.endif
