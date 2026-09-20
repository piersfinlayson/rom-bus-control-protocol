# 68K RBCP Host Routines

Routines a 68000 host uses to knock, send a command, poll and read the reply.

## Files

| File | Purpose |
|---|---|
| `rbcp_defs.s` | Protocol constants, the bus mapping, and the derived back-channel addresses |
| `rbcp.s` | The routines themselves |
| `sample_rbcp_config.s` | Annotated configuration to copy and edit |

Include them in that order, with your own `rbcp_config.s` first:

```
        INCLUDE "rbcp_config.s"
        INCLUDE "../rbcp/rbcp_defs.s"
        ...
        INCLUDE "../rbcp/rbcp.s"
```

`rbcp_defs.s` and `rbcp_config.s` hold definitions only, so they can be
included before the `ORG`. `rbcp.s` must be placed where the code will execute
— see *Execution environment* below.

## Bus mapping

RBCP is defined in terms of the address and data lines the *device* observes.
On a 68K the CPU drives its own wider set, so the library maps between the two
using five constants supplied by `rbcp_config.s`:

| Constant | Meaning |
|---|---|
| `CONFIG_RBCP_BUS_SHIFT` | log2 of the CPU address stride of one device bus cycle — 1 for a 16-bit bus, 2 for a 32-bit bus |
| `CONFIG_RBCP_DEV_SHIFT` | log2 of the bytes the device supplies per cycle — 0 for an 8-bit device, 1 for ×16 |
| `CONFIG_RBCP_DEV_MASK` | the low bits of a device word, `(1 << DEV_SHIFT) - 1` |
| `CONFIG_RBCP_LANE_OFF` | CPU byte offset of this device's lane within one bus cycle |
| `CONFIG_RBCP_ENDIAN_XOR` | Set where the host's byte order within a cycle runs opposite the specification's data-line assignment |

From these `rbcp_defs.s` works out the CPU address of every command byte and
every response header field, and converts the CPU-address placement in your
config into the device-side values `ENTER_CMD_RESP` takes — a command page
counted in device bus cycles, a back-channel start counted in device bytes.
Write CPU addresses in your config and leave that conversion to it.

### Supported configurations

|  | `BUS_SHIFT` | `DEV_SHIFT` | `DEV_MASK` | `LANE_OFF` | `ENDIAN_XOR` |
|---|---|---|---|---|---|
| One ×16 device, 16-bit bus | 1 | 1 | 1 | 0 | 1 |
| Two 8-bit devices, 16-bit bus — high lane | 1 | 0 | 0 | 0 | 0 |
| …low lane | 1 | 0 | 0 | 1 | 0 |
| Two ×16 devices, 32-bit bus — high word | 2 | 1 | 1 | 0 | 1 |
| …low word | 2 | 1 | 1 | 2 | 1 |
| Four 8-bit devices, 32-bit bus — lane L | 2 | 0 | 0 | L | 0 |

The first row is the one this library is used with.

On a multi-device bus the address lines are shared, which means:

- every device decodes every knock and every command
- each keeps its **own complete** back-channel header, the headers interleaved
  in CPU address space at the bus stride
- a host there polls every lane's header before treating a command as complete

This library polls one, so it suits a single-device bus.

One device is singled out in three ways:

- a pair of 8-bit ROMs — where the board wires them that way
- a single ×16 ROM — the word access itself drives it
- the 68020 and later — dynamic bus sizing does it instead of the strobes

## Execution environment

**This code must execute from RAM.** Instruction fetches from the ROM the
device is serving put their own addresses on the bus, and outside
command-response mode the device treats every address read as command data.
Once command-response mode is established the device filters on the command
page and ROM reads elsewhere become harmless. The knock and the
`ENTER_CMD_RESP` that establish it run before that filter is in place.

The Amiga example handles this by assembling a RAM section into the ROM image
and copying it to chip RAM before any RBCP traffic.

## Calling convention

- Every routine preserves every register it touches, except the ones it
  returns a value in.
- `D0` carries the result: 0 with Z set on success, non-zero with Z clear on
  failure.
- Callers set `RBCP_GROUP`, `RBCP_CMD` and `RBCP_ARG0..N` in scratch RAM
  before a command helper — a fixed RAM block.

On failure `RBCP_ERROR_CODE` holds the stage the command reached:

| Stage | Meaning |
|---|---|
| 1 | the token stayed put |
| 2 | progress stayed short of complete |
| 3 | the device reported failure |

## Routines

### Plumbing

| Routine | Purpose |
|---|---|
| `rbcp_knock` | Send the `!RBCP!` knock |
| `rbcp_send_cmd` | Send GROUP, CMD and `D0.B` argument bytes |
| `rbcp_save_token` / `rbcp_poll_token` | Token snapshot and poll |
| `rbcp_poll_progress` / `rbcp_poll_progress_long` / `rbcp_poll_progress_aux` | Progress poll, normal, NV and auxiliary timeouts |
| `rbcp_check_response` | Read the response field |
| `rbcp_issue_cmd` / `rbcp_issue_cmd_long_poll` / `rbcp_issue_cmd_aux_poll` | The full host polling sequence |
| `rbcp_reset` (and `rbcp_reset_stage1/2/3`) | The three-stage reset sequence |
| `rbcp_pause` | The inter-command gap |

### Reading the reply

On a word-organised ROM the data section's bytes are transposed in CPU address
space, so a linear index into that section is not a linear CPU offset.

| Routine | Purpose |
|---|---|
| `rbcp_region_addr` | CPU address of back-channel region byte `D0.W` |
| `rbcp_read_data` | Copy `D0.W` data bytes from data offset `D1.W` into `CONFIG_RBCP_DATA_BUF` in linear order |

A reply longer than `CONFIG_RBCP_DATA_BUF_SIZE` is read a window at a time,
moving `D1` along. `GET_FLASH_SLOT_INFO_ALL` returns a 4-byte preamble then a
32-byte record per slot, and a caller takes one record per call. Call either
routine after a command succeeds and before the next one is issued — the next
command overwrites the region. `rbcp_defs.s` gives the field offsets each
reply uses.

### Commands

Arguments the caller writes to scratch RAM before the call are named by their
`RBCP_ARG` slot. The rest arrive in registers.

| Routine | Takes |
|---|---|
| `rbcp_cmd_enter_cmd_resp` | nothing |
| `rbcp_cmd_nop` | nothing |
| `rbcp_cmd_exit_cmd_resp_ack` | nothing |
| `rbcp_cmd_switch_and_exit` | `D0.B` RAM slot |
| `rbcp_cmd_load_and_exit` | `D0.B` RAM slot, `D1.B` flash slot |
| `rbcp_cmd_get_proto_version` | nothing |
| `rbcp_check_protocol_version` | nothing |
| `rbcp_cmd_get_device_type` / `rbcp_cmd_get_device_version` | nothing |
| `rbcp_cmd_get_ram_info_all` | nothing |
| `rbcp_cmd_get_flash_count` | nothing |
| `rbcp_cmd_get_flash_info` | `D0.B` flash slot |
| `rbcp_cmd_get_flash_info_all` | nothing |
| `rbcp_cmd_slot_peek` | `ARG0` count, `ARG1/2/3` 24-bit offset, `ARG4` RAM slot |
| `rbcp_cmd_load_slot` | `D0.B` RAM slot, `D1.B` flash slot |
| `rbcp_cmd_get_nv_cap` | nothing |
| `rbcp_cmd_nv_peek` | `ARG0` count, `ARG1/2` location |
| `rbcp_cmd_nv_poke_commit_byte` | `ARG0` byte, `ARG1/2` location, `ARG3` RAM slot |
| `rbcp_cmd_get_pipe_cap` | nothing |
| `rbcp_cmd_get_pipe_info` | `D0.B` pipe |
| `rbcp_cmd_pipe_write` | `ARG0..3` payload, `D0.B` count, `D1.B` pipe |
| `rbcp_cmd_pipe_read` | `D0.B` count, `D1.B` pipe |
| `rbcp_cmd_get_aux_cap` | nothing |
| `rbcp_cmd_get_aux_group_info` | `D0.B` group |
| `rbcp_cmd_get_aux_pin_info` | `D0.B` pin, `D1.B` group |
| `rbcp_cmd_set_aux` | `ARG0` state, `ARG1` after, `ARG2` hold, `ARG3` pin, `ARG4` group |
| `rbcp_cmd_set_aux_and_exit` | as `rbcp_cmd_set_aux` |
| `rbcp_cmd_set_aux_switch_exit` | `ARG0` state, `ARG1` after, `ARG2` hold, `ARG3` flags, `ARG4` pin, `ARG5` group, `ARG6` RAM slot |
| `rbcp_cmd_get_led_cap` | nothing |
| `rbcp_cmd_get_led_info` | `D0.B` LED |
| `rbcp_cmd_get_led_mode_info` | `D0.B` LED, `D1.B` mode |
| `rbcp_cmd_set_led` | `ARG0` mode, `ARG1/2/3` colour, `ARG4` brightness, `ARG5` period, `ARG6` hold, `D0.B` LED |

`rbcp_cmd_enter_cmd_resp` takes its nine arguments from your config, and
`rbcp_check_protocol_version` issues `GET_PROTO_VERSION` and judges the
answer.

Pipes, auxiliary I/O and LEDs are optional. Ask the group's capability command
first. A device that does not implement the group fails that command without
consuming anything, so the session stays in step.

`rbcp_cmd_switch_and_exit`, `rbcp_cmd_load_and_exit`,
`rbcp_cmd_set_aux_and_exit` and `rbcp_cmd_set_aux_switch_exit` are terminal.
They send and pause, the device writes no response header, and the caller must
not poll afterwards.

`rbcp_cmd_set_aux` waits on `CONFIG_RBCP_AUX_POLL_TIMEOUT` because the device
holds the pin before it answers.

### The `$AA` guard

`$AA` is the reset marker, and the protocol forbids it as any command's final
argument. Where the caller picks the final argument — a pipe, an LED, a group,
a RAM slot — the routine refuses `$AA`, sends nothing, sets `RBCP_ERROR_CODE`
to 3 and returns `D0=1`. That covers `rbcp_cmd_get_pipe_info`,
`rbcp_cmd_pipe_read`, `rbcp_cmd_get_aux_group_info`,
`rbcp_cmd_get_aux_pin_info`, `rbcp_cmd_set_aux`, `rbcp_cmd_slot_peek`,
`rbcp_cmd_get_led_info`, `rbcp_cmd_get_led_mode_info` and `rbcp_cmd_set_led`.

The terminal commands do not refuse it. The caller asked to leave, and the
device declines the slot or the pin and completes the exit either way.

## Build-time checks

`rbcp_defs.s` checks at assembly time that:

- the configured back-channel start is 4-byte aligned in device terms
- both sentinel values differ from `$AA`
