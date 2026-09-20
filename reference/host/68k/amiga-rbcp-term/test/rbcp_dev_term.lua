-- rbcp_dev_term.lua — a fake RBCP device for MAME with a far end that talks
-- back, watching the Amiga's Kickstart socket.
-- Copyright (C) 2026 Piers Finlayson <piers@piers.rocks>
--
-- Watches every read in the Kickstart window, decodes the RBCP command stream
-- from the addresses, and answers by substituting bytes on reads of the
-- back-channel region.  Enough of the protocol for the terminal, and no more.
--
-- Two pipes, one each way.  Pipe 0 carries host to device and pipe 1 device to
-- host, so the terminal's scan has to find each direction rather than landing
-- on a single pipe that does both.  Whatever arrives on pipe 0 comes back on
-- pipe 1 with a prefix, so the text on screen is provably the text that was
-- typed.
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

local RUN_FRAMES = tonumber(os.getenv("RBCP_FRAMES") or "900")
local DEBUG      = os.getenv("RBCP_DEBUG") ~= nil
-- "04:03" makes the device refuse PIPE_READ, which stops the terminal reading
-- and puts the reason on its status bar.
local REFUSE     = os.getenv("RBCP_REFUSE")
-- A device that goes wrong now and then.  One command in FAIL_EVERY is
-- answered with failure and one in LOSE_EVERY is not answered at all.
local FAIL_EVERY = tonumber(os.getenv("RBCP_FAIL_EVERY") or "0")
local LOSE_EVERY = tonumber(os.getenv("RBCP_LOSE_EVERY") or "0")
local commands, failed, lost = 0, 0, 0

-- The pipes this device has.  PIPE_WRITE is refused on anything but the OUT
-- pipe and PIPE_READ on anything but the IN pipe, so a terminal that picked
-- the wrong one is caught here rather than appearing to work.
local PIPE_OUT   = tonumber(os.getenv("RBCP_PIPE_OUT") or "0")
local PIPE_IN    = tonumber(os.getenv("RBCP_PIPE_IN") or "1")
local PIPE_COUNT = 2
-- Set to run the device with no inbound pipe, which is the terminal's
-- send-only path.
if os.getenv("RBCP_NO_IN") then
  PIPE_IN, PIPE_COUNT = -1, 1
end

-- The prefix the far end puts on a line it echoes back, and what it says
-- before anything has been typed at it.  "\n" in RBCP_SEND is a line feed,
-- which ends a line.
local ECHO_PREFIX = os.getenv("RBCP_ECHO") or "you said "
local rx_text = (os.getenv("RBCP_SEND") or ""):gsub("\\n", "\n")
local rx_at = 1

-- The most PIPE_READ can be asked for here is the region less its eight-byte
-- response header and the eight bytes PIPE_READ puts in front of the data.
local PIPE_READ_ROOM = BCH_SIZE - 8 - 8

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
  knock_at = 0,                         -- how much of the knock has matched
  knocked  = false,
  group    = nil,
  cmd      = nil,
  args     = {},
  want     = 0,
  token    = 0,
}

local frames = 0

local ARGS = {                          -- [group][cmd] = argument count
  [0x00] = { [0x00] = 0, [0x01] = 9, [0x02] = 0, [0x03] = 0 },
  [0x01] = { [0x04] = 0, [0x05] = 0, [0x06] = 0 },
  [0x04] = { [0x00] = 0, [0x01] = 1, [0x02] = 6, [0x03] = 2 },
  [0xAA] = { [0xAA] = 0 },
}

local function log(fmt, ...) print(string.format("[dev] " .. fmt, ...)) end

local function put_data(i, v) bch[8 + i] = v & 0xFF end

local function put_string(i, s)
  for n = 1, #s do put_data(i + n - 1, s:byte(n)) end
  put_data(i + #s, 0)
end

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

-- PIPE_WRITE moves at most four bytes, so a typed line arrives in pieces.
-- They are held here until the line feed that ends the line, then printed
-- whole and handed back to the terminal on the inbound pipe.
local tx_line = ""
local lines_in = 0
local function pipe_out(s)
  tx_line = tx_line .. s
  while true do
    local nl = tx_line:find("\n")
    if not nl then break end
    local one = tx_line:sub(1, nl - 1):gsub("\r", "")
    lines_in = lines_in + 1
    io.write("[pipe>] " .. printable(one) .. "\n")
    if PIPE_IN >= 0 then
      rx_text = rx_text .. ECHO_PREFIX .. one .. "\n"
    end
    tx_line = tx_line:sub(nl + 1)
  end
end

local function pipe_flush()
  if tx_line ~= "" then pipe_out(tx_line .. "\n") end
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
  if REFUSE == string.format("%02X:%02X", g, c) then
    log("%02X/%02X refused", g, c)
    answer(false)
    return
  end
  if g == 0xAA then
    dev.cmd_resp = false
    log("RESET")
    return
  end

  -- The intermittent device.  Counted after the reset, because a reset is not
  -- a command the host is waiting on an answer to.
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
    put_data(0, PIPE_COUNT)
    answer(true)
  elseif g == 0x04 and c == 0x01 then             -- GET_PIPE_INFO
    local n = a[1]
    if n ~= PIPE_OUT and n ~= PIPE_IN then answer(false) return end
    local flags = 0x04 | 0x08                     -- far end known, attached
    if n == PIPE_OUT then flags = flags | 0x01 end
    if n == PIPE_IN then flags = flags | 0x02 end
    put_data(0, 0)                                -- raw
    put_data(1, flags)
    put_data(2, (n == PIPE_OUT) and 0xFF or 0)    -- room to write
    put_data(3, (n == PIPE_IN) and rx_waiting() or 0)
    put_data(4, 1)                                -- USB CDC
    log("GET_PIPE_INFO %d flags $%02X", n, flags)
    answer(true)
  elseif g == 0x04 and c == 0x02 then             -- PIPE_WRITE
    local n, pipe, s = a[6], a[5], ""
    if pipe ~= PIPE_OUT then answer(false) return end
    for i = 1, n do s = s .. string.char(a[i]) end
    pipe_out(s)
    answer(true)
  elseif g == 0x04 and c == 0x03 then             -- PIPE_READ
    local want, pipe = a[1], a[2]
    if pipe ~= PIPE_IN then answer(false) return end
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

-- ---------------------------------------------------------------------------
-- The screen, read back as text
--
-- The terminal draws to a bitmap, so a run leaves nothing to print.  The font
-- the image was built with is on disk, so every glyph's eight bytes map back
-- to the character that drew them and the whole screen comes out as lines.
--
-- Three combinations of pens appear.  Text is pen 5 on background, which puts
-- the glyph in plane 0.  Reversed text is the background pen on pen 5, which
-- puts its inverse there.  The two bars are black on gold, which puts the
-- inverse of the glyph in plane 1 and nothing in plane 0.
-- ---------------------------------------------------------------------------
local BITPLANE_BASE = 0x8000
local ROW_STRIDE    = 40 * 4 * 8
local PLANE_W       = 40
local ROW_BYTES     = 40 * 4

local glyphs = {}
local font_path = os.getenv("RBCP_FONT")
if font_path then
  local f = io.open(font_path, "rb")
  if f then
    local data = f:read("a")
    f:close()
    -- Printable ASCII only, so a blank cell comes out as a space rather than
    -- as one of the other glyphs the font draws as nothing.
    for code = 32, 126 do
      glyphs[data:sub(code * 8 + 1, code * 8 + 8)] = string.char(code)
    end
  end
end

local function cell(row, col, plane)
  local base = BITPLANE_BASE + row * ROW_STRIDE + plane * PLANE_W + col
  local out = {}
  for line = 0, 7 do
    out[#out + 1] = string.char(mem:read_u8(base + line * ROW_BYTES))
  end
  return table.concat(out)
end

local function invert(s)
  return (s:gsub(".", function (ch) return string.char(~ch:byte() & 0xFF) end))
end

local ZERO = string.rep("\0", 8)

local function screen_char(row, col)
  local p0 = cell(row, col, 0)
  local p1 = cell(row, col, 1)
  if p0 ~= ZERO then
    return glyphs[p0] or glyphs[invert(p0)] or "?"
  elseif p1 ~= ZERO then
    return glyphs[invert(p1)] or glyphs[p1] or "?"
  end
  return " "
end

local function screen_dump()
  if next(glyphs) == nil then
    log("no font, so the screen cannot be read back")
    return
  end
  print("[screen] +----------------------------------------+")
  for row = 0, 24 do
    local line = {}
    for col = 0, 39 do line[#line + 1] = screen_char(row, col) end
    print("[screen] |" .. table.concat(line) .. "|")
  end
  print("[screen] +----------------------------------------+")
end

-- ---------------------------------------------------------------------------
-- Typing
--
-- RBCP_TYPE is the script, one character at a time through the emulated
-- keyboard.  "\n" is RETURN and "\b" is BACKSPACE, the terminal's rub-out key.
-- A character that is the second legend on a key cap holds a shift key over
-- the keystroke, which covers the capitals and the shifted punctuation alike.
--
-- set_value is a sticky override that lasts until clear_value, so every key
-- pressed here is released by name or the machine sees it held for ever.
-- ---------------------------------------------------------------------------
local function press(field, on)
  if on then field:set_value(1) else field:clear_value() end
end

-- The legends on one key cap.  A field is named after the whole cap with two
-- spaces between the legends, so the S key is "s  S  ß §".
local function legends(fname)
  local out = {}
  for one in (fname .. "  "):gmatch("(.-)  +") do
    if one ~= "" then out[#out + 1] = one end
  end
  return out
end

-- The key a name asks for, and whether shift has to be held to get it.  The
-- whole name wins, then the first legend on a cap, then the second, so "s"
-- finds the S key and "S" and "?" find theirs with shift.
local function find_field(name)
  local plain, shifted, prefix
  for _, port in pairs(manager.machine.ioport.ports) do
    for fname, f in pairs(port.fields) do
      if fname == name then return f, false end
      local cap = legends(fname)
      if cap[1] == name and plain == nil then plain = f end
      if cap[2] == name and shifted == nil then shifted = f end
      if prefix == nil and fname:sub(1, #name) == name then prefix = f end
    end
  end
  if plain ~= nil then return plain, false end
  if shifted ~= nil then return shifted, true end
  return prefix, false
end

local function need_field(name)
  local f, caps = find_field(name)
  if f == nil then error("no input field named " .. name) end
  return f, caps
end

local TYPE_AT   = tonumber(os.getenv("RBCP_TYPE_AT") or "240")
local TYPE_GAP  = tonumber(os.getenv("RBCP_TYPE_GAP") or "12")
local KEY_HOLD  = tonumber(os.getenv("RBCP_TYPE_HOLD") or "6")

local script = (os.getenv("RBCP_TYPE") or ""):gsub("\\n", "\n"):gsub("\\b", "\b")
local typing, shift = {}, nil
if script ~= "" then
  shift = need_field("Left Shift")
  local at = TYPE_AT
  -- The keys with no legend to look them up by.
  local named = { ["\n"] = "Enter", ["\b"] = "Backspace", [" "] = "Space" }
  for i = 1, #script do
    local ch = script:sub(i, i)
    local field, caps = need_field(named[ch] or ch)
    typing[#typing + 1] = { at = at, ch = ch, caps = caps, field = field }
    at = at + TYPE_GAP
  end
end

emu.register_frame_done(function()
  frames = frames + 1

  for _, k in ipairs(typing) do
    if frames == k.at - 1 and k.caps then
      press(shift, true)
    elseif frames == k.at then
      press(k.field, true)
    elseif frames == k.at + KEY_HOLD then
      press(k.field, false)
    elseif frames == k.at + KEY_HOLD + 1 and k.caps then
      press(shift, false)
    end
  end

  if frames >= RUN_FRAMES then
    if os.getenv("RBCP_SNAP") then manager.machine.video:snapshot() end
    pipe_flush()
    screen_dump()
    if dirty_byte and not dirtied then
      log("chip RAM was never dirtied — rom_entry was not reached")
    end
    log("%d commands, %d failed, %d lost, %d lines typed",
        commands, failed, lost, lines_in)
    manager.machine:exit()
  end
end)
