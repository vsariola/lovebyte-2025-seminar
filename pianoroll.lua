-- local pat = {0, 4, 5, 7}
local pat = {0, 0, 4, 2, 3, 3, 6, 6, 0, 0, 2, 3, 4, 4, 3, 2}
function melody(t, chan)
 return pat[(t * chan >> 6) % #pat + 1] + chan * 7
end

function mapping(melody, chord)
 return (melody + chord + 1) * 12 // 7 - 1
 -- return (melody + chord
end

local progression = {0, 0, 3, 5, 0, 7, 8, 10}
local progression = {1, 1, 0, 0, 1, 1, 0, 4}
function chord(t)
 --  local chords = {0, 0, 0, 0, 1, 1, 1, 1}
 return progression[(t >> 7) % #progression + 1]
end

function mapped(t, chan)
 if not chn_cbs[chan + 1].checked then
  return -1
 end
 local m = melody(t, chan)
 if m == -1 then
  return -1
 end
 local c = chord(t)
 return mapping(m, chord(t))
end

------------
-- CONSTANTS
------------
PIANO_Y = 101
PIANO_HEIGHT = 25
PIANO_BLACK_HEIGHT = 15
PIANO_NUM_KEYS = 51
PMEM_PLAY = 10
PMEM_T = 11
PMEM_CHORDS = 0
PMEM_MAPPING = 1
PMEM_BG = 2
PMEM_DRAWTIME = 3
PMEM_CHANS = 4

-- computes the color of a given key, given the notes that are being played at
-- that time
function keycolor(k, notes)
 local ret = 0
 for i = 0, 3 do
  if k == notes[i + 1] then
   ret = ret + (1 << i)
  end
 end
 return ret
end

function pianokey(k)
 local o = k // 12
 local n = k % 12
 if n == 1 or n == 3 or n == 6 or n == 8 or n == 10 then
  -- black key
  return n * 56 // 12 + o * 56 + 1, 3, 1
 end
 -- white key
 return (n * 7 + 1) // 12 * 8 + o * 56, 7, 0
end

-- clear top bar, left and bottom bars
rect(0, 0, 240, 7, 0)
rect(0, 0, 7, 136, 0)
rect(0, PIANO_Y, 240, 136 - PIANO_Y, 0)
-- make the text that is on screen gray and everything else black
for i = 0, 32639 do
 c = peek4(i)
 poke4(i, (c ~= 0 and c ~= 15) and 3 or 0)
end
-- copy whatever was in the screen to where the map is are so we can show it in
-- the background
memcpy(0x8000, 0, 16320)

-- initialize palette
vbank(1)
for i = 0, 15 do
 for j = 0, 2 do
  tot = 0
  C = 0
  for c = 0, 3 do
   W = math.sin(c ^ 8 + j) ^ 2
   C = C + W * ((i >> c) & 1)
   tot = tot + W
  end
  C = C / tot
  poke(16320 + i * 3 + j, 255 * C ^ 0.45);
 end
end
vbank(0)
-- background colors are gray
for i = 0, 15 do
 poke(16320 + i * 3 + 0, i * 255 / 15);
 poke(16320 + i * 3 + 1, i * 255 / 15);
 poke(16320 + i * 3 + 2, i * 255 / 15);
end

chords_cb = {}
bg_cb = {}
mapping_cb = {}
keys_state = {}
time_cb = {}
chn_cbs = {{}, {}, {}, {}}

play = pmem(PMEM_PLAY) > 0 and true or false
t = pmem(PMEM_T)

mapcache = {}
function TIC()
 play_sounds()
 for i = 0, 127 do
  mapcache[i] = -1
 end
 local C = chord(t)
 for i = 0, 127 do
  local n = mapping(i, chord(t))
  mapcache[n] = i
 end
 vbank(0)
 draw_background()
 if chords_cb.checked then
  draw_chord_lines()
 end
 if time_cb.checked then
  draw_time()
 end
 vbank(1)
 cls(0)
 draw_pianoroll()
 draw_keys(keys_state)
 x = 0
 x = x + 5 + checkbox(chords_cb, "chords", x, 130, PMEM_CHORDS)
 x = x + 5 + checkbox(mapping_cb, "mapping", x, 130, PMEM_MAPPING)
 x = x + 5 + checkbox(bg_cb, "bg", x, 130, PMEM_BG)
 x = x + 5 + checkbox(time_cb, "t", x, 130, PMEM_DRAWTIME, nil, function()
  t = 0
 end)
 x = 216
 for i = 0, 3 do
  x = x + 1 + checkbox(chn_cbs[i + 1], "", x, 130, PMEM_CHANS + i, 1 << i, function(s)
   for j = 0, 3 do
    chn_cbs[j + 1].checked = not s
   end
  end)
 end
 if play then
  t = t + 1
 end
 if keyp(48) then
  play = not play
  if play and key(63) then
   t = 0
  end
 end
 if keyp(55) then
  t = 0
 end
 if key(63) then
  t = t - (keyp(59) and 1 or 0)
  t = t + (keyp(58) and 1 or 0)
 else
  t = t - (key(59) and 4 or 0)
  t = t + (key(58) and 4 or 0)
 end
 pmem(PMEM_PLAY, play and 1 or 0)
 pmem(PMEM_T, t)
end

-- sound functioms
play_sounds_notes = {}
function play_sounds()
 for chan = 0, 3 do
  local n = mapped(t, chan)
  if not play then
   n = -1
  end
  if chan == 0 and keys_state.pressed ~= nil and keys_state.pressed >= 0 then
   n = keys_state.pressed
  end
  if play_sounds_notes[chan + 1] ~= n then
   play_sounds_notes[chan + 1] = n
   if n >= 0 then
    sfx(0, n + 12, 1000, chan, 15)
   else
    sfx(0, 0, 0, chan, 15)
   end
  end
 end
end

-- drawing and GUI functions
pianoroll_tmp = {}
function draw_pianoroll()
 for i = 0, PIANO_Y - 1 do
  for chan = 0, 3 do
   pianoroll_tmp[chan + 1] = mapped(t + i, chan)
  end
  for chan = 0, 3 do
   local x, w, type = pianokey(pianoroll_tmp[chan + 1])
   local C = keycolor(pianoroll_tmp[chan + 1], pianoroll_tmp)
   rect(x, PIANO_Y - i - 1, w, 1, C)
  end
 end
end

function draw_background(y1, y2)
 y1 = y1 == nil and 0 or y1
 y2 = y2 == nil and PIANO_Y or y2
 if bg_cb.checked then
  memcpy(y1 * 120, 0x8000 + y1 * 120, (y2 - y1) * 120)
 else
  memset(y1 * 120, 0, (y2 - y1) * 120)
 end
end

function draw_chord_lines()
 local c1 = chord(t - 1)
 local c2
 for i = 0, PIANO_Y - 1 do
  local y = PIANO_Y - i - 1
  local c = chord(t + i)
  if c2 ~= c1 then
   x, w, _ = pianokey(mapped(t + i, 0))
   draw_background(y - 14, y + 1)
   print(c1, x + w + 1, y - 14, 8, 1, 3)
   c2 = c1
  end
  if c ~= c1 then
   c1 = c
   rect(0, y, 240, 1, 8)
  end
 end
end

function draw_time()
 local y = PIANO_Y - 1
 right("t=" .. t, 228, y - 5, 8)
 local t0 = -t % 8
 for i = t0, PIANO_Y, 8 do
  local T = t + i
  local b = T >> 3 & 15
  local l = 1
  if b == 0 then
   l = 12
  elseif b == 8 then
   l = 6
  end
  local y = PIANO_Y - i - 1
  rect(240 - l, y, l, 1, 8)
 end
end

function draw_keys(keys_state)
 local y = PIANO_Y
 rect(0, y, 240, PIANO_HEIGHT, 0)
 local text_y = (PIANO_HEIGHT + PIANO_BLACK_HEIGHT - 5) // 2 + PIANO_Y
 local text_bg = nil
 local key_height = PIANO_HEIGHT
 local mx, my, left = mouse()
 if not left then
  keys_state.pressed = nil
 end
 for chan = 0, 3 do
  pianoroll_tmp[chan + 1] = mapped(t, chan)
 end
 if keys_state.pressed ~= nil then
  pianoroll_tmp[1] = keys_state.pressed
 end
 -- draw white keys first, then black keys
 for T = 0, 1 do
  for i = 0, PIANO_NUM_KEYS - 1 do
   x, w, type = pianokey(i)
   if type == T then
    rectb(x - 1, PIANO_Y, w + 2, key_height, 0) -- black outline
    local C = keycolor(i, pianoroll_tmp)
    if T == 0 and C == 0 then
     C = 15
    end
    rect(x, PIANO_Y + 1, w, key_height - 2, C)
    if mx >= x - 1 and mx < x + w + 2 and my >= PIANO_Y and my < PIANO_Y + key_height and left then
     keys_state.pressed = i
    end
    if mapcache[i] >= 0 and mapping_cb.checked then
     local M = mapcache[i]
     center(M, x + w // 2 + 1, text_y, 6, text_bg)
    end
   end
  end
  text_y = (PIANO_BLACK_HEIGHT - 5) // 2 + PIANO_Y
  text_bg = 0
  key_height = PIANO_BLACK_HEIGHT
 end
end

-- GUI FUNCTIONS
function checkbox(s, t, x, y, a, c, f)
 if a ~= nil and s.checked == nil then
  s.checked = pmem(a) > 0 and true or false
 end
 c = c == nil and 14 or c
 rectb(x, y, 5, 5, 15)
 if s.checked then
  rect(x + 1, y + 1, 3, 3, c)
 end
 w = 5
 if t ~= "" then
  w = w + 2 + print(t, x + 7, y)
 end
 local mx, my, left, _, right = mouse()
 if mx >= x and mx < x + w and my >= y and my < y + 5 then
  if left and left ~= s.left then
   s.checked = not s.checked
  end
  if right and right ~= s.right and f ~= nil then
   f(s.checked)
  end
 end
 s.left = left
 s.right = right
 if a ~= nil then
  pmem(a, s.checked and 1 or 0)
 end
 return w
end

function center(t, x, y, c, bg)
 w = print(t, -1000, -1000, 0, 0, 1, 1)
 if bg ~= nil then
  rect(x - w / 2 - 1, y, w + 1, 5, bg)
 end
 print(t, x - w / 2, y, c, 0, 1, 1)
end

function right(t, x, y, c, bg)
 w = print(t, -1000, -1000, 0, 0, 1, 1)
 if bg ~= nil then
  rect(x - w / 2 - 1, y, w + 1, 5, bg)
 end
 print(t, x - w, y, c, 0, 1, 1)
end

-- <TILES>
-- 001:eccccccccc888888caaaaaaaca888888cacccccccacc0ccccacc0ccccacc0ccc
-- 002:ccccceee8888cceeaaaa0cee888a0ceeccca0ccc0cca0c0c0cca0c0c0cca0c0c
-- 003:eccccccccc888888caaaaaaaca888888cacccccccacccccccacc0ccccacc0ccc
-- 004:ccccceee8888cceeaaaa0cee888a0ceeccca0cccccca0c0c0cca0c0c0cca0c0c
-- 017:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 018:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 019:cacccccccaaaaaaacaaacaaacaaaaccccaaaaaaac8888888cc000cccecccccec
-- 020:ccca00ccaaaa0ccecaaa0ceeaaaa0ceeaaaa0cee8888ccee000cceeecccceeee
-- 032:0c000000c0c00000c0c00000c0c000000c000000000000000000000000000000
-- 033:0c0000000c0000000c0000000c0000000c000000000000000000000000000000
-- 034:cc00000000c000000c000000c0000000ccc00000000000000000000000000000
-- 035:cc00000000c00000cc00000000c00000cc000000000000000000000000000000
-- 036:c0c00000c0c00000ccc0000000c0000000c00000000000000000000000000000
-- 037:ccc00000c0000000ccc0000000c00000cc000000000000000000000000000000
-- 038:ccc00000c0000000ccc00000c0c00000ccc00000000000000000000000000000
-- 039:ccc0000000c000000c000000c0000000c0000000000000000000000000000000
-- 040:ccc00000c0c00000ccc00000c0c00000ccc00000000000000000000000000000
-- 041:ccc00000c0c00000ccc0000000c00000cc000000000000000000000000000000
-- </TILES>

-- <WAVES>
-- 000:00000000ffffffff00000000ffffffff
-- 001:0123456789abcdeffedcba9876543210
-- 002:0123456789abcdef0123456789abcdef
-- </WAVES>

-- <SFX>
-- 000:c000300010002000400060009000a000b000c000c000d000d000d000e000e000e000f000f000f000f000f000f000f000f000f000f000f000f000f000400000f10000
-- </SFX>

-- <TRACKS>
-- 000:100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
-- </TRACKS>

-- <PALETTE>
-- 000:1a1c2c5d275db13e53ef7d57ffcd75a7f07038b76425717929366f3b5dc941a6f673eff7f4f4f494b0c2566c86333c57
-- </PALETTE>

