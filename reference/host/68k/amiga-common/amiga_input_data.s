; amiga_input_data.s — what each keyboard scancode stands for
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; ROM data section.
;
; The keyboard sends a position, not a character, so the layout is these three
; tables.  They are the US layout.  A key a table holds a zero for reads as
; nothing pressed.

; One byte per scancode from $00, the key left of 1, to $40, the space bar.
; The numeric keypad, the two keys a US keyboard does not have and the
; scancodes no Amiga keyboard sends are the zeroes.
        EVEN
kbd_plain:
        DC.B    $60                     ; $00      `
        DC.B    "1234567890"            ; $01-$0A
        DC.B    $2D,$3D,$5C             ; $0B-$0D  - = \
        DC.B    0,0                     ; $0E-$0F  spare, keypad 0
        DC.B    "qwertyuiop"            ; $10-$19
        DC.B    $5B,$5D                 ; $1A-$1B  [ ]
        DC.B    0,0,0,0                 ; $1C-$1F  spare, keypad 1 2 3
        DC.B    "asdfghjkl"             ; $20-$28
        DC.B    $3B,$27                 ; $29-$2A  ; '
        DC.B    0,0                     ; $2B-$2C  extra key, spare
        DC.B    0,0,0                   ; $2D-$2F  keypad 4 5 6
        DC.B    0                       ; $30      extra key beside shift
        DC.B    "zxcvbnm"               ; $31-$37
        DC.B    $2C,$2E,$2F             ; $38-$3A  , . /
        DC.B    0,0,0,0                 ; $3B-$3E  keypad . 7 8 9
        DC.B    0                       ; $3F      spare
        DC.B    " "                     ; $40      SPACE

; The same scancodes with either shift key down.  A letter is the capital and
; SPACE is unchanged.
        EVEN
kbd_shifted:
        DC.B    $7E                     ; $00      ~
        DC.B    $21,$40,$23,$24,$25     ; $01-$05  ! @ # $ %
        DC.B    $5E,$26,$2A,$28,$29     ; $06-$0A  ^ & * ( )
        DC.B    $5F,$2B,$7C             ; $0B-$0D  _ + |
        DC.B    0,0                     ; $0E-$0F
        DC.B    "QWERTYUIOP"            ; $10-$19
        DC.B    $7B,$7D                 ; $1A-$1B  { }
        DC.B    0,0,0,0                 ; $1C-$1F
        DC.B    "ASDFGHJKL"             ; $20-$28
        DC.B    $3A,$22                 ; $29-$2A  : "
        DC.B    0,0                     ; $2B-$2C
        DC.B    0,0,0                   ; $2D-$2F
        DC.B    0                       ; $30
        DC.B    "ZXCVBNM"               ; $31-$37
        DC.B    $3C,$3E,$3F             ; $38-$3A  < > ?
        DC.B    0,0,0,0                 ; $3B-$3E
        DC.B    0                       ; $3F
        DC.B    " "                     ; $40      SPACE

; The keys whose scancodes run past the space bar's and that send a token
; instead of a character, from KBD_NAMED_FIRST for KBD_NAMED_COUNT bytes.
; Both RETURN keys give KEY_RETURN, so a hand on the keypad sends a line.
        EVEN
kbd_named:
        DC.B    KEY_BACKSPACE           ; $41
        DC.B    KEY_TAB                 ; $42
        DC.B    KEY_RETURN              ; $43      keypad ENTER
        DC.B    KEY_RETURN              ; $44
        DC.B    KEY_ESC                 ; $45
        DC.B    KEY_DEL                 ; $46
        DC.B    0,0,0                   ; $47-$49  spare
        DC.B    0,0                     ; $4A-$4B  keypad -, spare
        DC.B    KEY_UP                  ; $4C
        DC.B    KEY_DOWN                ; $4D
        DC.B    KEY_RIGHT               ; $4E
        DC.B    KEY_LEFT                ; $4F
