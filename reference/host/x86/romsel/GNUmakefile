# GNU make is not the build tool here.  Open Watcom's wmake is, and reads
# `makefile` alongside this.  This file exists so that `make` says so, rather
# than failing on wmake syntax it cannot parse.

.PHONY: all clean
all clean:
	@echo "ROMSEL builds with Open Watcom's wmake, not GNU make."
	@echo "Set WATCOM, INCLUDE and LIB for a 16-bit DOS target, then run: wmake"
	@echo "Open Watcom publishes no macOS build. See README.md."
	@exit 2
