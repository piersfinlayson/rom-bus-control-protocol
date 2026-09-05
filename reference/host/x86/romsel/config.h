/* config.h - build-time settings for ROMSEL.
   The version is ROMSEL's own. Everything after it describes the
   installation, not the protocol. */

#ifndef CONFIG_H
#define CONFIG_H

/* ROMSEL's version, shown on every screen. Not overridable: a build must not
   be able to claim a version it is not. */
#define CFG_VERSION     "0.1.0"

/* SEGMENT THE ROM WINDOW STARTS AT:
   An 8 KB XT BIOS lives at F000:E000, physical FE000. Expressing that as
   segment FE00 offset 0 lets a slot offset be used as a plain offset. */
#ifndef CFG_ROM_SEG
#define CFG_ROM_SEG     0xFE00
#endif

/* Size of the ROM image the device serves, in bytes. */
#ifndef CFG_ROM_SIZE
#define CFG_ROM_SIZE    0x2000
#endif

/* Host address bytes spanned by one device bus cycle. One ROM's 40-pin
   hardware does not observe the least significant address line of an 8-bit
   ROM, which makes this 2. A 28-pin part observes all of them, so it is 1.
   A stride of 2 needs a host window twice the slot size, which an 8 KB XT
   socket does not have. */
#ifndef CFG_STRIDE
#define CFG_STRIDE      1
#endif

/* Command page: the observed address bits above A7. Page N covers slot
   offsets N*256 to N*256+255. Reads that land here while command-response
   mode is active are taken as command bytes, so nothing else may read it. */
#ifndef CFG_CMD_PAGE
#define CFG_CMD_PAGE    0x10
#endif

/* Back-channel region, as a byte offset within the slot. Must be 4-byte
   aligned and must not overlap the command page. The bytes underneath are
   saved before the session and put back after it. */
#ifndef CFG_BCH_OFF
#define CFG_BCH_OFF     0x1800
#endif

/* Back-channel size. GET_FLASH_SLOT_INFO_ALL returns a 4-byte preamble plus
   32 bytes per slot, so 160 carries the header and four whole records. */
#ifndef CFG_BCH_SIZE
#define CFG_BCH_SIZE    160
#endif

/* Milliseconds to let the device finish switching before the reset jump. */
#ifndef CFG_SWITCH_MS
#define CFG_SWITCH_MS   20
#endif

/* Milliseconds allowed for one command in command-response mode. */
#ifndef CFG_CMD_MS
#define CFG_CMD_MS      50
#endif

/* Milliseconds allowed for a slot load, which copies from device flash. */
#ifndef CFG_LOAD_MS
#define CFG_LOAD_MS     400
#endif

/* Milliseconds between the sends of the reset sequence, where there is no
   back-channel to poll and the host must simply wait. */
#ifndef CFG_RESET_MS
#define CFG_RESET_MS    5
#endif

/* Most flash slots the menu will hold. */
#define CFG_MAX_SLOTS   16

#endif
