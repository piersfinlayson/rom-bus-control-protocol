-- rbcp_dev.lua — a fake RBCP device for MAME, watching the Apple II F8 socket.
--
-- Watches every read in $F800-$FFFF, decodes the RBCP command stream from the
-- addresses, and answers by substituting bytes on reads of the back-channel
-- region.  Enough of the protocol for the bootloader, and no more.

local ROM_BASE   = tonumber(os.getenv("RBCP_ROM_BASE") or "0xF800")
local CMD_PAGE   = 0xFE          -- must match rbcp_config.s
local BCH_BASE   = 0xFFB0
local BCH_SIZE   = 64
local COMPLETE   = 0xBB
local STATUS_OK  = 0xCC
local KNOCK      = { 0x21, 0x52, 0x42, 0x43, 0x50, 0x21 }

local NV_START   = tonumber(os.getenv("RBCP_NV") or "255")
local KEYS       = os.getenv("RBCP_KEYS") or ""     -- keys to feed, in order
local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "600")
local KEY_AT     = tonumber(os.getenv("RBCP_KEY_AT") or "150")   -- first key frame
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil
local SWITCH_IMG = os.getenv("RBCP_SWITCH_IMAGE")   -- served after the switch

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
}

-- Two LEDs, the second of them the RGB one, so that finding the lowest RGB
-- LED is actually exercised rather than assumed to be zero.
local LED_TYPE = { [0] = 0x00, [1] = 0x01 }
local MODE_NAME = { [0] = "off", "on", "blink", "breathe", "cycle", "beacon" }

local ARGS = {                   -- [group][cmd] = argument count
  [0x00] = { [0x01] = 9, [0x04] = 1 },
  [0x01] = { [0x00] = 0, [0x01] = 1, [0x03] = 0, [0x04] = 0, [0x05] = 0, [0x06] = 0 },
  [0x02] = { [0x02] = 2 },
  [0x03] = { [0x00] = 0, [0x01] = 3, [0x06] = 4 },
  [0x04] = { [0x00] = 0, [0x02] = 6 },
  [0x06] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 8 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

local function answer(ok)
  dev.token = (dev.token + 1) & 0xFFFF
  bch[0] = dev.group
  bch[1] = dev.cmd
  bch[2] = dev.token & 0xFF
  bch[3] = (dev.token >> 8) & 0xFF
  bch[4] = COMPLETE
  bch[5] = ok and STATUS_OK or ((~STATUS_OK) & 0xFF)
end

local function execute()
  local g, c, a = dev.group, dev.cmd, dev.args
  if g == 0xAA then
    dev.cmd_resp = false
    log("RESET")
    return
  end

  if g == 0x00 and c == 0x01 then                 -- ENTER_CMD_RESP
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
    put_data(0, 0x00)                             -- ROM type 2316
    put_string(1, slots[n] or "")
    log("GET_FLASH_SLOT_INFO %d = %s", n, slots[n] or "")
    answer(slots[n] ~= nil)
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
        end
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
    return bch[offset - BCH_BASE]
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
local frames = 0
local keys_at = 1
local held, held_until = nil, 0
emu.register_frame_done(function()
  frames = frames + 1
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
