# ROMSEL - Open Watcom wmake.  Needs wcc, wlink and wmake on the path, with
# WATCOM, INCLUDE and LIB set for a 16-bit DOS target.  DOS and Linux hosts
# both build it, and produce the same binary.
#
#   wmake
#
# Overridable settings, all of which describe the installation:
#
#   wmake ROM_SEG=0xFE00 ROM_SIZE=0x2000 STRIDE=1 CMD_PAGE=0x10 BCH_OFF=0x1800
#
# -s drops the stack-overflow probe, which would otherwise put a call in
# front of every bus read.

CC      = wcc
LINK    = wlink

!ifdef __UNIX__
BLD     = build/
MKBLD   = mkdir -p build
CLEAN   = rm -rf build
!else
BLD     = build\
MKBLD   = if not exist build mkdir build
CLEAN   = if exist build rmdir /s /q build
!endif

ROM_SEG  = 0xFE00
ROM_SIZE = 0x2000
STRIDE   = 1
CMD_PAGE = 0x10
BCH_OFF  = 0x1800
BCH_SIZE = 160

DEFS = -DCFG_ROM_SEG=$(ROM_SEG) -DCFG_ROM_SIZE=$(ROM_SIZE) &
       -DCFG_STRIDE=$(STRIDE) -DCFG_CMD_PAGE=$(CMD_PAGE) &
       -DCFG_BCH_OFF=$(BCH_OFF) -DCFG_BCH_SIZE=$(BCH_SIZE)

CFLAGS = -q -0 -ms -bt=dos -os -s -zq -wx $(DEFS)

OBJS = $(BLD)romsel.obj $(BLD)rbcp.obj $(BLD)vid.obj

all : $(BLD)romsel.exe .SYMBOLIC

# wlink puts the map in the current directory unless it is named, and
# nothing but build/ is generated here.
$(BLD)romsel.exe : $(OBJS)
	$(LINK) system dos name $(BLD)romsel.exe &
	    option quiet, map=$(BLD)romsel.map &
	    file $(BLD)romsel.obj file $(BLD)rbcp.obj file $(BLD)vid.obj

# Without -fo= Watcom writes .obj on DOS and .o on Linux, and the two hosts
# stop building the same file.
$(BLD)romsel.obj : romsel.c rbcp.h vid.h config.h
	@$(MKBLD)
	$(CC) $(CFLAGS) -fo=$(BLD)romsel.obj romsel.c

$(BLD)rbcp.obj : rbcp.c rbcp.h config.h
	@$(MKBLD)
	$(CC) $(CFLAGS) -fo=$(BLD)rbcp.obj rbcp.c

$(BLD)vid.obj : vid.c vid.h
	@$(MKBLD)
	$(CC) $(CFLAGS) -fo=$(BLD)vid.obj vid.c

clean : .SYMBOLIC
	@$(CLEAN)
