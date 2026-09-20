; pipe_read.s — PIPE_READ
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; One command to a module, so a host links only what it calls.

.include "../rbcp_defs.s"

.import rbcp_issue_cmd

.code

; rbcp_cmd_pipe_read: A = count, X = pipe. A count of zero asks for 256. The
; caller needs a data section holding 8 bytes plus the count it asks for, since
; a device that cannot fit the answer fails the command and reads nothing.
;
; On success the response is at RBCP_DATA_ADDR — see the RBCP_PIPE_READ_*
; offsets — and the bytes are at RBCP_PIPE_READ_DATA onwards, in the order the
; device held them.
;
; How many came back takes both of the first two fields. Where
; RBCP_PIPE_READ_FLAG_FULL is set the count asked for is the count that came,
; zero meaning 256 as it did in the command. Where it is clear, fewer arrived
; and RBCP_PIPE_READ_COUNT is how many: a zero there is an empty pipe, which is
; a success carrying no data rather than a failure, so a host polling an idle
; pipe never has to tell a quiet pipe from a broken one.
;
; RBCP_PIPE_READ_WAITING is what is left for the next read, measured after this
; one took its own. It saturates at $FF, so it carries a real count only below
; that.
;
; RBCP_PIPE_READ_FLAG_OVERRUN says the device threw bytes away before the host
; could read them, at some point since the last read that reported it. It does
; not say where they fell, so a caller that must resynchronise does so on
; framing of its own.
;
; $AA in a command's final argument byte is the reset marker, and the pipe
; number is this command's final byte. Sending $AA would desynchronise the
; session, so this sends nothing and reports rbcp_zp_5 = 4.
.export rbcp_cmd_pipe_read
rbcp_cmd_pipe_read:
    cpx #$AA
    beq @refuse
    sta rbcp_arg0           ; count, zero for 256
    stx rbcp_arg1           ; pipe
    lda #RBCP_GRP_PIPES
    sta rbcp_zp_0
    lda #RBCP_CMD_PIPE_READ
    sta rbcp_zp_1
    lda #2
    jmp rbcp_issue_cmd
@refuse:
    lda #4
    sta rbcp_zp_5
    sec
    rts
