/* rbcp.h - ROM Bus Control Protocol host layer for 8088 real mode.
   Protocol version targeted: 0.1.2. */

#ifndef RBCP_H
#define RBCP_H

#include "config.h"

typedef unsigned char  u8;
typedef unsigned int   u16;
typedef unsigned long  u32;

/* Command groups. */
#define RB_G_CONTROL    0x00
#define RB_G_READ       0x01
#define RB_G_MODIFY     0x02
#define RB_G_RESET      0xAA

/* Group 0x00 - Control. */
#define RB_C_NOP                    0x00
#define RB_C_ENTER_CMD_RESP         0x01
#define RB_C_EXIT_ACK               0x02
#define RB_C_EXIT_SILENT            0x03
#define RB_C_SWITCH_AND_EXIT        0x04
#define RB_C_LOAD_AND_EXIT          0x05
#define RB_C_EXIT_RESTORE           0x06

/* Group 0x01 - Read. */
#define RB_R_FLASH_SLOT_COUNT       0x00
#define RB_R_FLASH_SLOT_INFO        0x01
#define RB_R_FLASH_SLOT_INFO_ALL    0x02
#define RB_R_RAM_SLOT_INFO_ALL      0x03
#define RB_R_DEVICE_TYPE            0x04
#define RB_R_DEVICE_VERSION         0x05
#define RB_R_PROTOCOL_VERSION       0x06
#define RB_R_SLOT_PEEK              0x07
#define RB_R_BOOT_SLOT_INFO         0x08

/* Group 0x02 - Modify. */
#define RB_M_SLOT_POKE              0x00
#define RB_M_SWITCH_SLOT            0x01
#define RB_M_LOAD_SLOT              0x02
#define RB_M_POKE_ALL_BYTE          0x03

/* Group 0xAA - Reset. */
#define RB_RESET_CMD                0xAA

/* Results. */
#define RB_OK           0   /* command completed, response = status-OK */
#define RB_FAILED       1   /* command completed, response = failed */
#define RB_NO_TOKEN     2   /* nothing answered, command was not received */
#define RB_NO_PROGRESS  3   /* received but never completed */

/* Nothing in this module calls the BIOS or DOS. */

/* Session state the caller may read after a successful rbcp_open(). */
extern u8  rb_ram_count;
extern u8  rb_ram_active;
extern u8  rb_boot_flash;
extern u8  rb_boot_ram;
extern u8  rb_proto_major;
extern u8  rb_proto_minor;
extern u8  rb_proto_patch;

/* The values the device was told to write into the progress and response
   fields, picked against whatever the image already held there. */
extern u8  rb_complete;
extern u8  rb_status_ok;

/* One raw byte of the back-channel region, for a caller reporting what the
   device actually put there. */
u8   rbcp_bch_byte(u16 n);

/* The specification's reset sequence on its own, to leave the device idle
   after a session that could not be opened. */
void rbcp_reset(void);

/* Saves the bytes the back-channel will displace. Call once, before any
   knock, while the device is still idle. */
void rbcp_save_region(void);

/* Reset sequence from the specification, then ENTER_CMD_RESP. Returns one
   of the RB_ codes. On RB_OK the device is in command-response mode. */
int  rbcp_open(void);

/* Puts the displaced bytes back and leaves command-response mode. Returns
   non-zero where the served image was restored in full, zero where some of
   it is still displaced - which matters, because a BIOS checksums its own
   ROM at power-on and a warm boot would then fail. */
int rbcp_close_restore(void);

/* Commands. Each returns an RB_ code and, where it has a response, leaves it
   in the caller's buffer. */
int  rbcp_get_protocol_version(void);
int  rbcp_get_device_type(char *buf, u8 len);
int  rbcp_get_device_version(char *buf, u8 len);
int  rbcp_get_ram_slot_info(void);
int  rbcp_get_boot_slot_info(void);
int  rbcp_get_flash_slot_info_all(u8 *total, u8 *whole, u8 *buf, u16 buflen);
int  rbcp_load_slot(u8 ram_slot, u8 flash_slot);
int  rbcp_slot_poke(u8 byte, u32 addr, u8 slot);

/* Called as an image is written, with bytes done and bytes total. It may draw
   to the screen, which is a write to video memory, but it must not call the
   BIOS or read the served image. */
typedef void (*rbcp_progress_fn)(u16 done, u16 total);

/* Writes an image into a RAM slot that is not the active one. */
int  rbcp_write_image(const u8 *img, u16 len, u8 slot, rbcp_progress_fn report);

/* Terminal commands. These exit command-response mode and write no response,
   so nothing may poll the back-channel afterwards. */
void rbcp_switch_and_exit(u8 ram_slot);
void rbcp_exit_silent(void);

/* LOAD_SLOT issued in command mode, for a device with one RAM slot where the
   copy has to run over the image being served. Leaving command-response mode
   first means no back-channel is maintained while it runs, so the image that
   lands is the flash image and nothing writes a header into it. There is
   nothing to poll, so the caller waits. */
void rbcp_load_slot_cmd_mode(u8 ram_slot, u8 flash_slot);

/* Timing, from PIT channel 0 rather than any BIOS tick. */
void rbcp_delay_ms(u16 ms);

#endif
