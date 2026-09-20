-- rbcp_dev_pipe.lua — a fake RBCP device for MAME with a pipe worth measuring.
-- Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
--
-- Watches every read in the Kickstart window, decodes the RBCP command stream
-- from the addresses, and answers by substituting bytes on reads of the
-- back-channel region.  Enough of the protocol for the pipe throughput test,
-- and no more.
--
-- It is ../../amiga-boot/test/rbcp_dev_amiga.lua with the pipe counted rather
-- than printed, checked as it arrives, and given a size and a drain rate.
-- README.md in this directory says why.
--
-- It reports bits per second over emulated seconds.  The tester works its own
-- figure out from the CIA-B counter, so the two standing together confirm the
-- one-second window is a second.
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
local ECHO       = os.getenv("RBCP_ECHO") ~= nil

-- The pipe's own size and how fast the far end takes bytes off it, in bytes a
-- frame.  Nought is a far end that keeps up with anything, which is the
-- default because a throughput run wants no ceiling but its own.
local PIPE_CAP   = 255
local DRAIN      = tonumber(os.getenv("RBCP_DRAIN") or "0")

-- A device that goes wrong now and then.  One command in FAIL_EVERY is
-- answered with failure and one in LOSE_EVERY is not answered at all.
local FAIL_EVERY = tonumber(os.getenv("RBCP_FAIL_EVERY") or "0")
local LOSE_EVERY = tonumber(os.getenv("RBCP_LOSE_EVERY") or "0")
local commands, failed, lost = 0, 0, 0

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

local dev = {
  cmd_resp = false,
  knock_at = 0,
  knocked  = false,
  group    = nil,
  cmd      = nil,
  args     = {},
  want     = 0,
  token    = 0,
  room     = PIPE_CAP,
}

local frames = 0

local ARGS = {                          -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9 },
  [0x01] = { [0x04] = 0, [0x05] = 0, [0x06] = 0 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print("[dev] " .. string.format(fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

-- ---------------------------------------------------------------------------
-- The stream
--
-- A line is 62 characters and a CRLF.  Four hashes start a run and the
-- sequence begins again at 0000 on the line after, so a boundary is not a gap.
-- Every line but the banner carries its sequence in hex and a '#' one body column
-- further right than the line before it.
-- ---------------------------------------------------------------------------
local BODY_AT   = 6                     -- the body's first character, 1 based
local BODY_LEN  = 57

local st = {
  bytes = 0, lines = 0, runs = 0, bad = 0,
  gaps = 0, missing = 0, repeats = 0, stripe = 0,
  expect = nil, col = nil, paths = {},
  first = nil, last = nil,              -- emulated time of the first and last
}                                       -- byte, so the menu is not in the rate
local pending = ""

local function check(line)
  st.lines = st.lines + 1
  if #line ~= 62 then st.bad = st.bad + 1 return end

  if line:sub(1, 4) == "####" then
    st.runs = st.runs + 1
    -- The path the banner names is the only sign down the pipe of which key
    -- the menu took, so a run pressing 1, 2 or 3 is checked on it.
    st.paths[#st.paths + 1] = line:match("^#### RUN %d+ (%S+)") or "?"
    st.expect, st.col = 0, nil
    return
  end

  local seq = tonumber(line:sub(1, 4), 16)
  if seq == nil or line:sub(5, 5) ~= " " then st.bad = st.bad + 1 return end

  if st.expect ~= nil then
    if seq == (st.expect - 1) & 0xFFFF then
      st.repeats = st.repeats + 1
    elseif seq ~= st.expect then
      st.gaps = st.gaps + 1
      st.missing = st.missing + ((seq - st.expect) & 0xFFFF)
    end
  end
  st.expect = (seq + 1) & 0xFFFF

  -- The diagonal.  One '#' in the body, and one column right of the last.
  local at = line:find("#", BODY_AT, true)
  if at == nil or line:find("#", at + 1, true) ~= nil then
    st.stripe = st.stripe + 1
    st.col = nil
    return
  end
  local col = at - BODY_AT
  if st.col ~= nil and col ~= (st.col + 1) % BODY_LEN then
    st.stripe = st.stripe + 1
  end
  st.col = col
end

-- Emulated seconds, which is the machine's own clock and not the wall's.  A
-- MAME too old to answer leaves the rate out rather than inventing one.
local function emu_seconds()
  local ok, t = pcall(function () return manager.machine.time:as_double() end)
  if ok and type(t) == "number" then return t end
  return nil
end

local function pipe_in(s)
  st.bytes = st.bytes + #s
  st.last = emu_seconds()
  if st.first == nil then st.first = st.last end
  pending = pending .. s
  while true do
    local nl = pending:find("\n", 1, true)
    if not nl then break end
    local line = pending:sub(1, nl - 1):gsub("\r$", "")
    if ECHO then print("[pipe] " .. line) end
    check(line)
    pending = pending:sub(nl + 1)
  end
end

-- summary — every count the run ended on, down the log.  The rate spans the
-- first byte to the last, so time spent in the menu is not in it, and it is
-- the emulated machine's rather than a real one.
local function summary()
  if dirty_byte and not dirtied then
    log("chip RAM was never dirtied — rom_entry was not reached")
  end
  log("%d commands, %d failed, %d lost", commands, failed, lost)
  log("%d bytes, %d lines, %d runs", st.bytes, st.lines, st.runs)
  if #st.paths > 0 then log("paths %s", table.concat(st.paths, " ")) end
  log("gaps %d missing %d repeats %d stripe %d malformed %d",
      st.gaps, st.missing, st.repeats, st.stripe, st.bad)
  if st.first and st.last and st.last > st.first then
    local secs = st.last - st.first
    log("%.0f bits per second over %.2f emulated seconds sending",
        st.bytes * 8 / secs, secs)
  end
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

  commands = commands + 1
  if LOSE_EVERY > 0 and commands % LOSE_EVERY == 0 then
    lost = lost + 1
    return
  end
  if FAIL_EVERY > 0 and commands % FAIL_EVERY == 0 then
    failed = failed + 1
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
    put_data(1, 0x01 | 0x04 | 0x08)               -- host to device, attached
    put_data(2, dev.room > 0xFF and 0xFF or dev.room)
    put_data(3, 0)                                -- nothing coming back
    put_data(4, 1)                                -- USB CDC
    answer(true)
  elseif g == 0x04 and c == 0x02 then             -- PIPE_WRITE
    local n = a[6]
    if a[5] ~= 0 or n < 1 or n > 4 then answer(false) return end
    if DRAIN > 0 then
      if n > dev.room then answer(false) return end
      dev.room = dev.room - n
    end
    local s = ""
    for i = 1, n do s = s .. string.char(a[i]) end
    pipe_in(s)
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
-- until clear_value, so anything pressed here has to be released by name.
local function press(field, on)
  if on then field:set_value(1) else field:clear_value() end
end

-- The legends on one key cap.  A field is named after the whole cap with two
-- spaces between the legends, so the T key is "t  T" and Enter is "Enter".
local function legends(fname)
  local out = {}
  for one in (fname .. "  "):gmatch("(.-)  +") do
    if one ~= "" then out[#out + 1] = one end
  end
  return out
end

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

local keys = {}
for item in (os.getenv("RBCP_KEYS") or ""):gmatch("[^;]+") do
  local at, name = item:match("^(%d+):(.*)$")
  if not at then error("RBCP_KEYS items are frame:Key, e.g. 200:Enter") end
  keys[#keys + 1] = { at = tonumber(at), name = name, field = need_field(name) }
end
local KEY_HOLD = 6

emu.register_frame_done(function()
  frames = frames + 1

  -- The far end takes its bytes off the pipe once a frame.
  if DRAIN > 0 then
    dev.room = dev.room + DRAIN
    if dev.room > PIPE_CAP then dev.room = PIPE_CAP end
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
    summary()
    manager.machine:exit()
  end
end)
