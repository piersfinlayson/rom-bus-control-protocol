; rbcp_config.s — RBCP reference implementation configuration settings
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

; Apple II bootloader configuration for RBCP.
;
; Two sockets, two images.  A II or II+ has a 2KB F8 ROM at $F800.  A IIe has
; no F8 socket — its ROM is two 8KB parts, and the one holding the reset
; vector covers $E000-$FFFF.  Build the second with EF=1.
;
; Only where the image starts and how big it is differ.  Both end at $FFFF, so
; the command page and the back-channel region sit at the same addresses in
; both, and the two builds are the same code.

.ifdef EF

; The IIe EF socket, $E000-$FFFF, 8KB.
CONFIG_ROM_BASE_HI = $E0
CONFIG_ROM_SIZE = $2000

.else

; The II and II+ F8 socket, $F800-$FFFF, 2KB.
CONFIG_ROM_BASE_HI = $F8
CONFIG_ROM_SIZE = $0800

.endif

; Set to the high byte to be used for RBCP command page.
;
; $FE is the second to last page of the image.  A command page only has to be
; a page the host never reads while the session is open, and everything in
; this image that the bootloader reads has been copied to RAM before the
; session starts.  In the 2KB build that page holds ordinary code, because
; with 2KB to work in a page of padding is not affordable.  In the 8KB build
; it falls in the unused space above the code.
CONFIG_RBCP_CMD_PAGE = $FE

; The command page value relative to the start of the ROM image.  This is
; the value used to configure the device.
CONFIG_RBCP_CMD_PAGE_REL = CONFIG_RBCP_CMD_PAGE - CONFIG_ROM_BASE_HI

; Set to the base address of the back channel region, if used.  Should not
; conflict with the RBCP address read
;
; $FFB0 puts it at the top of the image, under the 6502 vectors, so the code
; below it is one unbroken run.  The host reads this region while the session
; is open, so the page holding it cannot be the command page.
CONFIG_RBCP_BCH_BASE = $FFB0

; Back-channel region start address, as a ROM-relative offset. Must be
; 4-byte aligned.
CONFIG_RBCP_BCH_START = (CONFIG_RBCP_BCH_BASE - (CONFIG_ROM_BASE_HI * $100))

; Set to the size of the back-channel region, including the header, in bytes.
;
; 64 bytes is the smallest region GET_FLASH_SLOT_INFO works in: an 8-byte
; response header and a 32-byte slot record.  The bootloader reads slot names
; one at a time for this reason, rather than asking for the whole list.
CONFIG_RBCP_BCH_SIZE = 64

; Set these to values that are not used by the ROM image in the progress and
; response byte locations (Offsets +$04 and +$05 in the back channel region).
; RBCP uses these values AND THE BITWISE INVERSE OF THESE VALUES to detect
; whether the device has updated them, so both the values configured here and
; their bitwise inverses must be unused in the ROM image as the appropriate
; locations.
CONFIG_RBCP_COMPLETE = $BB  ; inverse = $44
CONFIG_RBCP_STATUS_OK = $CC ; inverse = $33

; Set to a timeout for RBCP to wait for responses in command-response mode.
; This is an arbitrary value with no fixed unit.  $00 = wait forever.
CONFIG_RBCP_POLL_TIMEOUT = $FF

; A timeout to wait for non-volatile commits to complete, as these are likely
; to involve flash erases which take a long time (ms).
; This is an arbitrary value with no fixed unit.  $00 = wait forever.  The
; maximum is $FFFF
CONFIG_RBCP_NV_POLL_TIMEOUT = $FFFF

; SET_AUX with a hold waits on its own timeout, not the NV one: they bound
; unrelated things.
CONFIG_RBCP_AUX_POLL_TIMEOUT = $FFFF

; Set to the number of times to retry a command in command-response mode, if
; the device fails to acknowledge it within the timeout via a token increment.
; $00 = no retries.
CONFIG_RBCP_TIMEOUT_RETRIES = $00

; Used by RBCP to pause after sending a command when _not_ in command-response
; mode, to ensure the device has time to process it (as no back-channel is
; available to detect when the device is ready for the next command).  This is
; an arbitrary value with no fixed unit.  $00 = no pause.
; - $04 works using One ROM host-control plugin and a C64 bootloader kernal
CONFIG_RBCP_CMD_PAUSE = $04

; Set to the base address of the ZP block that the RBCP library should use.
; Must be at least 16 bytes long.
CONFIG_RBCP_ZP_BASE = $F0
CONFIG_RBCP_ZP_LENGTH = 16
