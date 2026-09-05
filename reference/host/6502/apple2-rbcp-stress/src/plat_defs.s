; plat_defs.s — what an Apple IIe is, to the reliability meter
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; The screen, the keys, and what this machine varies.  Everything else the
; meter needs is the same on every machine and lives in ../stress.

    .include "../rbcp/rbcp_defs.s"

; ---------------------------------------------------------------------------
; What an Apple IIe varies: nothing
;
; The video circuitry and the 6502 take alternate halves of every cycle, so
; fetching a row of characters costs the processor nothing and there are no
; badlines to stop.  Turning the display off would change the number of
; commands a second not at all, and would take the meter's own answer off the
; screen.  So this machine has no key and one column of counters, and a figure
; from a IIe is comparable with a C64's screen-on figure and not with anything
; else.
; ---------------------------------------------------------------------------

PLAT_VARY       = 0

; ---------------------------------------------------------------------------
; Soft switches
; ---------------------------------------------------------------------------

KBD             = $C000     ; bit 7 set = key waiting, bits 0-6 = ASCII
CLR80COL        = $C00C     ; 40 columns
CLRALTCHAR      = $C00E     ; primary character set, upper case and inverse
KBDSTRB         = $C010     ; any access clears the keyboard strobe
TXTSET          = $C051     ; text rather than graphics
MIXCLR          = $C052     ; whole screen, not split
TXTPAGE1        = $C054     ; display page 1 at $0400
LORES           = $C056     ; low resolution rather than hi-res

; ---------------------------------------------------------------------------
; Text screen.  Rows are not contiguous.  Row R starts at $0400 +
; (R AND 7) * $80 + (R / 8) * $28.
; ---------------------------------------------------------------------------

SCREEN_BASE     = $0400
SCREEN_COLS     = 40
SCREEN_ROWS     = 24

; ---------------------------------------------------------------------------
; The screen the meter draws on.  A row shorter than a C64's, so everything
; below the counts moves up one.
; ---------------------------------------------------------------------------

ROW_TITLE       = 0
ROW_DEV         = 2
ROW_VER         = 3
ROW_PROTO       = 4
ROW_PIPE        = 5
ROW_BIG         = 7
ROW_RAW         = 9
ROW_HEAD        = 11
ROW_FIRST       = 12        ; through ROW_FIRST + TEST_COUNT - 1
ROW_NOTE        = 18
ROW_REC_SENT    = 19
ROW_REC_GOT     = 20
ROW_KEYS        = 23

COL_NAME        = 1
COL_SENT        = 14
COL_BAD         = 30
COL_BIG         = 6

; Sent and errors are both ten digit counts, and the two with their labels take
; the row as far as column 33.  Lost goes on the row under it, right against
; the errors, which is where it belongs anyway.  It is the part of them the
; device never answered.
COL_RAW_SENT_LBL = 1        ; "SENT", 1 to 4
COL_RAW_SENT     = 6        ; 6 to 15
COL_RAW_BAD_LBL  = 20       ; "ERR", 20 to 22
COL_RAW_BAD      = 24       ; 24 to 33
COL_RAW_LOST_LBL = 19       ; "LOST", 19 to 22
COL_RAW_LOST     = 24       ; 24 to 33

; ---------------------------------------------------------------------------
; Zero page.  $F0-$FF is the RBCP library's.  Nothing else is running.  This
; ROM owns the machine from reset and never calls the monitor.
; ---------------------------------------------------------------------------

ZP_PTR_LO   = $E8
ZP_PTR_HI   = $E9
ZP_TMP0     = $EA
ZP_TMP1     = $EB
ZP_TMP2     = $EC
ZP_TMP3     = $ED
ZP_SCR_LO   = $EE
ZP_SCR_HI   = $EF

; A 40 column screen holds sent and wrong on one row, and lost on the next.
ROW_RAW_BAD      = ROW_RAW
ROW_RAW_LOST     = ROW_RAW + 1
