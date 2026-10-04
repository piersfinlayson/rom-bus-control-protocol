-- rbcp_dev_cbm.lua — a fake RBCP device for MAME on a C64 or VIC-20 ROM
-- socket.  It also presses keys and prints the screen as text.
--
-- Commands are decoded from the addresses of reads in the socket's window.
-- Responses are substituted into reads of the back-channel region.  Only the
-- commands the programs here use are implemented.
--
-- Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>

-- A soft reset re-runs this script but the taps and callbacks it installed
-- survive, so a second run must install nothing.
_G.RBCP_GEN = (_G.RBCP_GEN or 0) + 1
if _G.RBCP_GEN > 1 then
  print(string.format("[dev] re-entered after reset, generation %d", _G.RBCP_GEN))
  return
end

local ROM_BASE   = tonumber(os.getenv("RBCP_ROM_BASE") or "0xE000")
local CMD_PAGE   = tonumber(os.getenv("RBCP_CMD_PAGE") or "0xE0")
-- The back channel's address and size must match the program's rbcp_config.s.
local BCH_BASE   = tonumber(os.getenv("RBCP_BCH_BASE") or "0xE100")
local BCH_SIZE   = tonumber(os.getenv("RBCP_BCH_SIZE") or "512")
local ROM_SIZE   = tonumber(os.getenv("RBCP_ROM_SIZE") or "0x2000")
local COMPLETE   = 0xBB
local STATUS_OK  = 0xCC
local KNOCK      = { 0x21, 0x52, 0x42, 0x43, 0x50, 0x21 }

local NV_START   = tonumber(os.getenv("RBCP_NV") or "255")
local KEYS       = os.getenv("RBCP_KEYS") or ""
local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "600")
local KEY_AT     = tonumber(os.getenv("RBCP_KEY_AT") or "150")   -- first key frame
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil
-- "GG:CC" leaves that command unanswered, like a device too slow to reply.
local DEAF       = os.getenv("RBCP_DEAF")
-- "GG:CC:N" returns that command's previous response byte for N reads after
-- COMPLETE is set, like a device publishing the two out of order.
local LATE       = os.getenv("RBCP_LATE_RSP")
local SWITCH_IMG = os.getenv("RBCP_SWITCH_IMAGE")
-- Set for a device without auxiliary pins, which the spec allows.
local NO_AUX     = os.getenv("RBCP_NO_AUX") ~= nil

-- Slot names are mostly mixed case because a host draws a name as the device
-- reports it and inverse video handles the two cases differently.
local slots = {
  [0] = "CBM RBCP Bootloader",
  [1] = "Commodore Stock Kernal",
  [2] = "JiffyDOS 6.01",
  [3] = "SD2IEC KERNAL",
  [4] = "Dead Test Kernal",
}
for n = 5, tonumber(os.getenv("RBCP_SLOTS") or "5") - 1 do
  slots[n] = string.format("SPARE IMAGE %d", n)
end

-- Every slot reports the socket's ROM type because a host lists only slots of
-- the type it runs from.  A 2364 is type 2 and a C64C's 23128 is type 3.
local ROM_TYPE = tonumber(os.getenv("RBCP_ROM_TYPE") or "2")
local total_flash = tonumber(os.getenv("RBCP_SLOTS") or "5")

-- Image served after a slot switch.  Without one the run stops there.
local switch_img = nil
if SWITCH_IMG then
  local f = io.open(SWITCH_IMG, "rb")
  if f then switch_img = f:read("a") f:close() end
end

local bch = {}
for i = 0, BCH_SIZE - 1 do bch[i] = 0 end

local late_g, late_c, late_n
if LATE then
  local g, c, n = LATE:match("^(%x%x):(%x%x):(%d+)$")
  if not g then error("RBCP_LATE_RSP must be GG:CC:reads, for example 00:01:5") end
  late_g, late_c, late_n = tonumber(g, 16), tonumber(c, 16), tonumber(n)
end
local late_left, late_val = 0, 0

-- Three groups, so a host written for one fails.  The loopback pair lets a
-- host read a pin it does not drive.
local AUX_GROUPS = {
  [0] = { type = 0x01, pins = 10, drv = { [2] = true, [4] = true, [6] = true,
                                          [8] = true } },
  [1] = { type = 0x80, pins = 4,  drv = {} },
  [2] = { type = 0x81, pins = 2,  drv = { [0] = true } },
}
local LOOPBACK    = { [2] = { [0] = 1 } }   -- group, then source pin, follower
local AUX_MAX_HOLD = 255                    -- units of 10ms
local AUX_STATE   = { [0] = "low", "high", "released" }

if NO_AUX then AUX_GROUPS, LOOPBACK = {}, {} end

local aux_count = 0
for _ in pairs(AUX_GROUPS) do aux_count = aux_count + 1 end

-- Pin state survives RBCP_RESET and the end of a session, so only a device
-- reset clears it.
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
  knock_at = 0,                  -- knock bytes matched so far
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

-- A SET_AUX with a non-zero hold doesn't complete until the hold ends, so its
-- answer waits in pending.  Otherwise the host's auxiliary poll timeout is
-- never tested.
local frames = 0
local pending = nil

-- The RGB LED is second, so a host hard-coded to LED 0 fails.
local LED_TYPE = { [0] = 0x00, [1] = 0x01 }
local MODE_NAME = { [0] = "off", "on", "blink", "breathe", "cycle", "beacon" }

local ARGS = {                   -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9, [0x04] = 1 },
  [0x01] = { [0x00] = 0, [0x01] = 1, [0x02] = 0, [0x03] = 0, [0x04] = 0, [0x05] = 0,
             [0x06] = 0 },
  [0x02] = { [0x02] = 2 },
  [0x03] = { [0x00] = 0, [0x01] = 3, [0x06] = 4 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6, [0x03] = 2 },
  [0x05] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 5, [0x04] = 5, [0x05] = 7 },
  [0x06] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 8 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

-- Text the pipe's far end sends to the machine.  "\n" in RBCP_SEND is a line
-- feed because that ends a line on a real pipe.
local rx_text = (os.getenv("RBCP_SEND") or ""):gsub("\\n", "\n")
local rx_at = 1

-- Back channel less the response header and PIPE_READ's own eight bytes.
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

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

-- PIPE_WRITE moves at most four bytes, so a line is buffered to its line feed.
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

-- Prints a last line without a line feed, so a final error is still seen.
local function pipe_flush()
  if tx_line ~= "" then pipe_out(tx_line .. "\n") end
end

-- For a fault where continuing would let the run pass.
local function fatal(fmt, ...)
  io.write(string.format("[dev] fatal: " .. fmt .. "\n", ...))
  io.flush()
  manager.machine:exit()
end

-- A deferred hold passes g and c because dev.group and dev.cmd are cleared by
-- the time it completes.
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

-- 10ms units to 60Hz frames, rounded up.  On the default 50Hz PAL VIC-20 a
-- hold runs a fifth longer.
local function hold_frames(hold) return (hold * 3 + 4) // 5 end

-- Sets a pin and any loopback follower.
local function aux_apply(n, p, state)
  local st = dev.aux[n][p]
  if state == 0x02 then
    st.driven = 0
    -- Nothing on the board pulls the net, so a released pin reads low.
    st.level = 0
  else
    st.driven = 1
    st.level = state
  end
  local follower = (LOOPBACK[n] or {})[p]
  if follower then
    -- The follower is an input, so never driven.
    dev.aux[n][follower].level = st.level
    dev.aux[n][follower].driven = 0
  end
end

-- Shared by SET_AUX and its two exit variants.
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
    -- Four-byte preamble then 32 bytes a slot.  A record that only partly
    -- fits is left out and flagged, as the spec requires.
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
    put_data(3, rx_waiting())
    put_data(4, 1)                                -- USB CDC
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
    -- A reserved flag bit or slot $AA cancels both operations, not the exit.
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
      if a[i] ~= 13 then s = s .. string.char(a[i]) end
    end
    pipe_out(s)
    answer(true)
  else
    log("unknown command $%02X/$%02X", g, c)
    answer(false)
  end
end

-- One command byte, from the low byte of a command page address.  Outside
-- command-response mode a command must follow the knock, except group $AA, so
-- a reset always works.
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
          return                  -- GROUP is the byte after the knock
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

-- Everything below drives the machine rather than the device.

local CPU        = os.getenv("RBCP_CPU") or ":u7"
local SCREEN     = tonumber(os.getenv("RBCP_SCREEN") or "0x0400")
local COLS       = tonumber(os.getenv("RBCP_COLS") or "40")
local ROWS       = tonumber(os.getenv("RBCP_ROWS") or "25")
local HOLD       = os.getenv("RBCP_HOLD") or ""
local HOLD_UNTIL = tonumber(os.getenv("RBCP_HOLD_UNTIL") or "0")
-- In frames.  The bootloaders' scan loops miss a key that isn't preceded by a
-- clear release.
local KEY_HOLD   = tonumber(os.getenv("RBCP_KEY_HOLD") or "8")
local KEY_GAP    = tonumber(os.getenv("RBCP_KEY_GAP") or "30")

local mem = manager.machine.devices[CPU].spaces["program"]

-- The image is written to MAME's :kernal region so the machine's banking
-- still applies.  The BASIC arms don't set a switch image, because :kernal
-- isn't their socket.
local function serve_switched()
  local region = manager.machine.memory.regions[":kernal"]
  if not (region and switch_img) then return false end
  local n = math.min(#switch_img, region.size)
  for i = 0, n - 1 do region:write_u8(i, switch_img:byte(i + 1)) end
  log("served %d bytes into :kernal", n)
  return true
end

local handed_over, served = false, false

-- A global, because the tap is removed when Lua collects the object.
rbcp_tap = mem:install_read_tap(ROM_BASE, ROM_BASE + ROM_SIZE - 1, "rbcp",
                                function(offset, data, mask)
  if dev.switched then
    -- The host jumps through the new reset vector at once, so the swap can't
    -- wait for a frame.  MAME read this access's byte before the tap ran, so
    -- it is answered from the new image here.
    if not handed_over then
      handed_over = true
      served = serve_switched()
      if served then return switch_img:byte(offset - ROM_BASE + 1) end
    end
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

-- vic1210.cpp in MAME 0.264 and 0.289 masks the address with $BFF where the
-- cartridge decodes $FFF, so $0C00-$0FFF mirrors $0800-$0BFF.  A program
-- loaded across both overwrites itself.  These taps keep the two apart.
if os.getenv("RBCP_EXP") == "3k" then
  local ram = {}
  vic_3k_w = mem:install_write_tap(0x0800, 0x0FFF, "vic3k",
                                   function(offset, data, mask)
    ram[offset] = data & 0xFF
    return data
  end)
  vic_3k_r = mem:install_read_tap(0x0800, 0x0FFF, "vic3k",
                                  function(offset, data, mask)
    return ram[offset] or data
  end)
  log("holding $0800-$0BFF and $0C00-$0FFF apart, which the VIC-1210 does not")
end

-- A key is identified by its MAME legend and searched for in every port
-- because its row differs between the C64 and VIC-20.  Legends change between
-- MAME releases, so a name may list alternatives separated by "|".  The C64
-- cursor key is "Crsr Down Up" in 0.264 and arrow glyphs in 0.289.
local function find_field(name)
  for alt in name:gmatch("[^|]+") do
    for _, port in pairs(manager.machine.ioport.ports) do
      if port.fields[alt] then return port.fields[alt], alt end
    end
  end
  return nil
end

-- Returns the fields, or nil and the first name missing from this MAME.  Keys
-- are resolved before the run because a missing key presses nothing and the
-- default menu path can still pass.
local function resolve(names)
  local out = {}
  for name in names:gmatch("[^;]+") do
    local f, alt = find_field(name)
    if f == nil then return nil, name end
    out[#out + 1] = { field = f, name = alt }
  end
  return out
end

-- Setting a field once doesn't hold a key because MAME clears it at each
-- frame's input poll.  register_periodic runs many times a frame.
local released = false
local holding, bad = resolve(HOLD)
local keys
if holding then keys, bad = resolve(KEYS) end
if bad then
  fatal("this MAME doesn't have a key called %s", bad)
  return
end
for _, k in ipairs(holding) do log("holding %s", k.name) end
if #holding > 0 then
  emu.register_periodic(function()
    if released then return end
    for _, k in ipairs(holding) do k.field:set_value(1) end
  end)
end

-- Screen codes, not PETSCII.  Bit 7 is reverse video and $40 up is graphics.
local function screen_char(b)
  local c = b & 0x7F
  if c < 0x20 then return string.char(c + 0x40) end
  if c < 0x40 then return string.char(c) end
  return "."
end

local keys_at = 1
local pressed, press_until = nil, 0

emu.register_frame_done(function()
  frames = frames + 1
  if pending and frames >= pending.at then
    aux_apply(pending.group, pending.pin, pending.after)
    if pending.ok then answer(true, pending.g, pending.c) end
    pending = nil
  end
  -- The bootloaders read the matrix just after reset, before this script ran,
  -- so the machine is reset again with the keys held.
  if frames == 1 and #holding > 0 then
    log("resetting with the keys held")
    manager.machine:soft_reset()
  end
  if HOLD_UNTIL > 0 and frames == HOLD_UNTIL and not released then
    released = true
    for _, k in ipairs(holding) do k.field:set_value(0) end
    log("released %d held keys at frame %d", #holding, frames)
  end
  if pressed and frames >= press_until then
    pressed:set_value(0)
    pressed = nil
  end
  if handed_over and not served then
    log("switched, and nothing to switch to — stopping at frame %d", frames)
    pipe_flush()
    manager.machine:exit()
    return
  end
  if not pressed and frames >= KEY_AT and frames % KEY_GAP == 0 and keys_at <= #keys then
    local k = keys[keys_at]
    pressed = k.field
    k.field:set_value(1)
    press_until = frames + KEY_HOLD
    log("key %s", k.name)
    keys_at = keys_at + 1
  end
  if frames >= RUN_FRAMES then
    pipe_flush()
    if os.getenv("RBCP_SNAP") then manager.machine.video:snapshot() end
    for r = 0, ROWS - 1 do
      local s, inverse = "", false
      for c = 0, COLS - 1 do
        local b = mem:read_u8(SCREEN + r * COLS + c)
        if b >= 0x80 then inverse = true end
        s = s .. screen_char(b)
      end
      print(string.format("%02d%s|%s|", r, inverse and "*" or " ", s))
    end
    manager.machine:exit()
  end
end)
