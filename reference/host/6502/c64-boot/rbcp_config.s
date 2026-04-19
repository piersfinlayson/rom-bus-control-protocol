; rbcp_config.s — RBCP reference implementation configuration settings
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; C64 bootloader kernal configuration for RBCP.

; Set to the high byte of the address the ROM is mapped to in the host system.
; For example, the C64 kernal ROM is mapped to $E000, hence $E0.
CONFIG_ROM_BASE_HI = $E0

; Set to the high byte to be used for RBCP address reads.  RBCP executed as
; read to transmit data to the device, and, when in command-response mode, the
; device ignored reads to the back channel region.  Hence this must be outside
; that region if the back channel is used.  For the C64, the back channel is
; likely to be at the start of the ROM image region ($E000), so $F0 is a good
; choice.
CONFIG_RBCP_READ_HI = $F0

; Set these to values that are not used by the ROM image in the progress and
; response byte locations (Offsets +$04 and +$05 in the back channel region).
; RBCP uses these values AND THE BITWISE INVERSE OF THESE VALUES to detect
; whether the device has updated them, so both the values configured here and
; their bitwise inverses must be unused in the ROM image as the appropriate
; locations.
CONFIG_RBCP_COMPLETE = $AA  ; inverse = $55
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

; Set to a timeout for RBCP to wait for responses in command-response mode.
; This is an arbitrary value with no fixed unit.  $00 = wait forever.
CONFIG_RBCP_POLL_TIMEOUT = $FF

; Set to the base address of the ZP block that the RBCP library should use.
; Must be at least 16 bytes long.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16