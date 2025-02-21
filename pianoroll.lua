-- t:   time (60 ticks / s)
-- chn: channel (0-3)
pat={0,0,4,2,3,3,6,6,0,0,2,3,4,4,3,2}
function note(t, chn)
 return pat[(t*chn>>6)%#pat+1]
end

-- t: time
prog={1,1,0,0,1,1,3.9,4} 
function chord(t)
 return prog[(t>>7)%#prog+1]
end

-- n: note (returned by func "note")
-- c: chord (returned by func "chord")
-- chn: channel (0-3)
function mapping(n, c, chn)
 return (n+c+5)*12//7-1+n%7//6 
end

function mapped(t, chn)
 if not chn_cbs[chn + 1].checked then
  return -1
 end
 local m = note(t, chn)
 if m == -1 then
  return -1
 end
 local c = chord(t)
 return math.floor(mapping(m, chord(t), chn))
end

------------
-- CONSTANTS
------------
PIANO_Y = 101
PIANO_HEIGHT = 25
PIANO_BLACK_HEIGHT = 15
PIANO_NUM_KEYS = 51
PMEM_PLAY = 10
PMEM_SX = 11
PMEM_SLIDE = 12
PMEM_SHOW_SLIDES = 13
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

chords_cb = {}
bg_cb = {}
mapping_cb = {}
keys_state = {}
time_cb = {}
chn_cbs = {{}, {}, {}, {}}

play = pmem(PMEM_PLAY) > 0 and true or false
t = 0
sx = pmem(PMEM_SX)
slide = pmem(PMEM_SLIDE)
show_slides = pmem(PMEM_SHOW_SLIDES) > 0 and true or false

mapcache = {}
function TIC()
 play_sounds()
 for i = 0, 127 do
  mapcache[i] = -1
 end
 local C = chord(t)
 for i = 0, 127 do
  local n = mapping(i, chord(t), 0)
  mapcache[n] = i
 end
 vbank(0)
 cls(0)
 draw_background()
 -- background colors are gray
 local a = 1 - sx / 240
 for i = 0, 15 do
  poke(16320 + i * 3 + 0, i * 255 / 15 * a);
  poke(16320 + i * 3 + 1, i * 255 / 15 * a);
  poke(16320 + i * 3 + 2, i * 255 / 15 * a);
 end

 if chords_cb.checked then
  draw_chord_lines()
 end
 if time_cb.checked then
  draw_time()
 end
 vbank(1)
 cls(0)
 if sx > 0 then
  draw_slides()
 end
 if sx < 240 then
  draw_gui()
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
 if keyp(60) then
  show_slides = true
 end
 if keyp(61) then
  show_slides = false
 end
 sx = clamp(sx + (show_slides and 32 or -32), 0, 240)
 pmem(PMEM_PLAY, play and 1 or 0)
 pmem(PMEM_SX, sx)
 pmem(PMEM_SLIDE, slide)
 pmem(PMEM_SHOW_SLIDES, show_slides and 1 or 0)
end

slides = {
 {
  {{t="LOVEBYTE 2025", x=0, y=10, c=15, s=3}, {t="Making Tiny Music with the 12-tone Scale", x=0, y=35, c=14}},
  {{t="- MIDI", x=0, y=55, c=10}}, {{t="- TIC-80", x=0, y=65, c=10}},
  {{t="- Anywhere where you can pow(2,n/12)", x=0, y=75, c=10}}
 }, {
  {{t="PROBLEMS", x=0, y=10, c=15, s=3}}, {
   {
    t="1) Hard to make good chord progressions\n   with only major chords, and even more\n   difficult with only minor chords",
    x=0, y=55, c=10
   }
  }, {{t="2) Voice leading is not smooth\n   (chords always at root position)", x=0, y=80, c=10}}
 }, {
  {
   {t="RRROLA TRICK:", x=0, y=10, c=15, s=3}, {t="n*12//7", x=100, y=35, c=14},
   {t="- maps 7-tone scale to 12-tone scale", x=0, y=55, c=10}
  }, {{t="- starting from n=0 is the Locrian mode,\n  but (n+1)*12//7 is the Ionian mode", x=0, y=70, c=10}}
 }, {
  {{t="HOMEWORK", x=0, y=10, c=15, s=3}},
  {{t="1) Try the RRROLA trick with *12//5.\n   What scale is this?\n   What are its two most useful modes?", x=0, y=55, c=10}},
  {{t="2) Find the smallest equation for\n   harmonic minor scale", x=0, y=80, c=10}},
  {{t="3) Try the RRROLA trick with the\n   chord-function returning\n   non-integer values.\n   What useful chords you find? ", x=0, y=100, c=10}}  
 }
}

function draw_slides()
 local sstart = 0
 for i = 1, #slides do
  for j = 1, #slides[i] do
   if slide < sstart + j - 1 or slide >= sstart + #slides[i] then
    goto continue
   end
   for k = 1, #slides[i][j] do
    local e = slides[i][j][k]
    local x = e.x or 0
    local y = e.y or 0
    local c = e.c or 15
    local s = e.s or 1
    print(e.t, x + sx - 240, y, c, 1, s)
   end
   ::continue::
  end
  sstart = sstart + #slides[i]
 end
 slide = slide + (keyp(59) and 1 or 0)
 slide = slide - (keyp(58) and 1 or 0)
 slide = clamp(slide, 0, sstart - 1)
end

function draw_gui()
 draw_pianoroll()
 draw_keys(keys_state)
 x = sx
 x = x + 5 + checkbox(chords_cb, "chords", x, 130, PMEM_CHORDS)
 x = x + 5 + checkbox(mapping_cb, "mapping", x, 130, PMEM_MAPPING)
 x = x + 5 + checkbox(bg_cb, "bg", x, 130, PMEM_BG)
 x = x + 5 + checkbox(time_cb, "t", x, 130, PMEM_DRAWTIME, nil, function()
  t = 0
 end)
 x = 216 + sx
 for i = 0, 3 do
  x = x + 1 + checkbox(chn_cbs[i + 1], "", x, 130, PMEM_CHANS + i, 1 << i, function(s)
   for j = 0, 3 do
    chn_cbs[j + 1].checked = not s
   end
  end)
 end
 if key(63) then
  t = t - (keyp(59) and 1 or 0)
  t = t + (keyp(58) and 1 or 0)
 else
  t = t - (key(59) and 4 or 0)
  t = t + (key(58) and 4 or 0)
 end
end

function clamp(x, a, b)
 return x < a and a or x > b and b or x
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
   if pianoroll_tmp[chan + 1] >= 0 then
    local x, w, type = pianokey(pianoroll_tmp[chan + 1])
    local C = keycolor(pianoroll_tmp[chan + 1], pianoroll_tmp)
    rect(x + sx, PIANO_Y - i - 1, w, 1, C)
   end
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

local _dcl_tmp = {{}, {}, {}, {}}
function draw_chord_lines()
 local c1 = chord(t - 1)
 local c2
 for i = 0, PIANO_Y - 1 do
  local y = PIANO_Y - i - 1
  local c = chord(t + i)
  if c2 ~= c1 then
   for j = 0, 3 do
    local x, w, _ = pianokey(mapped(t + i, j))
    _dcl_tmp[j + 1].x = x
    _dcl_tmp[j + 1].w = w
   end
   table.sort(_dcl_tmp, function(a, b)
    return a.x < b.x
   end)
   local x = 0
   local w = _dcl_tmp[1].x
   for j = 0, 3 do
    if w > 15 then
     break
    end
    x = _dcl_tmp[j + 1].x + _dcl_tmp[j + 1].w
    w = j < 3 and _dcl_tmp[j + 2].x - x or 1e6
   end
   draw_background(y - 14, y + 1)
   print(c1, sx + x + 1, y - 14, 8, 1, 3)
   c2 = c1
  end
  if c ~= c1 then
   c1 = c
   rect(sx, y, 240, 1, 8)
  end
 end
end

function draw_time()
 if sx < 240 then
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
end

function draw_keys(keys_state)
 local y = PIANO_Y
 rect(sx, y, 240, PIANO_HEIGHT, 0)
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
   x = x + sx
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

