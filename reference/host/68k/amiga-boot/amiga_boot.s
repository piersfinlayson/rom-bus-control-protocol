; amiga_boot.s — Amiga RBCP Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; MILESTONE 1: prove entry into command-response mode.
;
; This build does the minimum needed to demonstrate that the host and device
; agree on the bus mapping: it resets the device, enters command-response
; mode, issues a NOP, and reports.  It deliberately displays the raw CPU
; bytes of the back-channel region before and after, so the byte-lane
; assignment can be read off the screen rather than assumed.
;
; The menu, slot enumeration, NV storage and boot switch come next.
;
; Build:
;   make            (see Makefile)
;
; ROM image layout (top-aligned; 256 KB from $FC0000 or 512 KB from $F80000):
;
;   ROM SECTION  — executed directly from ROM
;     ROM header, boot_cold_start, JMP boot_rom_entry
;     amiga_hw.s: a500_hw_init, exc_halt, screen_init
;     boot_rom_entry: HW init, screen up, copy RAM section, JMP $8000
;
;   RAM SECTION  — stored in ROM, copied to RAM_CODE_BASE ($8000) at boot
;     boot_ram_entry: the RBCP session
;     rbcp.s: RBCP protocol library
;     Screen rendering and hex output
;
;   ROM DATA SECTION — referenced via absolute long addresses from RAM code
;     copper_template, font_data, strings
;
;   $FFFC00  back-channel region (512 bytes, zeroed)
;   $FFFE00  command page        (512 bytes, zeroed)
;
; Why the split?
;   The knock and command sequences work by triggering specific ROM address
;   reads.  If the code performing them is itself fetched from that ROM, the
;   instruction-fetch addresses land on the bus and corrupt the sequence the
;   device sees.  Running from chip RAM removes all ROM instruction fetches
;   during the critical windows.
;
;   Once command-response mode is established the device filters on the
;   command page, so ROM reads elsewhere become harmless — which is why the
;   screen routines (which read the font from ROM) may be called after entry,
;   but never between the knock and the response to ENTER_CMD_RESP.
;
;   The initial hardware setup runs from ROM because it must execute before
;   the RAM section is copied.  It performs no RBCP address sequences.
;
; Addressing note:
;   RAM-section code reaches ROM data through explicit absolute long
;   addressing — LEA (label).L,A0 — never PC-relative.  The code is
;   assembled at its ROM address but executes from $8000, so a PC-relative
;   displacement computed at assembly time resolves to the wrong place at
;   run time.  The .L suffix also stops the assembler shortening high
;   addresses to sign-extended absolute short, which works on a 68000's
;   24-bit bus but not on a 32-bit one.

; Definitions first — the ORG below depends on CONFIG_ROM_BASE.  None of
; these emit any code or data.
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "amiga_defs.s"

        ORG     CONFIG_ROM_BASE

; ============================================================
; ROM SECTION
; ============================================================

; ---------------------------------------------------------------------------
; Kickstart-compatible ROM header
; At reset the 68K reads the SSP from ROM[$0] and the initial PC from ROM[$4]
; (ROM is mapped at $0 via OVL at power-on).
; ---------------------------------------------------------------------------
ROMStart:
        DC.W    $1114                   ; SSP[31:16] — conventional value
        DC.W    $4EF9                   ; SSP[15:0]  — conventional value
        DC.L    boot_cold_start         ; initial PC

        DCB.B   $D0-(*-ROMStart),$00    ; pad to offset $D0

        RESET                           ; +$D0: soft-reset entry
boot_cold_start:                        ; +$D2: CPU jumps here on power-on
        JMP     boot_rom_entry

; ---------------------------------------------------------------------------
; ROM-section hardware routines: a500_hw_init, exc_halt, screen_init
; screen_init contains a forward BSR to screen_clear in the RAM section; both
; are in ROM at assembly time so the PC-relative branch is correct there.
; ---------------------------------------------------------------------------
        INCLUDE "amiga_hw.s"

; ---------------------------------------------------------------------------
; boot_rom_entry — runs from ROM
;
; 1. Clear OVL so chip RAM appears at $0, then set the stack
; 2. Hardware init (chipset silent, exception vectors)
; 3. Bring up the display
; 4. Copy the RAM section from ROM to chip RAM at RAM_CODE_BASE
; 5. JMP to RAM_CODE_BASE = boot_ram_entry
; ---------------------------------------------------------------------------
boot_rom_entry:
        MOVE.W  #COL_RED,COLOR00
        MOVE.B  #$03,CIAA_DDRA      ; clear OVL — chip RAM now at $0
        MOVE.B  #$02,CIAA_PRA
        MOVEA.L #STACK_TOP,SP       ; SP set AFTER OVL cleared
        BSR     a500_hw_init
        MOVE.W  #COL_YELLOW,COLOR00

        BSR     screen_init

        ; Copy the RAM section (stored in the ROM image) to chip RAM
        LEA     (ram_section_rom_start).L,A0
        MOVEA.L #RAM_CODE_BASE,A1
        MOVE.W  #(ram_section_rom_end-ram_section_rom_start)/2-1,D0
.broe_copy:
        MOVE.W  (A0)+,(A1)+
        DBF     D0,.broe_copy

        ; boot_ram_entry is at offset 0 from ram_section_rom_start, so
        ; RAM_CODE_BASE is its exact address in chip RAM.
        JMP     RAM_CODE_BASE

; ============================================================
; RAM SECTION
; Stored in the ROM image between ram_section_rom_start and
; ram_section_rom_end, copied word-by-word to RAM_CODE_BASE ($8000).
;
; boot_ram_entry is at offset 0 so JMP RAM_CODE_BASE enters it directly.
;
; All BSR/BRA within this section are PC-relative and the distances between
; instructions are identical in ROM and in the RAM copy, so they resolve
; correctly from $8000.  References OUT of this section — to ROM data — use
; absolute long addressing.
; ============================================================
ram_section_rom_start:

; ---------------------------------------------------------------------------
; boot_ram_entry — application entry point (runs from chip RAM)
; ---------------------------------------------------------------------------
boot_ram_entry:
        MOVE.W  #COL_GREEN,COLOR00

        ; ------------------------------------------------------------------
        ; Header and derived configuration
        ; ------------------------------------------------------------------
        LEA     (str_title).L,A0
        MOVE.B  #0,D2
        MOVE.B  #1,D1
        BSR     screen_print

        BSR     show_config

        ; ------------------------------------------------------------------
        ; Raw back-channel bytes BEFORE any RBCP traffic.
        ; These come straight out of the ROM image, so they should all be $00
        ; — the region is zero-filled at build time.  Any other value here
        ; means the region is not where the configuration says it is.
        ; ------------------------------------------------------------------
        LEA     (str_before).L,A0
        MOVE.B  #ROW_BEFORE_LBL,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVEA.L #CONFIG_RBCP_BCH_ABS,A2
        MOVE.B  #ROW_BEFORE_HEX,D2
        MOVE.B  #1,D1
        BSR     hex_dump16

        ; ==================================================================
        ; RBCP session.  No ROM access of any kind from here until
        ; command-response mode is established — no screen output, because
        ; screen_putchar reads the font from ROM.
        ; ==================================================================
        BSR     rbcp_reset
        BSR     rbcp_cmd_enter_cmd_resp
        MOVE.B  D0,VAR_ENTER_RESULT
        MOVE.B  RBCP_ERROR_CODE,VAR_ENTER_STAGE
        ; ==================================================================
        ; Command-response mode is now either active — in which case the
        ; device filters on the command page and ROM reads elsewhere are
        ; ignored — or it was never entered.  Either way the screen is safe.
        ; ==================================================================

        LEA     (str_after).L,A0
        MOVE.B  #ROW_AFTER_LBL,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVEA.L #CONFIG_RBCP_BCH_ABS,A2
        MOVE.B  #ROW_AFTER_HEX,D2
        MOVE.B  #1,D1
        BSR     hex_dump16

        BSR     show_header

        ; ------------------------------------------------------------------
        ; Report the ENTER_CMD_RESP outcome
        ; ------------------------------------------------------------------
        TST.B   VAR_ENTER_RESULT
        BNE.S   .bre_enter_failed

        LEA     (str_entered).L,A0
        MOVE.B  #ROW_RESULT,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVE.W  #COL_GREEN,COLOR00

        ; ------------------------------------------------------------------
        ; NOP round-trip — proves the session is live, not just that one
        ; command landed.
        ; ------------------------------------------------------------------
        BSR     rbcp_cmd_nop
        MOVE.B  D0,VAR_NOP_RESULT
        MOVE.B  RBCP_ERROR_CODE,VAR_NOP_STAGE

        BSR     show_header             ; refresh: token should have moved

        TST.B   VAR_NOP_RESULT
        BNE.S   .bre_nop_failed
        LEA     (str_nop_ok).L,A0
        MOVE.B  #ROW_NOP,D2
        MOVE.B  #1,D1
        BSR     screen_print
        BRA     halt_forever

.bre_nop_failed:
        LEA     (str_nop_fail).L,A0
        MOVE.B  #ROW_NOP,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  VAR_NOP_STAGE,D0
        MOVEQ   #1,D4
        MOVE.B  #ROW_NOP,D2
        MOVE.B  #STAGE_COL,D1
        BSR     hex_out
        MOVE.W  #COL_ORANGE,COLOR00
        BRA     halt_forever

.bre_enter_failed:
        LEA     (str_not_entered).L,A0
        MOVE.B  #ROW_RESULT,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  VAR_ENTER_STAGE,D0
        MOVEQ   #1,D4
        MOVE.B  #ROW_RESULT,D2
        MOVE.B  #STAGE_COL,D1
        BSR     hex_out

        LEA     (str_stage_help).L,A0
        MOVE.B  #ROW_RESULT+1,D2
        MOVE.B  #1,D1
        BSR     screen_print
        MOVE.W  #COL_RED,COLOR00
        ; fall through

halt_forever:
        BRA.S   halt_forever

; ---------------------------------------------------------------------------
; show_config — display the values derived from rbcp_config.s
;
; Row A: the ROM geometry and the two values actually sent to the device —
;        the command page number and the back-channel start offset.  Both are
;        in DEVICE terms, and both differ from the CPU addresses above them.
; Row B: the CPU addresses the library will read the header fields from.
; ---------------------------------------------------------------------------
show_config:
        MOVEM.L D0-D4/A0-A2,-(SP)

        MOVE.B  #ROW_CFG_A,D2

        LEA     (str_c_rom).L,A0
        MOVE.B  #1,D1
        BSR     screen_print
        MOVE.L  #CONFIG_ROM_BASE,D0
        MOVEQ   #6,D4
        MOVE.B  #5,D1
        BSR     hex_out

        LEA     (str_c_sz).L,A0
        MOVE.B  #12,D1
        BSR     screen_print
        MOVE.L  #CONFIG_ROM_SIZE,D0
        MOVEQ   #6,D4
        MOVE.B  #15,D1
        BSR     hex_out

        LEA     (str_c_pg).L,A0
        MOVE.B  #22,D1
        BSR     screen_print
        MOVE.L  #RBCP_CMD_PAGE_REL,D0
        MOVEQ   #4,D4
        MOVE.B  #25,D1
        BSR     hex_out

        LEA     (str_c_bch).L,A0
        MOVE.B  #30,D1
        BSR     screen_print
        MOVE.L  #RBCP_BCH_START,D0
        MOVEQ   #6,D4
        MOVE.B  #34,D1
        BSR     hex_out

        LEA     (str_c_bsz).L,A0
        MOVE.B  #41,D1
        BSR     screen_print
        MOVE.L  #CONFIG_RBCP_BCH_SIZE,D0
        MOVEQ   #4,D4
        MOVE.B  #45,D1
        BSR     hex_out

        MOVE.B  #ROW_CFG_B,D2

        LEA     (str_c_ctok).L,A0
        MOVE.B  #1,D1
        BSR     screen_print
        MOVE.L  #RBCP_TOKEN_LSB_ADDR,D0
        MOVEQ   #6,D4
        MOVE.B  #6,D1
        BSR     hex_out

        LEA     (str_c_cprg).L,A0
        MOVE.B  #14,D1
        BSR     screen_print
        MOVE.L  #RBCP_PROGRESS_ADDR,D0
        MOVEQ   #6,D4
        MOVE.B  #19,D1
        BSR     hex_out

        LEA     (str_c_crsp).L,A0
        MOVE.B  #27,D1
        BSR     screen_print
        MOVE.L  #RBCP_RESPONSE_ADDR,D0
        MOVEQ   #6,D4
        MOVE.B  #32,D1
        BSR     hex_out

        MOVEM.L (SP)+,D0-D4/A0-A2
        RTS

; ---------------------------------------------------------------------------
; show_header — display the decoded response header
; Each field is read through its mapped CPU address, so this line and the raw
; dump above it should be consistent with the bus mapping and with nothing
; else.
; ---------------------------------------------------------------------------
show_header:
        MOVEM.L D0-D4/A0-A2,-(SP)
        MOVE.B  #ROW_HEADER,D2

        LEA     (str_h_grp).L,A0
        MOVE.B  #1,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  (RBCP_LASTCMD_GRP_ADDR).L,D0
        MOVEQ   #2,D4
        MOVE.B  #5,D1
        BSR     hex_out

        LEA     (str_h_cmd).L,A0
        MOVE.B  #9,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  (RBCP_LASTCMD_CMD_ADDR).L,D0
        MOVEQ   #2,D4
        MOVE.B  #13,D1
        BSR     hex_out

        LEA     (str_h_tok).L,A0
        MOVE.B  #17,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  (RBCP_TOKEN_LSB_ADDR).L,D0
        MOVEQ   #2,D4
        MOVE.B  #21,D1
        BSR     hex_out

        LEA     (str_h_prg).L,A0
        MOVE.B  #25,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  (RBCP_PROGRESS_ADDR).L,D0
        MOVEQ   #2,D4
        MOVE.B  #29,D1
        BSR     hex_out

        LEA     (str_h_rsp).L,A0
        MOVE.B  #33,D1
        BSR     screen_print
        MOVEQ   #0,D0
        MOVE.B  (RBCP_RESPONSE_ADDR).L,D0
        MOVEQ   #2,D4
        MOVE.B  #37,D1
        BSR     hex_out

        MOVEM.L (SP)+,D0-D4/A0-A2
        RTS

; ============================================================
; RBCP library (runs from RAM)
; ============================================================
        INCLUDE "../rbcp/rbcp.s"

; ============================================================
; Screen rendering and hex output (RAM section)
; font_data lives in the ROM data section and is reached by absolute long
; address, correct from any execution address.
; ============================================================

; ---------------------------------------------------------------------------
; screen_clear — zero the entire bitplane
; Also called from screen_init in the ROM section, via the ROM copy here.
; Clobbers (saved/restored): D0/A0
; ---------------------------------------------------------------------------
screen_clear:
        MOVEM.L D0/A0,-(SP)
        LEA     (BITPLANE_BASE).L,A0
        MOVE.W  #SCREEN_BPL_SZ/4-1,D0
.sc_loop:
        CLR.L   (A0)+
        DBF     D0,.sc_loop
        MOVEM.L (SP)+,D0/A0
        RTS

; ---------------------------------------------------------------------------
; screen_putchar — render one ASCII character into the bitplane
; Input : D0.B = character code, D1.B = column (0-79), D2.B = row (0-27)
; Clobbers (saved/restored): D0-D4/A0-A1
; ---------------------------------------------------------------------------
screen_putchar:
        MOVEM.L D0-D4/A0-A1,-(SP)

        ; Bitplane byte address = BITPLANE_BASE + row*640 + col
        ; row*640 = row*512 + row*128
        MOVEQ   #0,D3
        MOVE.B  D2,D3
        MOVE.W  D3,D4
        LSL.W   #8,D3               ; row * 256
        ADD.W   D3,D3               ; row * 512 (68000 max immediate shift 8)
        LSL.W   #7,D4               ; row * 128
        ADD.W   D4,D3               ; row * 640
        MOVEQ   #0,D4
        MOVE.B  D1,D4
        ADD.W   D4,D3               ; row*640 + col
        LEA     (BITPLANE_BASE).L,A1
        ADDA.W  D3,A1

        ; Glyph address = font_data + char_code * 8
        MOVEQ   #0,D3
        MOVE.B  D0,D3
        ASL.W   #3,D3
        LEA     (font_data).L,A0
        ADDA.W  D3,A0

        MOVE.B  (A0)+,(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*1(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*2(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*3(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*4(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*5(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*6(A1)
        MOVE.B  (A0)+,SCREEN_BPL_W*7(A1)

        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

; ---------------------------------------------------------------------------
; screen_print — print a null-terminated ASCII string
; Input : A0 = string pointer, D1.B = column, D2.B = row
; Characters beyond the last column are dropped.
; Clobbers (saved/restored): D0-D2/A0
; ---------------------------------------------------------------------------
screen_print:
        MOVEM.L D0-D2/A0,-(SP)
.sp_loop:
        MOVE.B  (A0)+,D0
        BEQ.S   .sp_done
        CMPI.B  #SCREEN_COLS,D1
        BCC.S   .sp_done
        BSR     screen_putchar
        ADDQ.B  #1,D1
        BRA.S   .sp_loop
.sp_done:
        MOVEM.L (SP)+,D0-D2/A0
        RTS

; ---------------------------------------------------------------------------
; hex_out — print the low D4.B nibbles of D0.L as hex
; Input : D0.L = value, D4.B = digit count (1-8), D1.B = column, D2.B = row
; Output: D1 advanced past the digits printed
; Clobbers (saved/restored): D0/D3-D5
; ---------------------------------------------------------------------------
hex_out:
        MOVEM.L D0/D3-D5,-(SP)
        MOVE.L  D0,D5               ; value
        MOVEQ   #0,D3
        MOVE.B  D4,D3
        SUBQ.B  #1,D3
        LSL.B   #2,D3               ; shift for the most significant nibble
.ho_loop:
        MOVE.L  D5,D0
        MOVE.B  D3,D4
        LSR.L   D4,D0
        ANDI.L  #$0F,D0
        CMPI.B  #10,D0
        BCS.S   .ho_digit
        ADDI.B  #7,D0               ; 'A'-'0'-10
.ho_digit:
        ADDI.B  #'0',D0
        BSR     screen_putchar
        ADDQ.B  #1,D1
        SUBI.B  #4,D3
        BCC.S   .ho_loop            ; borrow = ran past the last nibble
        MOVEM.L (SP)+,D0/D3-D5
        RTS

; ---------------------------------------------------------------------------
; hex_dump16 — dump 16 consecutive CPU bytes as hex, space separated
; Input : A2 = CPU address, D1.B = column, D2.B = row
; Clobbers (saved/restored): D0-D5/A2
; ---------------------------------------------------------------------------
hex_dump16:
        MOVEM.L D0-D5/A2,-(SP)
        MOVEQ   #16-1,D5
.hd_loop:
        MOVEQ   #0,D0
        MOVE.B  (A2)+,D0
        MOVEQ   #2,D4
        BSR     hex_out             ; advances D1 by 2
        ADDQ.B  #1,D1               ; separating space
        DBF     D5,.hd_loop
        MOVEM.L (SP)+,D0-D5/A2
        RTS

        EVEN
ram_section_rom_end:

; ============================================================
; ROM DATA SECTION
; Copper template, font and strings.  Reached from RAM code by absolute long
; address, so correct from any PC.
; ============================================================

        EVEN
copper_template:
        DC.W    COP_BPL1PTH,$0000       ; patched by screen_init
        DC.W    COP_BPL1PTL,$0000       ; patched by screen_init
        DC.W    COP_BPLCON0,$9200       ; 1 plane, HIRES, colour enable
        DC.W    COP_BPLCON1,$0000
        DC.W    COP_BPLCON2,$0024
        DC.W    COP_BPL1MOD,$0000
        DC.W    COP_DDFSTRT,$003C
        DC.W    COP_DDFSTOP,$00D4
        DC.W    COP_DIWSTRT,$2C81       ; NTSC display window start
        DC.W    COP_DIWSTOP,$F4C1       ; NTSC, 224 lines
        DC.W    COP_COLOR00,$0000       ; border: black
        DC.W    COP_COLOR01,$0FFF       ; text: white
        DC.W    $2C01,$FFFE             ; WAIT for start of display
        DC.W    COP_COLOR00,$0000       ; background: black
        DC.W    $FFFF,$FFFE             ; END
copper_template_end:

; font_8x8.bin: 256 glyphs * 8 bytes = 2048 bytes, no header.
; One byte per scan line, MSB = leftmost pixel.
        EVEN
font_data:
        INCBIN  "font_8x8.bin"
font_data_end:

        EVEN
str_title:
        DC.B    "AMIGA RBCP BOOTLOADER - MILESTONE 1: COMMAND-RESPONSE MODE",0
        EVEN
str_c_rom:
        DC.B    "ROM:",0
        EVEN
str_c_sz:
        DC.B    "SZ:",0
        EVEN
str_c_pg:
        DC.B    "PG:",0
        EVEN
str_c_bch:
        DC.B    "BCH:",0
        EVEN
str_c_bsz:
        DC.B    "BSZ:",0
        EVEN
str_c_ctok:
        DC.B    "@TOK:",0
        EVEN
str_c_cprg:
        DC.B    "@PRG:",0
        EVEN
str_c_crsp:
        DC.B    "@RSP:",0
        EVEN
str_before:
        DC.B    "BACK-CHANNEL RAW CPU BYTES BEFORE (EXPECT ALL ZERO):",0
        EVEN
str_after:
        DC.B    "BACK-CHANNEL RAW CPU BYTES AFTER:",0
        EVEN
str_h_grp:
        DC.B    "GRP:",0
        EVEN
str_h_cmd:
        DC.B    "CMD:",0
        EVEN
str_h_tok:
        DC.B    "TOK:",0
        EVEN
str_h_prg:
        DC.B    "PRG:",0
        EVEN
str_h_rsp:
        DC.B    "RSP:",0
        EVEN
str_entered:
        DC.B    "OK: ENTERED COMMAND-RESPONSE MODE",0
        EVEN
str_not_entered:
        DC.B    "FAILED TO ENTER COMMAND-RESPONSE MODE - STAGE",0
        EVEN
str_stage_help:
        DC.B    "  1=NO TOKEN  2=NO PROGRESS  3=DEVICE REPORTED FAILURE",0
        EVEN
str_nop_ok:
        DC.B    "OK: NOP ACKNOWLEDGED - SESSION IS LIVE",0
        EVEN
str_nop_fail:
        DC.B    "NOP FAILED - STAGE",0
        EVEN

; ============================================================
; Back-channel region — zeroed, at the CPU address the config derives
; ============================================================
        ORG     CONFIG_RBCP_BCH_ABS
        DCB.B   RBCP_BCH_CPU_SPAN,$00

; ============================================================
; Command page — zeroed, one page of device bus cycles
; ============================================================
        ORG     CONFIG_RBCP_CMD_PAGE_ABS
        DCB.B   RBCP_CMD_PAGE_SPAN,$00
