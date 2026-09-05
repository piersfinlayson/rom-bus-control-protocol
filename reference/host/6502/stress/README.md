# RBCP Reliability Meter, shared code

The meter is one program built for three machines, and this directory holds the part common to all of them. What differs is the screen, the keys and the one thing each machine varies, which live in the application's own `plat_defs.s` and `plat.s`.

The applications are [C64](../c64-rbcp-stress/README.md), [VIC-20](../vic20-rbcp-stress/README.md) and [Apple IIe](../apple2-rbcp-stress/README.md). The C64 one documents what the meter is for and what it reports.

## The files

| File | Contents |
| --- | --- |
| `stress.s` | The loop, the padding that keeps it off one alignment, the counters, the phase, and the record of the last failure |
| `display.s` | The layout and every word that goes on a screen, in two layouts picked on `SCREEN_COLS` |
| `report.s` | The pipe report, a line for every failure and one every phase |
| `ratio.s` | The 32-by-32 division and decimal conversion behind `1 IN n` |
| `session.s` | The knock, command-response mode, the version check, and what the device calls itself |
| `stress_defs.s` | The commands under test, the counters' shapes, the colour roles, and the platform interface |

Two more come from [`../common/`](../common/). `rbcp_stage.s` names the three ways the library reports a command failing, and `rbcp_recover.s` is the reset and re-entry that puts a device which has stopped answering back together. The pipe tester uses both. What the meter keeps to itself is the count, a failure the device never answered being `LOST` against the setting it happened under.

## The platform interface

In `plat_defs.s`, as constants:

| | |
| --- | --- |
| `SCREEN_COLS`, `SCREEN_ROWS` | The screen the meter draws on. Under 32 columns gets the narrow layout |
| `ROW_*`, `COL_*` | Where each part of the display goes |
| `PLAT_VARY` | 1 if the machine varies something, 0 if not |
| `KEY_VARY` | The key that switches it, where there is one |
| `ZP_PTR_LO`, `ZP_PTR_HI` | Two zero page bytes the shared code walks strings with |

In `plat.s`, as routines:

| | |
| --- | --- |
| `plat_init` | The display, from RAM, before anything is asked of the device |
| `plat_cls` | A blank screen |
| `plat_row` | A = row. Points the screen writer at it |
| `plat_put` | A = ASCII, Y = column, X = a `COLR_` role. Y comes back untouched |
| `plat_key` | A key code, or `KEY_NONE_CODE` |
| `plat_vary_set` | A = 1 on, 0 off. Only where `PLAT_VARY` is 1 |
| `plat_vary_word` | The word for what is varied, with `plat_key_word` for the key. Only where `PLAT_VARY` is 1 |

and `stress_run`, which the machine's reset entry jumps to once the code is in RAM. It does not return.

## Video differences

A machine whose video steals cycles from the processor has two rates rather than one. On a C64 that is the VIC-II's badlines, and the meter keeps a separate set of counters for the display on and off, so a run that switches between them still says what each was.

A VIC-20's VIC-I and an Apple IIe's video take the alternate half of every cycle instead and steal nothing. Both set `PLAT_VARY` to 0, which costs them the key and the second row of counters and nothing else.

## Colour roles

The meter asks for a role and the machine decides what it looks like, or ignores it where the screen has no colour. `COLR_TITLE` and everything above it is reverse video where the machine has any, which is the title bar and the headline band.
