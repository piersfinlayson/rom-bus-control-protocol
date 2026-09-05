# x86-based Host Reference RBCP Implementations

This directory contains reference implementations of RBCP hosts for x86 PCs. They are intended as examples and starting points for developers implementing an RBCP host on a PC-compatible machine.

## Contents

- [ROMSEL](romsel/README.md): A DOS program that picks which image a One ROM serves from an 8088 machine's BIOS socket, and resets into it. Includes an 8088 real-mode RBCP host layer in C.

## Requirements

- [Open Watcom](https://github.com/open-watcom/open-watcom-v2), which targets 16-bit real-mode DOS and hosts on DOS, Windows and Linux. The DOS and Linux builds are byte-identical, so this builds in CI without a DOS machine.
