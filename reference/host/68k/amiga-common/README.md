# Amiga RBCP Application Routines

Each Amiga application includes these as source.

## Files

| File | Purpose |
|---|---|
| `amiga_defs.s` | The constants, the palette and the variable addresses every file here uses |
| `amiga_hw.s` | `a500_hw_init`, `exc_halt`, `kbd_init`, `screen_init` |
| `amiga_screen.s` | `screen_clear`, `screen_fill_row`, `screen_putchar`, `screen_print`, `screen_print_centred` |
| `amiga_screen_data.s` | The copper list template and the font |
| `amiga_input.s` | `amiga_getkey`, `both_buttons_held` |
| `amiga_input_data.s` | The character or token each keyboard scancode stands for |
| `amiga_device.s` | `draw_device` |
| `amiga_device_data.s` | The author line beside the device's name |
| `amiga_log.s` | `log_open`, `log_write`, `log_break`, `pipe_puts`, `log_line`, `log_crlf`, `log_dec`, `log_name_end`, `log_device` |
| `amiga_log_data.s` | The pieces a device line is built from |
| `amiga_error.s` | `err_halt`, `draw_err_diag`, `diag_field`, `print_hex_byte`, `log_error`, `log_hex_byte` |
| `amiga_error_data.s` | The error heading and the rule the log prints |
| `amiga_diag_data.s` | The diagnostic field labels for the screen and the pipe |
| `amiga_time.s` | `beam_line`, `tod_now`, `tod_start`, `wait_field` |
| `amiga_blit.s` | `blit_wait`, `blit_clear`, `blit_copy`, `blit_or`, `blit_cookie`, `obj_dest`, `draw_object`, `draw_object_solid` |
| `font_8x8.bin` | 256 glyphs of 8x8, one byte per scan line, no header |

## The three sections

`amiga-boot/amiga_boot.s` is the worked example.

| Section | Where it lives | Files |
|---|---|---|
| ROM | the ROM itself, before anything is copied | `amiga_hw.s` |
| RAM | chip RAM at `RAM_CODE_BASE` | every `.s` but `amiga_hw.s`, `amiga_defs.s` and the `_data.s` files |
| ROM data | read in place by absolute long address | the `_data.s` files |

[`../rbcp/README.md`](../rbcp/README.md) says why the RBCP code cannot run
from the ROM the device is serving. The same applies to everything that runs while a
command is in flight.

Include each file where its section is emitted. The definitions come before
the `ORG`:

```
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        INCLUDE "amiga_config.s"
        INCLUDE "../amiga-common/amiga_defs.s"

        ORG     CONFIG_ROM_BASE
        ...
        INCLUDE "../amiga-common/amiga_hw.s"
        ...
        INCLUDE "../amiga-common/amiga_screen.s"
        ...
        INCLUDE "../amiga-common/amiga_screen_data.s"
```

The font is found through `-I ../amiga-common`.

## Supplied by the application

| Name | Purpose |
|---|---|
| `str_title` | The heading text |
| `draw_title_at` | Draws `str_title` at `D2.B` = row. `err_halt` calls it |
| `err_msgs` | A `DC.L` table of message pointers the error number in `D0` indexes |
| `chime_stop` | Stops the chime. An application that sets `CONFIG_BOOT_CHIME` to 1 needs it |

Variables sit at fixed offsets from `VAR_BASE`. `amiga_defs.s` lists the ones
the code here owns: `VAR_BASE`+0 to +24, `APP_BASE`+$158 to +$15A,
`APP_BASE`+$160 to +$163 and `APP_BASE`+$170 to +$177. An application's own
variables go above all four — `amiga-rbcp-stress` starts at `APP_BASE`+$400.
Chip RAM holds whatever it held at reset, so an application clears its own
block and `CONFIG_RBCP_DATA_BUF` at startup, and clears or sets the shared
variables as well. `err_halt` fills `APP_BASE`+$170 to +$177 itself.

## The palette

`PEN00_RGB` to `PEN15_RGB` are the sixteen pens as `$0RGB`. Each is a default
an application replaces by defining it before `amiga_defs.s`.

```
PEN06_RGB   EQU $0999
        INCLUDE "../amiga-common/amiga_defs.s"
```

The values are assembled into the copper list `screen_init` installs, so a pen
is set when the image is built and does not change while the program runs.

The bootloader's artwork is generated against these defaults. Pens 0 to 5 are
the logo and the text, 6 to 13 the checks on its bouncing ball, 14 the drop
shadow and 15 spare.

`VAR_PEN` and `VAR_PEN_BG` take a pen number, and `amiga_defs.s` names four.

| Name | Pen | For |
|---|---|---|
| `PEN_BG` | 0 | the background |
| `PEN_GOLD` | 2 | One ROM gold |
| `PEN_TEXT` | 5 | text |
| `PEN_LIGHT` | 5 | the device line along the bottom |

## The keyboard

`amiga_getkey` polls once and returns a byte in `D0`. `D0` is the only
register it changes.

| Returns | Meaning |
|---|---|
| 0 | nothing pressed since the last poll |
| `$20` to `$7E` | the character on a typing key |
| a `KEY_` token below `$20` | a key with a name, or a mouse button |

Every token is below `$20` and every character is `$20` or above, so
`CMPI.B #$20,D0` tells them apart. `$1F` is the highest a new token may take.
`KEY_DEL` is a token rather than ASCII `$7F`.

| Token | Key |
|---|---|
| `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT` | the cursor keys |
| `KEY_RETURN` | RETURN, or the keypad's ENTER |
| `KEY_BACKSPACE`, `KEY_DEL` | BACKSPACE and DEL |
| `KEY_TAB`, `KEY_ESC` | TAB and ESC |
| `KEY_LMB`, `KEY_RMB` | a mouse button, once per press |

The typing keys are the US layout: the letters, the digits, and the
punctuation in both its unshifted and its shifted form. Shift is the one key
whose release is watched, because whether it is down picks which of the two
character tables the next key comes out of. The numeric keypad's digits, CAPS
LOCK, CTRL, ALT, AMIGA, HELP and the function keys read as nothing, as does
any key `amiga_input_data.s` holds a zero for.

The keyboard holds each code until the host handshakes it, so a press left
unread arrives late rather than not at all. After 143ms of no handshake the
keyboard decides the code was missed and sends it again with `$F9` in front to
say so. `amiga_getkey` drops the code behind a `$F9`, so one press gives one
character however long the host was busy. A loop that spends time waiting for
something else still polls here as it waits rather than once at the end, so
what somebody types appears as they type it. `amiga-aux-io`'s `blink_wait` is
the worked example.

## Drawing

The bitmap is four interleaved planes of 320x256 and the CPU renders text a
character cell at a time. `VAR_PEN` and `VAR_PEN_BG` pick the two pens a
cell takes and `VAR_COL_MAX` is the column printing stops at. `VAR_DRAW_BASE`
is the address the text routines draw to — the bitmap, or an off-screen object
of the same shape.

`amiga_blit.s` puts a four-plane object down in one blit and can cut it out
with a mask. An object is laid out as the bitmap is, so its rows are the same
shape and a rectangle of one goes into the other without shifting.

## Logging

`log_open` takes the pipe in `D0.B` and every log line goes down it from then
on. An application finds the pipe for itself. `rbcp_cmd_get_pipe_cap` says how
many the device has and `rbcp_cmd_get_pipe_info` gives one pipe's flags, and a
pipe with `RBCP_PIPE_FLAG_OUT` set carries host to device. The bootloader logs
through pipe 0. `amiga-rbcp-stress` walks the pipes and hands `log_open` the
first one reporting `RBCP_PIPE_FLAG_OUT`.

`log_line` and `log_device` return without doing anything until `log_open` has
been called, so an application calls them whether or not the device has a pipe.
Everything else here writes down `VAR_LOG_PIPE` whatever it holds, so nothing
else is safe before `log_open`.

A write the device will not take is sent again, up to `LOG_TRIES` goes in all.
`PIPE_WRITE` is all or nothing, so the same bytes go out again rather than
some part of them. Waiting for room would hang the machine on a far end that
is not reading. Bytes that will not go at all abandon the rest of the
line and leave a newline owed, which `log_break` sends before anything else
goes out. The stump then stands as a short line.

## Errors

`err_halt` takes an error number in `D0`, logs the raw device state, turns the
screen red and stops. There is no way back. The session is in an unknown state
and no image has loaded.
