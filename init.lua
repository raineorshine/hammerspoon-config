--[[

Simultaneous VI Mode (smode)

Ad hoc testing guidelines:
  ✓ press activation keys at same time -> should enter smode and enable navigation
  ✓ tap activate keys several times -> should enter and exit smode smoothly
  ✓ press and hold one activation key, then press and hold the other -> should type characters
  ✓ enter and exit smode and then press single activation key -> should type character
  ✓ press gs<enter> within MAX_TIME -> enter gets delayed until after 's'
  ✓ activate, release one, re-activate, release other -> should enter and exit smode smoothly without typing characters.

Hammerspoon Console Tips:
  - hs.reload()

--]]

---------------------------------------------------------------
-- Constants
---------------------------------------------------------------

local KEY1 = hs.keycodes.map[1] -- the physical 's' key, independent of keyboard layout
local KEY2 = hs.keycodes.map[2] -- the physical 'r' key, independent of keyboard layout

local mappings = {
  { from = 'h', to = 'left' },
  { from = 'n', to = 'down' },
  { from = 'e', to = 'up' },
  { from = 'i', to = 'right' },
  { from = 'd', to = 'delete', fromMod = {'shift'}, toMod = {'ctrl', 'shift'} },
  -- must come after since it will pick up any modifier
  { from = 'd', to = 'forwarddelete' }
}

-- If KEY1 and KEY2 are *both* pressed within this time period, consider this to
-- mean that they've been pressed simultaneously, and therefore we should enter
-- smode.
local ACTIVATION_WINDOW = 0.04 -- 40 milliseconds

---------------------------------------------------------------
-- State
---------------------------------------------------------------

local keysDown = {}
-- NOTE: active is different than just having both keys down, since that can happen from non-simultaneous (sequential press and hold) key presses
local active = false

-- when an activation key is pressed, store the key in case the other key is not pressed
-- then we can send the activation key as a normal key press
local pending = false
local pendingKey = nil
local pendingModifiers = {}
local pendingNonce = 0

-- when smode
local cooldown = false

-- used to force a normal key press
local force = false

---------------------------------------------------------------
-- Helper Functions
---------------------------------------------------------------

local eventTypes = hs.eventtap.event.types

-- return true if the given key is one of the activation keys
local isActivationKey = function(char)
  return char == KEY1 or char == KEY2
end

-- return true if the given key is pressed
local isKeyDown = function(char)
  return keysDown[char]
end

-- return the opposite of the given activation key
local other = function(char)
  return char == KEY1 and KEY2 or KEY1
end

-- convert a table to an indexed list of keys
local keys = function(table)
  local list = {}
  local n = 0
  for k, v in pairs(table) do
    n = n + 1
    list[n] = k
  end
  return list
end

-- finds a mapping for the given key + modifiers if it exists
local findMapping = function(key, modifiers)
  local n = 0
  for _,mapping in pairs(mappings) do
    if mapping.from == key and (not mapping.fromMod or table_eq(mapping.fromMod, modifiers)) then
      return mapping
    end
  end
  return nil
end

-- send a raw key event
local sendKeyDown = function(key, modifiers)
  -- force the key through as a normal key press
  force = true
  hs.eventtap.event.newKeyEvent(modifiers, key, true):post()
end

-- send a mapped a key event or if there is no mapping return false
local sendMappedKeyDown = function(key, modifiers)

  local mapping = findMapping(key, modifiers)
  if mapping then
    -- if toMod is not specified, pass whatever modifiers are pressed
    -- print('sending mapping', mapping.to)
    sendKeyDown(mapping.to, mapping.toMod or modifiers)
    return true
  end

end

-- http://stackoverflow.com/questions/25922437/how-can-i-deep-compare-2-lua-tables-which-may-or-may-not-have-tables-as-keys
function table_eq(table1, table2)
   local avoid_loops = {}
   local function recurse(t1, t2)
      -- compare value types
      if type(t1) ~= type(t2) then return false end
      -- Base case: compare simple values
      if type(t1) ~= "table" then return t1 == t2 end
      -- Now, on to tables.
      -- First, let's avoid looping forever.
      if avoid_loops[t1] then return avoid_loops[t1] == t2 end
      avoid_loops[t1] = t2
      -- Copy keys from t2
      local t2keys = {}
      local t2tablekeys = {}
      for k, _ in pairs(t2) do
         if type(k) == "table" then table.insert(t2tablekeys, k) end
         t2keys[k] = true
      end
      -- Let's iterate keys from t1
      for k1, v1 in pairs(t1) do
         local v2 = t2[k1]
         if type(k1) == "table" then
            -- if key is a table, we need to find an equivalent one.
            local ok = false
            for i, tk in ipairs(t2tablekeys) do
               if table_eq(k1, tk) and recurse(v1, t2[tk]) then
                  table.remove(t2tablekeys, i)
                  t2keys[tk] = nil
                  ok = true
                  break
               end
            end
            if not ok then return false end
         else
            -- t1 has a key which t2 doesn't have, fail.
            if v2 == nil then return false end
            t2keys[k1] = nil
            if not recurse(v1, v2) then return false end
         end
      end
      -- if t2 has a key which t1 doesn't have, fail.
      if next(t2keys) then return false end
      return true
   end
   return recurse(table1, table2)
end

-- resolve the pending mode and optionally send the pending key
local resolvePending = function(send)
  -- print('resolve pending', send)
  pending = false
  -- increment the pendingNonce to invalidate the existing window
  pendingNonce = pendingNonce + 1
  if send then
    sendKeyDown(pendingKey, pendingModifiers)
  end
end

---------------------------------------------------------------
-- KeyDown
---------------------------------------------------------------

hs.eventtap.new({ eventTypes.keyDown }, function(event)

  ---------------------------------------------------------------
  -- Setup
  ---------------------------------------------------------------

  -- read char
  local char = event:getCharacters(true):lower()
  if char == ' ' then
    char = 'space'
  end
  -- print('--' .. char .. '--')

  -- allow key presses to be forced through
  if force then
    -- print('force')
    force = false
    return false
  end

  -- any activation key
  local isAct = isActivationKey(char)
  if isAct then
    keysDown[char] = true
  end

  ---------------------------------------------------------------
  -- Suppress and modify cases
  ---------------------------------------------------------------

  -- first activation key
  if isAct and not active and not pending then
    -- print('first activation key')
    pending = true
    pendingKey = char
    pendingModifiers = keys(event:getFlags())

    -- start activation window
    -- use a nonce so the callback can be invalidated manually
    pendingNonce = pendingNonce + 1
    local activationNonce = pendingNonce
    hs.timer.doAfter(ACTIVATION_WINDOW, function()
      -- print('activation window end')
      if pendingNonce == activationNonce then
        -- print('  not supressed: valid nonce')
        resolvePending(true)
      else
        -- print('  suppressed: old nonce')
      end
    end)

  -- any non-activation key will resolve pending
  elseif pending and not isAct then
    local keyCode = event:getKeyCode()
    -- print('non-activation key', keyCode)
    resolvePending(true)
    local isSpecial = not (next(event:getFlags()) == nil)
      or keyCode == 36 -- enter
      or keyCode == 53 -- escape
      or keyCode == 51 -- backspace
    -- async send the current key so that is pressed after the pending key
    hs.timer.doAfter(0, function()
      -- local modifier = next(event:getFlags()) == nil and {} or keys(event:getFlags())
      -- if not a normal character, must use keystroke (slower)
      if isSpecial then
        -- print('resolve pending short circuit (special key)')
        force = true
        hs.eventtap.keyStroke(keys(event:getFlags()), keyCode)
      else
        -- print('resolve pending short circuit (normal key)', keyCode)
        sendKeyDown(char, modifiers)
      end
    end)

  -- activate
  elseif not active and pending and isKeyDown(other(char)) then
    -- print('activate!')
    active = true
    resolvePending(false)

  -- suppress activation keys when in smode
  elseif active and isAct then
    -- leave empty so that we return true at the end

  -- if none of the cases apply, we can return false for a normal key press
  else
    return false
  end

  -- all code paths above suppress the key press
  -- except for the explicit return false in the else case
  return true

end):start()

---------------------------------------------------------------
-- KeyUp
---------------------------------------------------------------

hs.eventtap.new({ eventTypes.keyUp }, function(event)

  local char = event:getCharacters(true):lower()

  if isActivationKey(char) then
    -- print('activation key up: resume pending', char)

    keysDown[char] = false

    -- if one key is released, just go back to pending
    pending = true

    -- if both keys have been released, re-enable activation keys
    if not isKeyDown(KEY1) and not isKeyDown(KEY2) then
      -- print('  both keys up: exit smode')
      active = false
      resolvePending(false)
    end
  end

end):start()

---------------------------------------------------------------
-- Navigation
---------------------------------------------------------------

-- keyDown
-- (duplicate event handlers handled in LIFO order)
hs.eventtap.new({ eventTypes.keyDown }, function(event)
  return active and sendMappedKeyDown(event:getCharacters(true):lower(), keys(event:getFlags()))
end):start()
