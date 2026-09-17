; amiga_config.s — build options for the Amiga Kickstart bootloader
; Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
;
; Each option is guarded, so the Makefile can override it with -D on the
; command line without editing this file.

; ---------------------------------------------------------------------------
; CONFIG_DEV_ALWAYS_MENU — `make DEV=1`.  The menu always appears, whatever
; the mouse buttons say.  A bench under remote control has no hand on the
; mouse, so a shipped build resets straight past the menu.
; ---------------------------------------------------------------------------
    ifnd CONFIG_DEV_ALWAYS_MENU
CONFIG_DEV_ALWAYS_MENU      EQU 0
    endc

; ---------------------------------------------------------------------------
; The banner.  Three switches, each covering both the code and the artwork it
; needs.  Any combination assembles and runs.
;
;   CONFIG_BANNER_ART     the tagline heading across the top, and the One ROM
;                         logo beside the list
;   CONFIG_BANNER_BALL    the checkered ball that bounces behind the logo and
;                         the list, and spins as it goes
;   CONFIG_BANNER_SHADOW  the ball's drop shadow.  Needs the ball.  Off by
;                         default, because the background is black and a
;                         shadow on it comes out as a pale halo
;
; Built with `make ART=0`, `make BALL=0`, `make SHADOW=1`.
; ---------------------------------------------------------------------------
    ifnd CONFIG_BANNER_ART
CONFIG_BANNER_ART           EQU 1
    endc
    ifnd CONFIG_BANNER_BALL
CONFIG_BANNER_BALL          EQU 1
    endc
    ifnd CONFIG_BANNER_SHADOW
CONFIG_BANNER_SHADOW        EQU 0
    endc

; No ball means no shadow, whatever the command line said.  This is what the
; rest of the source tests.
BANNER_SHADOW               EQU CONFIG_BANNER_BALL*CONFIG_BANNER_SHADOW

; The foreground object exists only to be put back over the ball, so it is
; built only when there is a ball.
BANNER_FG                   EQU CONFIG_BANNER_BALL

; ---------------------------------------------------------------------------
; CONFIG_BOOT_CHIME — `make CHIME=0` drops it.  Paula plays it once as the
; menu comes up.  See chime_start.
; ---------------------------------------------------------------------------
    ifnd CONFIG_BOOT_CHIME
CONFIG_BOOT_CHIME           EQU 1
    endc
