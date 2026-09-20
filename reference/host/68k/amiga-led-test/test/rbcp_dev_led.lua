-- rbcp_dev_led.lua — a fake RBCP device with LEDs, for MAME, watching the
-- Amiga's Kickstart socket.
-- Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
--
-- Watches every read in the Kickstart window, decodes the RBCP command stream
-- from the addresses, and answers by substituting bytes on reads of the
-- back-channel region.  Enough of the protocol for the LED tester, and no
-- more.
--
-- The board it pretends to be.
--
--   * A board chosen by RBCP_LEDS, so a monochrome LED, an RGB one, a device
--     with neither and a device with more LEDs than the tester shows can all
--     be looked at.
--   * A device that answers SET_LED the way the protocol says it should, so
--     that the tester's read back line means something — and RBCP_LED_LIES,
--     which makes LED 0 report a brightness of its own whatever it is given,
--     so the screen that catches it can be seen too.
--   * GET_LED_MODE_INFO answering per mode, and refusing a mode
--     the LED does not have, as the specification requires.
--   * A mode given a non-zero hold runs for as long as it was given, after
--     which the device puts back what was in force when the command arrived.
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
local BCH_SPAN  = 512                   -- the CPU bytes they occupy
local COMPLETE  = 0xBB
local STATUS_OK = 0xCC
local KNOCK     = { 0x21, 0x52, 0x42, 0x43, 0x50, 0x21 }

local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "900")
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil

-- The board.  LED 0 is a monochrome green status LED with three modes, and
-- every LED after it is an RGB one with all six.  That is the shape a One ROM
-- has, and taking the first n of it gives a device with one LED, with none, or
-- with more than the tester's screen holds.
local LED_COUNT  = tonumber(os.getenv("RBCP_LEDS") or "2")
local MAX_PERIOD = tonumber(os.getenv("RBCP_MAX_PERIOD") or "100")
local MAX_HOLD   = tonumber(os.getenv("RBCP_MAX_HOLD") or "100")
-- Set to make the device fail every LED command, which is how a device whose
-- protocol version predates the group looks to a host.
local NO_LEDS    = os.getenv("RBCP_NO_LED_GROUP") ~= nil
-- Set to make LED 0 report a brightness of its own whatever it is given.
local LIES       = os.getenv("RBCP_LED_LIES") ~= nil

-- The colour the device picks when the host names none.  Any would do —
-- the point is that it is visibly not one the tester asked for.
local DEV_R, DEV_G, DEV_B = 0x75, 0xCE, 0xC8
local MODE_DEFAULT_PERIOD = 20          -- two seconds, in protocol units
local MODE_MIN_PERIOD     = 5           -- half a second is as short as it goes

local MODE_NAME = { [0] = "off", "on", "blink", "breathe", "cycle", "beacon" }
-- Which modes take a period.  Off and On never do, and the protocol leaves the
-- rest to the device.
local MODE_TAKES_PERIOD = { [0] = false, false, true, true, true, true }

-- Every LED's fixed properties and the state it powers on in.  A monochrome
-- LED's colour is its own.  An RGB one starts dark and is given a colour by
-- the first SET_LED.
local leds = {}
for n = 0, LED_COUNT - 1 do
  if n == 0 then
    leds[n] = { type = 0x00, modes = 0x07,
                mode = 0, r = 0x56, g = 0xAC, b = 0x4D,
                bright = 100, period = 0 }
  else
    leds[n] = { type = 0x01, modes = 0x3F,
                mode = 0, r = 0x00, g = 0x00, b = 0x00,
                bright = 100, period = 0 }
  end
end

-- The bounded mode the device is still timing, and the state it puts back when
-- the hold runs out.  Only one restore point is remembered, as the
-- specification requires.
local restore = nil
local frames = 0

-- Hold is in units of 100ms and a frame is a fiftieth of a second, so one unit
-- is five frames.
local function hold_frames(hold) return hold * 5 end

local dev = {
  cmd_resp = false,
  knock_at = 0,
  knocked  = false,
  group    = nil,
  cmd      = nil,
  args     = {},
  want     = 0,
  token    = 0,
}

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
-- application writes for itself.  It ends at the 256 KB every application is
-- built to fit in.
--
-- RBCP_DIRTY picks the byte.  "count" steps $FF down to $01 and starts again,
-- so no byte is 0 — the one value that hides this kind of fault — and
-- neighbouring bytes differ, so an unwritten word or long is junk too.  A hex
-- byte fills with that byte throughout, which narrows down a run that found
-- something.  "off" leaves chip RAM as MAME zeroes it.
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

local ARGS = {                          -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9 },
  [0x01] = { [0x04] = 0, [0x05] = 0, [0x06] = 0 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6, [0x03] = 2 },
  [0x06] = { [0x00] = 0, [0x01] = 1, [0x02] = 2, [0x03] = 8 },
  [0xAA] = { [0xAA] = 0 },
}

local commands = 0

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
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

local function pipe_flush()
  if tx_line ~= "" then pipe_out(tx_line .. "\n") end
end

-- The commands the device saw, printed as the run ends.  The tester draws to
-- a bitmap, so this is the only thing that says the session ran at all.
local function summary()
  if dirty_byte and not dirtied then
    log("chip RAM was never dirtied — rom_entry was not reached")
  end
  log("%d commands", commands)
  for n = 0, LED_COUNT - 1 do
    local l = leds[n]
    log("LED %d finished %s rgb %02X%02X%02X bri %d per %d", n,
        MODE_NAME[l.mode] or l.mode, l.r, l.g, l.b, l.bright, l.period)
  end
end

local function answer(ok, g, c)
  g, c = g or dev.group, c or dev.cmd
  dev.token = (dev.token + 1) & 0xFFFF
  bch[0] = g
  bch[1] = c
  bch[2] = dev.token & 0xFF
  bch[3] = (dev.token >> 8) & 0xFF
  bch[4] = COMPLETE
  bch[5] = ok and STATUS_OK or ((~STATUS_OK) & 0xFF)
end

-- Whether this LED has this mode.  The mode bitmap has a bit for modes 0 to 7
-- and no more, so a mode above seven is one the host issued without discovery
-- and the command fails.
local function has_mode(led, mode)
  if mode > 7 then return false end
  return (led.modes & (1 << mode)) ~= 0
end

local function mode_takes_period(led, mode)
  if MAX_PERIOD == 0 then return false end
  return MODE_TAKES_PERIOD[mode] == true
end

local function set_led(a)
  local mode, r, g, b = a[1], a[2], a[3], a[4]
  local bright, period, hold, n = a[5], a[6], a[7], a[8]
  local led = leds[n]
  if led == nil then return false end
  if not has_mode(led, mode) then return false end
  if bright > 100 then return false end
  if hold > MAX_HOLD then return false end
  if period ~= 0 then
    if not mode_takes_period(led, mode) then return false end
    if period < MODE_MIN_PERIOD or period > MAX_PERIOD then return false end
  end

  -- The LED's state when the command arrived, for a bounded mode to go back to.
  if hold ~= 0 and restore == nil then
    restore = { at = frames + hold_frames(hold), led = n,
                mode = led.mode, r = led.r, g = led.g, b = led.b,
                bright = led.bright, period = led.period }
  end

  led.mode = mode
  if led.type == 0x01 then              -- a monochrome LED's colour is its own
    if r == 0 and g == 0 and b == 0 then
      led.r, led.g, led.b = DEV_R, DEV_G, DEV_B
    else
      led.r, led.g, led.b = r, g, b
    end
  end
  if LIES and n == 0 then
    led.bright = 100                    -- whatever it was given
  elseif bright == 0 then
    led.bright = 100                    -- the device's own choice
  else
    led.bright = bright
  end
  if mode_takes_period(led, mode) then
    led.period = (period ~= 0) and period or MODE_DEFAULT_PERIOD
  else
    led.period = 0
  end

  log("SET_LED %d %s rgb %02X%02X%02X bri %d per %d hold %d", n,
      MODE_NAME[mode] or mode, led.r, led.g, led.b, led.bright, led.period,
      hold)
  return true
end

local function execute()
  local g, c, a = dev.group, dev.cmd, dev.args
  if g == 0xAA then
    dev.cmd_resp = false
    log("RESET")
    return
  end
  commands = commands + 1

  if g == 0x00 and c == 0x00 then                 -- NOP
    answer(true)
  elseif g == 0x00 and c == 0x01 then             -- ENTER_CMD_RESP
    dev.cmd_resp = true
    log("ENTER_CMD_RESP page=$%04X bch=$%06X size=%d", a[1] | (a[2] << 8),
        a[3] | (a[4] << 8) | (a[5] << 16), a[6] | (a[7] << 8))
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
  elseif g == 0x04 and c == 0x00 then             -- GET_PIPE_CAPABILITY
    put_data(0, 1)
    answer(true)
  elseif g == 0x04 and c == 0x01 then             -- GET_PIPE_INFO
    if a[1] ~= 0 then answer(false) return end
    put_data(0, 0)                                -- raw
    put_data(1, 0x03 | 0x04 | 0x08)               -- both ways, far end attached
    put_data(2, 0xFF)                             -- room to write
    put_data(3, 0)                                -- nothing waiting to be read
    put_data(4, 1)                                -- USB CDC
    answer(true)
  elseif g == 0x04 and c == 0x02 then             -- PIPE_WRITE
    local n, s = a[6], ""
    for i = 1, n do
      if a[i] ~= 13 then s = s .. string.char(a[i]) end
    end
    pipe_out(s)
    answer(true)
  elseif g == 0x06 and NO_LEDS then
    log("%02X/%02X refused, this device has no LED group", g, c)
    answer(false)
  elseif g == 0x06 and c == 0x00 then             -- GET_LED_CAPABILITY
    put_data(0, LED_COUNT)
    put_data(1, (LED_COUNT > 0) and MAX_PERIOD or 0)
    put_data(2, (LED_COUNT > 0) and MAX_HOLD or 0)
    for i = 3, 7 do put_data(i, 0) end
    log("GET_LED_CAPABILITY %d LEDs, max period %d, max hold %d",
        LED_COUNT, MAX_PERIOD, MAX_HOLD)
    answer(true)
  elseif g == 0x06 and c == 0x01 then             -- GET_LED_INFO
    local led = leds[a[1]]
    if led == nil then answer(false) return end
    put_data(0, led.type)
    put_data(1, led.mode)
    put_data(2, led.r)
    put_data(3, led.g)
    put_data(4, led.b)
    put_data(5, led.bright)
    put_data(6, led.period)
    put_data(7, 0)
    put_data(8, led.modes)
    for i = 9, 15 do put_data(i, 0) end
    answer(true)
  elseif g == 0x06 and c == 0x02 then             -- GET_LED_MODE_INFO
    local mode, led = a[1], leds[a[2]]
    if led == nil or not has_mode(led, mode) then answer(false) return end
    local takes = mode_takes_period(led, mode)
    put_data(0, takes and 0x01 or 0x00)
    put_data(1, takes and MODE_MIN_PERIOD or 0)
    for i = 2, 7 do put_data(i, 0) end
    log("GET_LED_MODE_INFO led %d %s takes period %s", a[2],
        MODE_NAME[mode] or mode, tostring(takes))
    answer(true)
  elseif g == 0x06 and c == 0x03 then             -- SET_LED
    answer(set_led(a))
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

-- The tap object has to be kept, or Lua collects it.  COLOR00 carries the boot
-- progress colour, and COL_YELLOW is written once.
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

-- The tap object has to be kept, or Lua collects it.
rbcp_tap = mem:install_read_tap(ROM_BASE, 0xFFFFFF, "rbcp", function(offset, data, mask)
  if dev.cmd_resp and offset >= BCH_ABS and offset < BCH_ABS + BCH_SPAN then
    local rel = offset - BCH_ABS
    -- The specification puts the even region offset on D0-D7, which on a
    -- big-endian 68K is the higher CPU address of the pair.  Answering the
    -- whole word covers both lanes with no branch on the mask.
    return ((bch[rel + 1] or 0) << 8) | (bch[rel] or 0)
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

-- A key, as RBCP_KEYS names it.  set_value is a sticky override that lasts
-- until clear_value, so anything pressed here has to be released by name or
-- the tester sees the key held down for the rest of the run.
local function press(field, on)
  if on then field:set_value(1) else field:clear_value() end
end

-- The legends on one key cap.  A field is named after the whole cap with two
-- spaces between the legends, so the M key is "m  M  º" and the 1 key is
-- "1  !  ¹".
local function legends(fname)
  local out = {}
  for one in (fname .. "  "):gmatch("(.-)  +") do
    if one ~= "" then out[#out + 1] = one end
  end
  return out
end

-- The input field a name asks for.  The whole name wins, then a legend on the
-- cap, so both "M" and "m" find the M key, and then the first field whose name
-- starts with the name given.
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

-- "frame:Key;frame:Key", each naming a key on the emulated keyboard.  The key
-- is held for six frames, the way a finger holds it, so the keyboard MCU has
-- time to scan it and send it.
local keys = {}
for item in (os.getenv("RBCP_KEYS") or ""):gmatch("[^;]+") do
  local at, name = item:match("^(%d+):(.*)$")
  if not at then error("RBCP_KEYS items are frame:Key, e.g. 200:Cursor Down") end
  keys[#keys + 1] = { at = tonumber(at), name = name, field = need_field(name) }
end
local KEY_HOLD = 6

emu.register_frame_done(function()
  frames = frames + 1

  -- A bounded mode that has run its time, put back the way it was.
  if restore and frames >= restore.at then
    local led = leds[restore.led]
    led.mode, led.r, led.g, led.b = restore.mode, restore.r, restore.g, restore.b
    led.bright, led.period = restore.bright, restore.period
    log("LED %d hold over, back to %s", restore.led,
        MODE_NAME[led.mode] or led.mode)
    restore = nil
  end

  for _, k in ipairs(keys) do
    if frames == k.at then
      log("key '%s' at frame %d", k.name, frames)
      press(k.field, true)
    elseif frames == k.at + KEY_HOLD then
      press(k.field, false)
    end
  end

  if frames >= RUN_FRAMES then
    if os.getenv("RBCP_SNAP") then manager.machine.video:snapshot() end
    pipe_flush()
    summary()
    manager.machine:exit()
  end
end)
