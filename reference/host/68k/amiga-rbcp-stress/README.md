# Amiga RBCP Reliability Meter

A Kickstart ROM image that measures how reliably a One ROM answers RBCP
commands on an Amiga. It runs a fixed set of commands in a loop and shows the
failure rate as a ratio.

## Controls

| Key | Action |
| --- | --- |
| `S` | switch the display on or off |

## Dependencies

[vasm and `onerom`](../README.md#requirements), and the shared Amiga routines
in [`../amiga-common/`](../amiga-common/README.md).

## Building

```
make images
```

Outputs `build/amiga_meter_256k.bin` and `build/amiga_meter_512k.bin`.

## Testing

[`test/`](test/README.md) runs the built image on an emulated Amiga 500 against
a fake RBCP device, so a session can be driven without hardware. It needs MAME
and the A500 keyboard MCU dump.

```
make
test/run.sh <rom-dir>
```

`RBCP_FAIL_EVERY` and `RBCP_LOSE_EVERY` provide a rate to count.

## Programming

```
onerom program --plugin usb --plugin host-control \
    --slot file=build/amiga_meter_512k.bin,type=27c400,label="RBCP Meter"
```

Read the report with `onerom monitor log`.
