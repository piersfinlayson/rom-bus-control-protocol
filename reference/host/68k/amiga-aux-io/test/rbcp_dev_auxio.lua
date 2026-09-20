-- rbcp_dev_auxio.lua — a fake RBCP device for MAME, watching the Amiga's
-- Kickstart socket.
-- Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
--
-- Watches every read in the Kickstart window, decodes the RBCP command stream
-- from the addresses, and answers by substituting bytes on reads of the
-- back-channel region.
--
-- It is ../../amiga-boot/test/rbcp_dev_amiga.lua with the auxiliary board
-- from ../../../6502/apple2-boot/test/rbcp_dev.lua in it.
--
-- The 16-bit bus shapes the addresses the tap sees:
--   * the tap sees the even CPU address of a word, never a byte address
--   * one command byte is two CPU address bytes, so a command byte is
--     (offset - CMD_ABS) >> 1
--   * region byte N sits at CPU address BCH_ABS + (N xor 1), so a word read at
--     an even offset answers with region bytes rel+1 and rel, high byte first

local ROM_KB    = tonumber(os.getenv("RBCP_ROM_KB") or "256")
local ROM_BASE  = 0x1000000 - ROM_KB * 1024
-- Both regions sit at the top of the image, so neither moves with the size.
-- These must match rbcp_config.s.
local CMD_ABS   = 0xFFFE00
local BCH_ABS   = 0xFFFC00
local BCH_SIZE  = 512                   -- device bytes
local BCH_SPAN  = 512                   -- CPU bytes
local COMPLETE  = 0xBB
local STATUS_OK = 0xCC
local KNOCK     = { 0x21, 0x52, 0x42, 0x43, 0x50, 0x21 }

local NV_START   = tonumber(os.getenv("RBCP_NV") or "0")
local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "600")
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil
-- "01:06" makes the device ignore GET_PROTOCOL_VERSION entirely.  That is
-- how a device too busy to answer in time looks to the host.
local DEAF       = os.getenv("RBCP_DEAF")
-- "01:00:5" makes the device answer the response byte with what it held
-- before the command for five reads after it has said the command is
-- complete.  That is a device publishing the two out of order.
local LATE       = os.getenv("RBCP_LATE_RSP")
-- "05:02:20" makes the device leave the progress byte short of complete for
-- twenty reads of it after that command, so the host's poll spins.  That is a
-- device taking its time over one command, and it is what the command timer
-- has to see.
local SLOW       = os.getenv("RBCP_SLOW_CMD")
local SWITCH_IMG = os.getenv("RBCP_SWITCH_IMAGE")   -- served after the switch
-- Set to make the device expose no auxiliary pins.  A device with none is
-- legal, and it sends a host down its no-pins path.
local NO_AUX     = os.getenv("RBCP_NO_AUX") ~= nil

-- A device that goes wrong now and then rather than always.  One command in
-- FAIL_EVERY is answered with failure and one in LOSE_EVERY is not answered
-- at all, counted over every command the host sends.  RBCP_DEAF and
-- RBCP_REFUSE hold one command wrong for the whole run.  A host measuring a
-- failure rate needs failures at intervals, landing on whatever command is in
-- flight.
local FAIL_EVERY = tonumber(os.getenv("RBCP_FAIL_EVERY") or "0")
local LOSE_EVERY = tonumber(os.getenv("RBCP_LOSE_EVERY") or "0")
local commands, failed, lost = 0, 0, 0

-- Names a real device might carry.  One runs to twenty-nine characters and a
-- record holds thirty.
local slots = {
  [0] = "Amiga RBCP Bootloader",
  [1] = "Kickstart 1.3",
  [2] = "Kickstart 2.05",
  [3] = "DiagROM V2",
  [4] = "Adrian's Amiga Diagnostic ROM",
}
local total_flash = tonumber(os.getenv("RBCP_SLOTS") or "5")
for n = 5, total_flash - 1 do
  slots[n] = string.format("SPARE IMAGE %d", n)
end

-- The ROM type every slot reports.  A host offering a choice of image only
-- offers slots of the type it is being served, so this follows the socket: a
-- 27C200 for the 256 KB build, a 27C400 for the 512 KB one.
local ROM_TYPE = (ROM_KB == 512) and 0x13 or 0x21

-- How many RAM slots the device has.  One leaves the tester no spare slot to
-- stage an image in, so its reset exits with SET_AUX_AND_EXIT.  Two let it
-- stage a load in the spare and SET_AUX_SWITCH_EXIT to it.
local RAM_SLOTS = tonumber(os.getenv("RBCP_RAM_SLOTS") or "2")

-- The image the device serves once it has switched slots.  Without one the
-- tester is still the image in the socket after the switch and the machine
-- comes back as it.
local switch_img = nil
if SWITCH_IMG then
  local f = io.open(SWITCH_IMG, "rb")
  if f then switch_img = f:read("a") f:close() end
end

-- ---------------------------------------------------------------------------
-- Dirty chip RAM
--
-- MAME starts an A500 with chip RAM zeroed and a real one comes up holding
-- whatever the last program left.  A variable an application reads before it
-- writes reads 0 here and anything at all on the bench, so a missing
-- initialisation passes every run under MAME and fails on the machine.
--
-- The fill runs at the one moment nothing of the application's is in chip RAM:
-- the COL_YELLOW write to COLOR00 in rom_entry, after a500_hw_init has filled
-- the exception vectors and before screen_init, kbd_init and the copy of the
-- RAM section.  It starts above the vectors and the boot trampoline, which the
-- application writes rather than assumes, and ends at the 256 KB every
-- application is built to fit in.
--
-- RBCP_DIRTY picks the byte.  "count" steps $FF down to $01 and starts again,
-- so no byte is 0 — the one value that hides this kind of fault — and
-- neighbouring bytes differ, so an unwritten word or long is junk too.  A hex
-- byte fills with that byte throughout, which is how a run that found
-- something is narrowed down.  "off" leaves chip RAM as MAME zeroes it.
-- ---------------------------------------------------------------------------
local COLOR00    = 0xDFF180
local COL_YELLOW = 0x0FF0
local DIRTY_LOW  = 0x001000
local DIRTY_HIGH = 0x03FFFF
local DIRTY      = os.getenv("RBCP_DIRTY") or "count"
local dirty_byte                        -- nil where the fill is off
if DIRTY == "count" then
  dirty_byte = function(addr) return 0xFF - (addr % 255) end
elseif DIRTY ~= "off" then
  local b = tonumber(DIRTY, 16)
  if b == nil or b < 0 or b > 0xFF then
    error("RBCP_DIRTY is count, off, or a hex byte such as FF")
  end
  dirty_byte = function() return b end
end
local dirtied = false

local bch = {}                          -- region bytes, index 0..BCH_SIZE-1
for i = 0, BCH_SIZE - 1 do bch[i] = 0 end

-- The command that holds its response back, the number of reads it holds it
-- for, and the value those reads answer with.
local late_g, late_c, late_n
if LATE then
  local g, c, n = LATE:match("^(%x%x):(%x%x):(%d+)$")
  if not g then error("RBCP_LATE_RSP must be GG:CC:reads, e.g. 01:00:5") end
  late_g, late_c, late_n = tonumber(g, 16), tonumber(c, 16), tonumber(n)
end
local late_left, late_val = 0, 0

-- The command the device is slow over and how many reads of the progress byte
-- it stays short of complete for.
local slow_g, slow_c, slow_n
if SLOW then
  local g, c, n = SLOW:match("^(%x%x):(%x%x):(%d+)$")
  if not g then error("RBCP_SLOW_CMD must be GG:CC:reads, e.g. 05:02:20") end
  slow_g, slow_c, slow_n = tonumber(g, 16), tonumber(c, 16), tonumber(n)
end
local slow_left = 0

-- The auxiliary pins the device pretends to have.  There are four groups, so
-- a host that assumed a single group is caught.  The first is GPIO with only
-- the even pins from 2 upwards drivable, the second an image-select group with
-- nothing drivable in it, the third a pair of pads, and the fourth the socket
-- the device serves the ROM through.
--
-- Pads 0 and 1 — group 2 — are the loopback pair, wired together so driving
-- pad 0 moves pad 1.  A host can then be shown reading a pin it did not drive.
--
-- Group 3 is eighteen address lines and sixteen data lines on the socket the
-- device serves the ROM through, reported as GPIO because the protocol names
-- no type for a bus.  Eighteen is a 27C400's count, and the 256 KB build gets
-- it too, because the fake device does not size the group to the build.  A
-- real One ROM reports them and a host reading them sees them move, so the
-- all-pins page has fifty pins moving on it.
local BUS_ADDR_PINS = 18
local BUS_DATA_PINS = 16
local AUX_GROUPS = {
  [0] = { type = 0x01, pins = 10, drv = { [2] = true, [4] = true, [6] = true,
                                          [8] = true } },
  [1] = { type = 0x80, pins = 4,  drv = {} },
  [2] = { type = 0x81, pins = 2,  drv = { [0] = true } },
  [3] = { type = 0x01, pins = BUS_ADDR_PINS + BUS_DATA_PINS, drv = {},
          bus = true },
}
local LOOPBACK     = { [2] = { [0] = 1 } }  -- group, then source pin, follower
-- The longest hold the device will time, in units of 10ms.  255 is 2.55
-- seconds.  Zero is a device that times no hold at all, which cannot pulse a
-- pin, and a small value is one the host has to cut its pulse down to.
local AUX_MAX_HOLD = tonumber(os.getenv("RBCP_AUX_MAX_HOLD") or "255")
local AUX_STATE    = { [0] = "low", "high", "released" }

if NO_AUX then AUX_GROUPS, LOOPBACK = {}, {} end

local aux_count = 0
for _ in pairs(AUX_GROUPS) do aux_count = aux_count + 1 end

-- Power-on state.  Nothing is driven, and nothing on the board pulls a net, so
-- every pin reads low.  This lives in dev and is never cleared, because a
-- pin's state outlives the session and survives RBCP_RESET — only a device
-- reset puts it back.
local function aux_power_on()
  local t = {}
  for n, grp in pairs(AUX_GROUPS) do
    t[n] = {}
    for p = 0, grp.pins - 1 do t[n][p] = { level = 0, driven = 0 } end
  end
  return t
end

local dev = {
  cmd_resp = false,
  knock_at = 0,                         -- how much of the knock has matched
  knocked  = false,
  group    = nil,
  cmd      = nil,
  args     = {},
  want     = 0,
  token    = 0,
  nv       = NV_START,
  active_ram = 0,
  switched = nil,
  aux      = aux_power_on(),
  bus_addr = 0,                         -- the last word address the ROM saw
  bus_data = 0,                         -- and the word that went back
}

-- A socket pin's level: the address lines carry the last word address read
-- and the data lines the word that answered it.  The device holds what it
-- last saw, so a host reading the pins one at a time sees a different bus
-- cycle behind each one, which is what a real board gives it.
local function bus_level(p)
  local bit = p
  local word = dev.bus_addr
  if p >= BUS_ADDR_PINS then
    bit, word = p - BUS_ADDR_PINS, dev.bus_data
  end
  return (word >> bit) & 1
end

-- The frame counter and the hold the device is still timing.  A SET_AUX with
-- a non-zero hold does not complete until the hold has elapsed, so its answer
-- waits here instead of going out with the command.  Both are declared here
-- because execute() and the frame loop below touch them.
local frames = 0
local pending = nil

-- The LED commands the bootloader harness exercises.  This tester sends none.
local LED_TYPE = { [0] = 0x00, [1] = 0x01 }
local MODE_NAME = { [0] = "off", "on", "blink", "breathe", "cycle", "beacon" }
local last_led_info = nil               -- the LED GET_LED_INFO last reported

local ARGS = {                          -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9, [0x02] = 0, [0x03] = 0, [0x04] = 1,
             [0x05] = 2 },
  [0x01] = { [0x00] = 0, [0x01] = 1, [0x02] = 0, [0x03] = 0, [0x04] = 0,
             [0x05] = 0, [0x06] = 0, [0x07] = 5 },
  [0x02] = { [0x02] = 2 },
  [0x03] = { [0x00] = 0, [0x01] = 3, [0x06] = 4 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6, [0x03] = 2 },
  [0x05] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 5, [0x04] = 5,
             [0x05] = 7 },
  [0x06] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 8 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

-- The far end's side of the pipe, as RBCP_SEND holds it.  "\n" in that
-- variable is a line feed, which ends a line at the far end of a real pipe.
-- PIPE_READ hands it over a read at a time and GET_PIPE_INFO says how much of
-- it is left.
local rx_text = (os.getenv("RBCP_SEND") or ""):gsub("\\n", "\n")
local rx_at = 1

-- The most PIPE_READ can be asked for here is the data section less the eight
-- bytes of header the command puts in front of the data.
local PIPE_READ_ROOM = BCH_SIZE - 8 - 8

local function rx_waiting()
  local n = #rx_text - rx_at + 1
  if n < 0 then n = 0 end
  if n > 0xFF then n = 0xFF end
  return n
end

local function printable(s)
  return (s:gsub("[^\32-\126]", function (ch)
    return ch == "\n" and "\\n" or "."
  end))
end

-- PIPE_WRITE moves at most four bytes, so a log line arrives in pieces.  They
-- are held here until the line feed that ends the line, then printed whole.
local tx_line = ""
local function pipe_out(s)
  tx_line = tx_line .. s
  while true do
    local nl = tx_line:find("\n")
    if not nl then break end
    io.write("[pipe] " .. printable(tx_line:sub(1, nl - 1)) .. "\n")
    tx_line = tx_line:sub(nl + 1)
  end
end

-- Flush a line a run ended part way through, so an error line with no line
-- feed behind it is still seen.
local function pipe_flush()
  if tx_line ~= "" then pipe_out(tx_line .. "\n") end
end

-- What the device saw, printed as the run ends.  A host that draws to a
-- bitmap leaves nothing to read on screen, so this is what says the session
-- ran at all and how much of it went through.
local function summary()
  if dirty_byte and not dirtied then
    log("chip RAM was never dirtied — rom_entry was not reached")
  end
  log("%d commands, %d failed, %d lost", commands, failed, lost)
end

-- The group and command default to the ones in hand.  A deferred hold names
-- them, because by the time it answers the device has finished reading the
-- command that asked for it.
local function answer(ok, g, c)
  g, c = g or dev.group, c or dev.cmd
  dev.token = (dev.token + 1) & 0xFFFF
  bch[0] = g
  bch[1] = c
  bch[2] = dev.token & 0xFF
  bch[3] = (dev.token >> 8) & 0xFF
  bch[4] = COMPLETE
  if slow_g and g == slow_g and c == slow_c then slow_left = slow_n end
  if late_g and g == late_g and c == late_c then
    late_left, late_val = late_n, bch[5]
    log("%02X/%02X response held back for %d reads", late_g, late_c, late_n)
  end
  bch[5] = ok and STATUS_OK or ((~STATUS_OK) & 0xFF)
end

-- Hold is in units of 10ms and a frame is about a fiftieth of a second, so ten
-- units are five frames.  It rounds up, because a hold shorter than a frame
-- still has to cost one.
local function hold_frames(hold) return (hold + 1) // 2 end

-- Moves a pin and the pin wired to it where this is a loopback source.
local function aux_apply(n, p, state)
  local st = dev.aux[n][p]
  if state == 0x02 then
    st.driven = 0
    -- Nothing on the board pulls the net, so a released pin reads low.  A real
    -- installation would put a resistor on it and see the pull instead.
    st.level = 0
  else
    st.driven = 1
    st.level = state
  end
  local follower = (LOOPBACK[n] or {})[p]
  if follower then
    -- The follower takes the level off the wire.  It is an input, so the
    -- device is never driving it.
    dev.aux[n][follower].level = st.level
    dev.aux[n][follower].driven = 0
  end
end

-- Everything SET_AUX and its two terminal variants check before touching a
-- pin.  True where the request is good.
local function aux_ok(n, p, state, after, hold)
  local grp = AUX_GROUPS[n]
  if grp == nil or p >= grp.pins or not grp.drv[p] then return false end
  if state > 0x02 then return false end
  if hold ~= 0 and (after > 0x02 or hold > AUX_MAX_HOLD) then return false end
  return true
end

-- Hand the machine the image the device switched to.  Every read of the socket
-- comes from the Kickstart region, so writing the new image into it is the
-- switch.  It happens the moment the command says so, because the
-- bootloader reads the new image's reset vector a few instructions later.
local function do_switch(slot)
  dev.switched = slot
  dev.cmd_resp = false
  if not switch_img then return end
  local region = manager.machine.memory.regions[":kickstart"]
  for i = 0, #switch_img - 2, 2 do
    region:write_u16(i, (switch_img:byte(i + 1) << 8) | switch_img:byte(i + 2))
  end
end

local function execute()
  local g, c, a = dev.group, dev.cmd, dev.args
  if DEAF == string.format("%02X:%02X", g, c) then
    log("%02X/%02X ignored", g, c)
    return
  end
  if os.getenv("RBCP_REFUSE") == string.format("%02X:%02X", g, c) then
    log("%02X/%02X refused", g, c)
    answer(false)
    return
  end
  if g == 0xAA then
    dev.cmd_resp = false
    log("RESET")
    return
  end

  -- The intermittent device.  It is counted here, after the reset, because a
  -- reset is not a command the host is waiting on an answer to.
  commands = commands + 1
  if LOSE_EVERY > 0 and commands % LOSE_EVERY == 0 then
    lost = lost + 1
    log("%02X/%02X lost", g, c)
    return
  end
  if FAIL_EVERY > 0 and commands % FAIL_EVERY == 0 then
    failed = failed + 1
    log("%02X/%02X failed", g, c)
    answer(false)
    return
  end

  if g == 0x00 and c == 0x00 then                 -- NOP
    answer(true)
  elseif g == 0x00 and c == 0x01 then             -- ENTER_CMD_RESP
    dev.cmd_resp = true
    log("ENTER_CMD_RESP page=$%04X bch=$%06X size=%d", a[1] | (a[2] << 8),
        a[3] | (a[4] << 8) | (a[5] << 16), a[6] | (a[7] << 8))
    answer(true)
  elseif g == 0x00 and c == 0x04 then             -- SWITCH_AND_EXIT
    log("SWITCH_AND_EXIT ram slot %d", a[1])
    do_switch(a[1])
  elseif g == 0x00 and c == 0x05 then             -- LOAD_AND_EXIT
    log("LOAD_AND_EXIT ram %d <- flash %d (%s)", a[1], a[2], slots[a[2]] or "?")
    dev.active_ram = a[1]
    do_switch(a[1])
  elseif g == 0x01 and c == 0x00 then             -- GET_FLASH_SLOT_COUNT
    put_data(0, total_flash)
    answer(true)
  elseif g == 0x01 and c == 0x01 then             -- GET_FLASH_SLOT_INFO
    local n = a[1]
    put_data(0, ROM_TYPE)
    put_string(1, slots[n] or "")
    log("GET_FLASH_SLOT_INFO %d = %s", n, slots[n] or "<none>")
    answer(slots[n] ~= nil)
  elseif g == 0x01 and c == 0x02 then             -- GET_FLASH_SLOT_INFO_ALL
    -- Four bytes of preamble and then 32 bytes a slot, so the data section's
    -- size sets how many records fit.  A record that only partly fits is left
    -- out and flagged, as the spec requires and as a host reading the list has
    -- to cope with.  This region holds fifteen.
    local room = (BCH_SIZE - 8 - 4) // 32
    local whole = math.min(total_flash, room)
    put_data(0, total_flash)
    put_data(1, whole)
    put_data(2, (whole < total_flash) and 0x01 or 0x00)
    put_data(3, 0)
    for n = 0, whole - 1 do
      put_data(4 + n * 32, ROM_TYPE)
      put_string(4 + n * 32 + 1, slots[n] or "")
    end
    log("GET_FLASH_SLOT_INFO_ALL %d of %d%s", whole, total_flash,
        (whole < total_flash) and ", partial record flagged" or "")
    answer(true)
  elseif g == 0x01 and c == 0x03 then             -- GET_RAM_SLOT_INFO_ALL
    put_data(0, RAM_SLOTS)
    put_data(1, dev.active_ram)
    put_data(2, ROM_TYPE)
    put_data(3, 0)
    answer(true)
  elseif g == 0x01 and c == 0x04 then             -- GET_DEVICE_TYPE
    put_string(0, "One ROM")
    answer(true)
  elseif g == 0x01 and c == 0x05 then             -- GET_DEVICE_VERSION
    put_string(0, "v0.7.2")
    answer(true)
  elseif g == 0x01 and c == 0x06 then             -- GET_PROTOCOL_VERSION
    put_data(0, 0) put_data(1, 1) put_data(2, 2) put_data(3, 0)
    answer(true)
  elseif g == 0x02 and c == 0x02 then             -- LOAD_SLOT
    log("LOAD_SLOT ram %d <- flash %d (%s)", a[1], a[2], slots[a[2]] or "?")
    answer(slots[a[2]] ~= nil)
  elseif g == 0x03 and c == 0x00 then             -- GET_NV_CAPABILITY
    put_data(0, 16) put_data(1, 0) put_data(2, 1)
    -- With no spare RAM slot to stage in, the device stages within itself and
    -- keeps the first four bytes of NV storage.
    put_data(3, 0x02)
    answer(true)
  elseif g == 0x03 and c == 0x01 then             -- NV_PEEK
    put_data(0, dev.nv)
    log("NV_PEEK = %d", dev.nv)
    answer(true)
  elseif g == 0x03 and c == 0x06 then             -- NV_POKE_COMMIT_BYTE
    if os.getenv("RBCP_NV_FAIL") then
      log("NV_POKE_COMMIT_BYTE = %d, refused", a[1])
      answer(false)
      return
    end
    dev.nv = a[1]
    log("NV_POKE_COMMIT_BYTE = %d", a[1])
    answer(true)
  elseif g == 0x04 and c == 0x00 then             -- GET_PIPE_CAPABILITY
    put_data(0, 1)
    answer(true)
  elseif g == 0x04 and c == 0x01 then             -- GET_PIPE_INFO
    if a[1] ~= 0 then answer(false) return end
    put_data(0, 0)                                -- raw
    put_data(1, 0x03 | 0x04 | 0x08)               -- both ways, far end attached
    put_data(2, 0xFF)                             -- room to write
    put_data(3, rx_waiting())                     -- what RBCP_SEND has left
    put_data(4, 1)                                -- USB CDC
    answer(true)
  elseif g == 0x04 and c == 0x02 then             -- PIPE_WRITE
    local n, s = a[6], ""
    for i = 1, n do
      if a[i] ~= 13 then s = s .. string.char(a[i]) end
    end
    pipe_out(s)
    answer(true)
  elseif g == 0x04 and c == 0x03 then             -- PIPE_READ
    local want, pipe = a[1], a[2]
    if pipe ~= 0 then answer(false) return end
    if want == 0 then want = 256 end
    if want > PIPE_READ_ROOM then answer(false) return end
    local n = rx_waiting()
    if n > want then n = want end
    for i = 0, n - 1 do
      put_data(8 + i, rx_text:byte(rx_at + i))
    end
    rx_at = rx_at + n
    put_data(0, n & 0xFF)
    put_data(1, (n == want) and 0x02 or 0x00)     -- bit 0 is never set here
    put_data(2, rx_waiting())
    for i = 3, 7 do put_data(i, 0) end
    if n > 0 then
      io.write("[pipe<] " .. printable(rx_text:sub(rx_at - n, rx_at - 1)) .. "\n")
    end
    answer(true)
  elseif g == 0x05 and c == 0x00 then             -- GET_AUX_CAPABILITY
    put_data(0, aux_count)
    put_data(1, aux_count > 0 and AUX_MAX_HOLD or 0)
    for i = 2, 7 do put_data(i, 0) end
    answer(true)
  elseif g == 0x05 and c == 0x01 then             -- GET_AUX_GROUP_INFO
    local grp = AUX_GROUPS[a[1]]
    if grp == nil then answer(false) return end
    put_data(0, grp.type)
    put_data(1, grp.pins & 0xFF)                  -- zero would mean 256
    for i = 2, 7 do put_data(i, 0) end
    log("GET_AUX_GROUP_INFO %d = type $%02X, %d pins", a[1], grp.type, grp.pins)
    answer(true)
  elseif g == 0x05 and c == 0x02 then             -- GET_AUX_PIN_INFO
    local n, p = a[2], a[1]
    local grp = AUX_GROUPS[n]
    if grp == nil or p >= grp.pins then answer(false) return end
    put_data(0, 0x02 | (grp.drv[p] and 0x01 or 0x00))   -- readable, drivable
    put_data(1, grp.bus and bus_level(p) or dev.aux[n][p].level)
    put_data(2, dev.aux[n][p].driven)
    for i = 3, 7 do put_data(i, 0) end
    answer(true)
  elseif g == 0x05 and c == 0x03 then             -- SET_AUX
    local state, after, hold, p, n = a[1], a[2], a[3], a[4], a[5]
    if not aux_ok(n, p, state, after, hold) then answer(false) return end
    aux_apply(n, p, state)
    log("SET_AUX %d/%d %s hold %d", n, p, AUX_STATE[state], hold)
    if hold == 0 then answer(true) return end
    pending = { at = frames + hold_frames(hold),
                group = n, pin = p, after = after, g = g, c = c, ok = true }
  elseif g == 0x05 and c == 0x04 then             -- SET_AUX_AND_EXIT
    local state, after, hold, p, n = a[1], a[2], a[3], a[4], a[5]
    dev.cmd_resp = false
    if not aux_ok(n, p, state, after, hold) then
      log("SET_AUX_AND_EXIT refused %d/%d, exit stands", n, p)
      return
    end
    aux_apply(n, p, state)
    log("SET_AUX_AND_EXIT %d/%d %s hold %d", n, p, AUX_STATE[state], hold)
    if hold ~= 0 then
      pending = { at = frames + hold_frames(hold),
                  group = n, pin = p, after = after }
    end
  elseif g == 0x05 and c == 0x05 then             -- SET_AUX_SWITCH_EXIT
    local state, after, hold = a[1], a[2], a[3]
    local flags, p, n, slot = a[4], a[5], a[6], a[7]
    dev.cmd_resp = false
    -- A reserved flag bit or a slot of $AA costs the device both operations,
    -- and the exit happens anyway.
    if (flags & 0xFE) ~= 0 or slot == 0xAA or
       not aux_ok(n, p, state, after, hold) then
      log("SET_AUX_SWITCH_EXIT refused %d/%d slot %d, exit stands", n, p, slot)
      return
    end
    log("SET_AUX_SWITCH_EXIT %d/%d %s hold %d, ram slot %d %s", n, p,
        AUX_STATE[state], hold, slot,
        (flags & 1) == 0 and "after the pin" or "before the pin")
    if (flags & 1) == 0 then
      aux_apply(n, p, state)
      do_switch(slot)
    else
      do_switch(slot)
      aux_apply(n, p, state)
    end
    if hold ~= 0 then
      pending = { at = frames + hold_frames(hold),
                  group = n, pin = p, after = after }
    end
  elseif g == 0x06 and c == 0x00 then             -- GET_LED_CAPABILITY
    put_data(0, 2)                                -- two LEDs
    put_data(1, 100)                              -- max period
    put_data(2, 100)                              -- max hold
    answer(true)
  elseif g == 0x06 and c == 0x01 then             -- GET_LED_INFO
    local n = a[1]
    if LED_TYPE[n] == nil then answer(false) return end
    put_data(0, LED_TYPE[n])
    for i = 1, 15 do put_data(i, 0) end
    put_data(8, 0x3F)                             -- every defined mode
    -- A host asking in a loop would otherwise bury the rest of the log, and
    -- the same answer a second time says nothing the first did not.
    if last_led_info ~= n then
      last_led_info = n
      log("GET_LED_INFO %d = %s", n, LED_TYPE[n] == 1 and "RGB" or "monochrome")
    end
    answer(true)
  elseif g == 0x06 and c == 0x02 then             -- GET_LED_MODE_INFO
    put_data(0, 0) put_data(1, 0)
    answer(true)
  elseif g == 0x06 and c == 0x03 then             -- SET_LED
    local mode, r, gr, b, led = a[1], a[2], a[3], a[4], a[8]
    if LED_TYPE[led] == nil then answer(false) return end
    log("SET_LED %d %s rgb %02X%02X%02X", led, MODE_NAME[mode] or mode, r, gr, b)
    answer(true)
  else
    log("unknown command $%02X/$%02X", g, c)
    answer(false)
  end
end

local function byte_in(b)
  if dev.want > 0 then
    dev.args[#dev.args + 1] = b
    dev.want = dev.want - 1
    if dev.want == 0 then execute() end
    return
  end
  if dev.group == nil then
    if not dev.cmd_resp and not dev.knocked then
      if b == KNOCK[dev.knock_at + 1] then
        dev.knock_at = dev.knock_at + 1
        if dev.knock_at == #KNOCK then
          dev.knocked = true
          dev.knock_at = 0
          return                  -- GROUP is the byte after the knock, not
        end                       -- the last byte of it
      else
        dev.knock_at = (b == KNOCK[1]) and 1 or 0
      end
      if not dev.knocked and b ~= 0xAA then return end
    end
    dev.group = b
    return
  end
  dev.cmd = b
  dev.args = {}
  local n = (ARGS[dev.group] or {})[dev.cmd]
  if n == nil then
    dev.group, dev.cmd = nil, nil
    return
  end
  dev.want = n
  if n == 0 then execute() end
end

local function after_command()
  dev.group, dev.cmd, dev.want = nil, nil, 0
  if not dev.cmd_resp then dev.knocked = false end
end

-- The response byte, index 5, is the one a late answer holds back.  It shares
-- a word with the progress byte at index 4, so a word read at region offset 4
-- passes through here once for each.
local function bch_byte(i)
  if i == 5 and late_left > 0 then
    late_left = late_left - 1
    return late_val
  end
  if i == 4 and slow_left > 0 then
    slow_left = slow_left - 1
    return 0
  end
  return bch[i] or 0
end

local mem = manager.machine.devices[":maincpu"].spaces["program"]

-- The tap object has to be kept here too, or Lua collects it and the fill
-- never happens.  COLOR00 carries the boot progress colour, and COL_YELLOW is
-- written once.
if dirty_byte then
  dirty_tap = mem:install_write_tap(COLOR00, COLOR00 + 1, "dirty",
                                    function(offset, data, mask)
    if dirtied or data ~= COL_YELLOW then return data end
    dirtied = true
    for a = DIRTY_LOW, DIRTY_HIGH, 4 do
      mem:write_u32(a, (dirty_byte(a) << 24) | (dirty_byte(a + 1) << 16)
                     | (dirty_byte(a + 2) << 8) | dirty_byte(a + 3))
    end
    log("chip RAM $%06X-$%06X dirtied with %s", DIRTY_LOW, DIRTY_HIGH, DIRTY)
    return data
  end)
end

-- The tap object has to be kept.  Dropping the reference lets Lua collect it,
-- and the tap goes with it.
rbcp_tap = mem:install_read_tap(ROM_BASE, 0xFFFFFF, "rbcp", function(offset, data, mask)
  if dev.switched then return data end
  -- Every read here is a bus cycle the device saw, and the socket pins in
  -- group 3 report what was on the lines for it.
  dev.bus_addr = ((offset - ROM_BASE) >> 1) & 0x3FFFF
  dev.bus_data = data & 0xFFFF
  if dev.cmd_resp and offset >= BCH_ABS and offset < BCH_ABS + BCH_SPAN then
    local rel = offset - BCH_ABS
    -- The specification puts the even region offset on D0-D7, which on a
    -- big-endian 68K is the higher CPU address of the pair.  Answering the
    -- whole word covers both lanes with no branch on the mask.
    local word = (bch_byte(rel + 1) << 8) | bch_byte(rel)
    dev.bus_data = word
    return word
  end
  if offset < CMD_ABS then return data end
  local b = (offset - CMD_ABS) >> 1
  local finished = (dev.want == 1)
  if DEBUG then
    log("byte $%02X (group=%s cmd=%s want=%d)", b, tostring(dev.group),
        tostring(dev.cmd), dev.want)
  end
  byte_in(b)
  if finished or (dev.group ~= nil and dev.cmd ~= nil and dev.want == 0) then
    after_command()
  end
  return data
end)

-- A key or a mouse button, as RBCP_KEYS and RBCP_MOUSE name them.  set_value
-- is a sticky override that lasts until clear_value, so anything pressed here
-- has to be released by name or the tester waits for a release that never
-- comes.
local function press(field, on)
  if on then field:set_value(1) else field:clear_value() end
end

-- The legends on one key cap.  A field is named after the whole cap with two
-- spaces between the legends, so the S key is "s  S  ß §" and the 1 key is
-- "1  !  ¹".
local function legends(fname)
  local out = {}
  for one in (fname .. "  "):gmatch("(.-)  +") do
    if one ~= "" then out[#out + 1] = one end
  end
  return out
end

-- The input field a name asks for.  The whole name wins, then a legend on the
-- cap, so both "S" and "s" find the S key, and then the first field whose
-- name starts with what was asked.
local function find_field(name)
  local legend, prefix
  for _, port in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(port.fields) do
      if fname == name then return f end
      for _, one in ipairs(legends(fname)) do
        if one == name and legend == nil then legend = f end
      end
      if prefix == nil and fname:sub(1, #name) == name then prefix = f end
    end
  end
  return legend or prefix
end

local function need_field(name)
  local f = find_field(name)
  if f == nil then error("no input field named " .. name) end
  return f
end

-- "frame:Key;frame:Key", each naming a key on the emulated keyboard: a letter
-- such as L, Cursor Up, Cursor Down or Enter.  The key is held for six frames,
-- the way a finger holds it, so the keyboard MCU has time to scan it and send
-- it.  set_value is sticky, so every press here is released by name six frames
-- later or the machine sees it held for the rest of the run.
local keys = {}
for item in (os.getenv("RBCP_KEYS") or ""):gmatch("[^;]+") do
  local at, name = item:match("^(%d+):(.*)$")
  if not at then error("RBCP_KEYS items are frame:Key, e.g. 200:Cursor Down") end
  keys[#keys + 1] = { at = tonumber(at), name = name, field = need_field(name) }
end
local KEY_HOLD = 6

-- The mouse gestures the bootloader harness uses.  Nothing in this tester
-- reads them.
local MOUSE   = tonumber(os.getenv("RBCP_MOUSE") or "0")
local RCLICK  = tonumber(os.getenv("RBCP_RCLICK") or "0")
local CLICK_HOLD = 8
local LMB = (MOUSE > 0) and need_field("P1 Button 1") or nil
local RMB = (MOUSE > 0 or RCLICK > 0) and need_field("P1 Button 2") or nil

emu.register_frame_done(function()
  frames = frames + 1
  if pending and frames >= pending.at then
    aux_apply(pending.group, pending.pin, pending.after)
    if pending.ok then answer(true, pending.g, pending.c) end
    pending = nil
  end

  if MOUSE > 0 then
    if frames < MOUSE then
      press(LMB, true)
      press(RMB, true)
    elseif frames == MOUSE then
      press(LMB, false)
      press(RMB, false)
      log("mouse buttons released at frame %d", frames)
    end
  end
  if RCLICK > 0 then
    if frames >= RCLICK and frames < RCLICK + CLICK_HOLD then
      press(RMB, true)
    elseif frames == RCLICK + CLICK_HOLD then
      press(RMB, false)
      log("right click released at frame %d", frames)
    end
  end
  for _, k in ipairs(keys) do
    if frames == k.at then
      log("key '%s' at frame %d", k.name, frames)
      press(k.field, true)
    elseif frames == k.at + KEY_HOLD then
      press(k.field, false)
    end
  end

  if dev.switched then
    if switch_img then
      -- The image is already in the socket.  The tap belonged to the session
      -- that has just ended, and every Kickstart fetch would otherwise come
      -- through it.
      log("switched to ram slot %d, now serving %s", dev.switched, SWITCH_IMG)
      rbcp_tap:remove()
      rbcp_tap, switch_img = nil, nil
      dev.switched = nil
    else
      log("switched, and nothing to switch to — stopping at frame %d", frames)
      pipe_flush()
      summary()
      manager.machine:exit()
      return
    end
  end

  if frames >= RUN_FRAMES then
    if os.getenv("RBCP_SNAP") then manager.machine.video:snapshot() end
    pipe_flush()
    summary()
    manager.machine:exit()
  end
end)
