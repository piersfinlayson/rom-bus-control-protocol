-- rbcp_dev.lua — a fake RBCP device for MAME, watching the Apple II F8 socket.
--
-- Watches every read in $F800-$FFFF, decodes the RBCP command stream from the
-- addresses, and answers by substituting bytes on reads of the back-channel
-- region.  Enough of the protocol for the bootloader, and no more.

local ROM_BASE   = tonumber(os.getenv("RBCP_ROM_BASE") or "0xF800")
local CMD_PAGE   = 0xFE          -- must match rbcp_config.s
-- The back channel differs between the programs tested here.  The bootloader,
-- the terminal and the meter put 64 bytes under the vectors.  The auxiliary
-- I/O tester needs room for a flash slot list, whose records are 32 bytes
-- each, and puts 512 bytes lower down.
local BCH_BASE   = tonumber(os.getenv("RBCP_BCH_BASE") or "0xFFB0")
local BCH_SIZE   = tonumber(os.getenv("RBCP_BCH_SIZE") or "64")
local COMPLETE   = 0xBB
local STATUS_OK  = 0xCC
local KNOCK      = { 0x21, 0x52, 0x42, 0x43, 0x50, 0x21 }

local NV_START   = tonumber(os.getenv("RBCP_NV") or "255")
local KEYS       = os.getenv("RBCP_KEYS") or ""     -- keys to feed, in order
local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "600")
local KEY_AT     = tonumber(os.getenv("RBCP_KEY_AT") or "150")   -- first key frame
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil
-- "01:06" makes the device ignore GET_PROTOCOL_VERSION entirely, as a device
-- too busy to answer in time looks from the host's side.
local DEAF       = os.getenv("RBCP_DEAF")
-- "00:01:5" makes the device answer the response byte with what it held
-- before the command for five reads after it has said the command is
-- complete, which is a device publishing the two out of order.
local LATE       = os.getenv("RBCP_LATE_RSP")
local SWITCH_IMG = os.getenv("RBCP_SWITCH_IMAGE")   -- served after the switch
-- Set to make the device expose no auxiliary pins at all, which is a legal
-- device and the one that sends a host down its no-pins path.
local NO_AUX     = os.getenv("RBCP_NO_AUX") ~= nil

-- Names a real device might carry, one of them mixed case, since a name is
-- drawn as the device gives it and inverse video treats the two cases
-- differently.  The dead test one is thirty characters, the most that fits.
local slots = {
  [0] = "Apple II RBCP Bootloader",
  [1] = "Apple IIe Stock ROM",
  [2] = "Adrian's Apple ][ Deadtest ROM",
  [3] = "APPLE II MONITOR",
  [4] = "Applesoft Lite",
}
for n = 5, tonumber(os.getenv("RBCP_SLOTS") or "5") - 1 do
  slots[n] = string.format("SPARE IMAGE %d", n)
end

-- The ROM type every slot reports.  A host offering a choice of image only
-- offers slots of the type it is being served, so this has to follow the
-- socket, and it has to be what a One ROM says rather than what the machine
-- originally held.  Both sockets take 24 pin mask ROMs and the boards that
-- serve them are 28 pin parts: a 2716 for the II's 2KB F8, a 2764 for the
-- IIe's 8KB EF.
local ROM_TYPE = (ROM_BASE == 0xF800) and 0x08 or 0x0A
local total_flash = tonumber(os.getenv("RBCP_SLOTS") or "5")

-- What the device serves once it has switched slots.  Without one the
-- bootloader is still what is in the socket after the switch, and the machine
-- boots it again.
local switch_img = nil
if SWITCH_IMG then
  local f = io.open(SWITCH_IMG, "rb")
  if f then switch_img = f:read("a") f:close() end
end

local bch = {}                   -- back-channel bytes, index 0..BCH_SIZE-1
for i = 0, BCH_SIZE - 1 do bch[i] = 0 end

-- Which command holds its response back, for how many reads, and what those
-- reads answer while it does.
local late_g, late_c, late_n
if LATE then
  local g, c, n = LATE:match("^(%x%x):(%x%x):(%d+)$")
  if not g then error("RBCP_LATE_RSP must be GG:CC:reads, e.g. 00:01:5") end
  late_g, late_c, late_n = tonumber(g, 16), tonumber(c, 16), tonumber(n)
end
local late_left, late_val = 0, 0

-- The auxiliary pins the device pretends to have.  Three groups, so a host
-- that assumed one is caught: GPIO with only the even pins from 2 upwards
-- drivable, an image-select group with nothing drivable in it at all, and a
-- pair of pads.
--
-- Pads 0 and 1 — group 2 — are the loopback pair, wired together so that
-- driving pad 0 moves pad 1, which is a board a host can be shown reading a
-- pin it did not drive.
local AUX_GROUPS = {
  [0] = { type = 0x01, pins = 10, drv = { [2] = true, [4] = true, [6] = true,
                                          [8] = true } },
  [1] = { type = 0x80, pins = 4,  drv = {} },
  [2] = { type = 0x81, pins = 2,  drv = { [0] = true } },
}
local LOOPBACK    = { [2] = { [0] = 1 } }   -- group, then source pin, follower
local AUX_MAX_HOLD = 255                    -- 2.55 seconds, in units of 10ms
local AUX_STATE   = { [0] = "low", "high", "released" }

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
  knock_at = 0,                  -- how much of the knock has matched
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
}

-- The frame counter, and the hold the device is still timing.  A SET_AUX with
-- a non-zero hold does not complete until the hold has elapsed, so its answer
-- waits here instead of going out with the command — which is the only thing
-- that makes the host's auxiliary poll timeout mean anything.  Both are
-- declared up here because execute() and the frame loop below both touch
-- them.
local frames = 0
local pending = nil

-- Two LEDs, the second of them the RGB one, so that finding the lowest RGB
-- LED is actually exercised rather than assumed to be zero.
local LED_TYPE = { [0] = 0x00, [1] = 0x01 }
local MODE_NAME = { [0] = "off", "on", "blink", "breathe", "cycle", "beacon" }

local ARGS = {                   -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9, [0x04] = 1 },
  [0x01] = { [0x00] = 0, [0x01] = 1, [0x02] = 0, [0x03] = 0, [0x04] = 0, [0x05] = 0,
             [0x06] = 0 },
  [0x02] = { [0x02] = 2 },
  [0x03] = { [0x00] = 0, [0x01] = 3, [0x06] = 4 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6 },
  [0x05] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 5, [0x04] = 5, [0x05] = 7 },
  [0x06] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 8 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

-- The group and command default to the one in hand.  A deferred hold names
-- them, since by the time it answers the device has long since finished
-- reading the command that asked for it.
local function answer(ok, g, c)
  g, c = g or dev.group, c or dev.cmd
  dev.token = (dev.token + 1) & 0xFFFF
  bch[0] = g
  bch[1] = c
  bch[2] = dev.token & 0xFF
  bch[3] = (dev.token >> 8) & 0xFF
  bch[4] = COMPLETE
  if late_g and g == late_g and c == late_c then
    late_left, late_val = late_n, bch[5]
    log("%02X/%02X response held back for %d reads", late_g, late_c, late_n)
  end
  bch[5] = ok and STATUS_OK or ((~STATUS_OK) & 0xFF)
end

-- Hold is in units of 10ms and a frame is about a sixtieth of a second, so ten
-- units are six frames.  Rounded up, since a hold shorter than a frame still
-- has to cost one.
local function hold_frames(hold) return (hold * 3 + 4) // 5 end

-- Moves a pin, and the pin wired to it where this is a loopback source.
local function aux_apply(n, p, state)
  local st = dev.aux[n][p]
  if state == 0x02 then
    st.driven = 0
    -- Released, and nothing on the board pulls the net, so it reads low.  A
    -- real installation would put a resistor on it and see the pull instead.
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

  if g == 0x00 and c == 0x00 then                 -- NOP
    answer(true)
  elseif g == 0x00 and c == 0x01 then             -- ENTER_CMD_RESP
    dev.cmd_resp = true
    log("ENTER_CMD_RESP page=$%02X bch=$%04X size=%d", a[1], a[3] | (a[4] << 8),
        a[6] | (a[7] << 8))
    answer(true)
  elseif g == 0x00 and c == 0x04 then             -- SWITCH_AND_EXIT
    dev.switched = a[1]
    dev.cmd_resp = false
    log("SWITCH_AND_EXIT ram slot %d", a[1])
  elseif g == 0x01 and c == 0x00 then             -- GET_FLASH_SLOT_COUNT
    put_data(0, total_flash)
    answer(true)
  elseif g == 0x01 and c == 0x01 then             -- GET_FLASH_SLOT_INFO
    local n = a[1]
    put_data(0, ROM_TYPE)
    put_string(1, slots[n] or "")
    log("GET_FLASH_SLOT_INFO %d = %s", n, slots[n] or "")
    answer(slots[n] ~= nil)
  elseif g == 0x01 and c == 0x02 then             -- GET_FLASH_SLOT_INFO_ALL
    -- Four bytes of preamble and then 32 bytes a slot, so how many fit is
    -- what the data section has room for.  A record that only partly fits is
    -- left out and flagged, which is what the spec asks for and what a host
    -- reading the list has to cope with.
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
    log("GET_FLASH_SLOT_INFO_ALL %d of %d", whole, total_flash)
    answer(true)
  elseif g == 0x01 and c == 0x03 then             -- GET_RAM_SLOT_INFO_ALL
    put_data(0, 2)
    put_data(1, dev.active_ram)
    put_data(2, 0x00)
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
    put_data(3, 0)                                -- nothing waiting
    put_data(4, 1)                                -- USB CDC
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
    put_data(1, dev.aux[n][p].level)
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
      dev.switched = slot
    else
      dev.switched = slot
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
    log("GET_LED_INFO %d = %s", n, LED_TYPE[n] == 1 and "RGB" or "monochrome")
    answer(true)
  elseif g == 0x06 and c == 0x02 then             -- GET_LED_MODE_INFO
    put_data(0, 0) put_data(1, 0)
    answer(true)
  elseif g == 0x06 and c == 0x03 then             -- SET_LED
    local mode, r, gr, b, led = a[1], a[2], a[3], a[4], a[8]
    if LED_TYPE[led] == nil then answer(false) return end
    log("SET_LED %d %s rgb %02X%02X%02X", led, MODE_NAME[mode] or mode, r, gr, b)
    answer(true)
  elseif g == 0x04 and c == 0x02 then             -- PIPE_WRITE
    local n, s = a[6], ""
    for i = 1, n do
      local ch = a[i]
      s = s .. ((ch >= 32 and ch < 127) and string.char(ch) or
                (ch == 13 and "" or (ch == 10 and "\\n" or ".")))
    end
    io.write("[pipe] " .. s .. "\n")
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

local mem = manager.machine.devices[":maincpu"].spaces["program"]

-- The tap object has to be kept: dropping the reference lets Lua collect it,
-- and the tap goes with it.
rbcp_tap = mem:install_read_tap(ROM_BASE, 0xFFFF, "rbcp", function(offset, data, mask)
  if dev.switched then
    if switch_img then return switch_img:byte(offset - ROM_BASE + 1) end
    return data
  end
  if dev.cmd_resp and offset >= BCH_BASE and offset < BCH_BASE + BCH_SIZE then
    local i = offset - BCH_BASE
    if i == 5 and late_left > 0 then
      late_left = late_left - 1
      return late_val
    end
    return bch[i]
  end
  if dev.cmd_resp and (offset >> 8) ~= CMD_PAGE then return data end
  local finished = (dev.want == 1)
  if DEBUG then
    log("byte $%02X (group=%s cmd=%s want=%d)", offset & 0xFF,
        tostring(dev.group), tostring(dev.cmd), dev.want)
  end
  byte_in(offset & 0xFF)
  if finished or (dev.group ~= nil and dev.cmd ~= nil and dev.want == 0) then
    after_command()
  end
  return data
end)

-- Feed keys and stop when the machine has said what it is going to say.
local function split_keys(str)
  local out, i = {}, 1
  while i <= #str do
    if str:sub(i, i) == "{" then
      local j = str:find("}", i)
      out[#out + 1] = str:sub(i, j)
      i = j + 1
    else
      out[#out + 1] = str:sub(i, i)
      i = i + 1
    end
  end
  return out
end

local keys = split_keys(KEYS)
local keys_at = 1
local held, held_until = nil, 0
emu.register_frame_done(function()
  frames = frames + 1
  if pending and frames >= pending.at then
    aux_apply(pending.group, pending.pin, pending.after)
    if pending.ok then answer(true, pending.g, pending.c) end
    pending = nil
  end
  if held and frames >= held_until then
    held:set_value(0)
    held = nil
  end
  if dev.switched and not switch_img then
    log("switched, stopping")
    manager.machine:exit()
    return
  end
  if frames > KEY_AT and frames % 20 == 0 and keys_at <= #keys then
    local k = keys[keys_at]
    if k:sub(1, 1) == "{" then
      -- A named key, held for a few frames the way a finger would.
      local name = k:sub(2, -2)
      for tag, port in pairs(manager.machine.ioport.ports) do
        if port.fields[name] then
          held = port.fields[name]
          held:set_value(1)
          held_until = frames + 3
        end
      end
    else
      manager.machine.natkeyboard:post(k)
    end
    keys_at = keys_at + 1
  end
  if frames >= RUN_FRAMES then
    if os.getenv("RBCP_SNAP") then manager.machine.video:snapshot() end
    -- The text screen, one line per row.  A row drawn in inverse video is
    -- marked with a *, since the characters themselves now carry case.
    for r = 0, 23 do
      local base = 0x400 + (r % 8) * 0x80 + (r // 8) * 0x28
      local s, inverse = "", false
      for c = 0, 39 do
        local b = mem:read_u8(base + c)
        if b < 0x80 then inverse = true end
        local ch = b & 0x7F
        if ch < 0x20 then ch = ch + 0x40 end          -- inverse upper case
        if b >= 0x60 and b < 0x80 then ch = b end     -- inverse lower case
        s = s .. string.char(ch)
      end
      print(string.format("%02d%s|%s|", r, inverse and "*" or " ", s))
    end
    manager.machine:exit()
  end
end)
