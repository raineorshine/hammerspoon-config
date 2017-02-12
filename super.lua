--[[

Simultaneous VI Mode (smode)

Ad hoc testing guidelines:
  - press activation keys at same time -> should enter smode and enable navigation
  - tap activate keys several times -> should enter and exit smode smoothly
  - activate, hold, release one, hold, release other -> should exit smode smoothly
  - enter and exit smode and then press single activation key -> should type character
  - once activated, release one and then the other without releasing both -> should stay in smode
  - press and hold one activation key, then press and hold the other -> should type characters
  - press gs<enter> within MAX_TIME -> enter gets delayed until after 's'

--]]

------------------------------
-- Constants
------------------------------

-- Colemak remappings
local KEY1 = 'r'
local KEY2 = 's'

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
local MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES = 00.02 -- 20 milliseconds
-- local MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES = 0.4 -- DEBUG

------------------------------
-- State
------------------------------

local keysDown = {}
-- NOTE: need to keep track of which keys were pressed only within the delay
-- This allows sequential press and hold to type normal characters
local quickKeysDown = {}
local once = false
-- NOTE: active is different than just having both keys down, since that can happen from non-simultaneous (sequential press and hold) key presses
local active = false
local cooldown = false
local modifiers = {}
local delayedKeys = {}

------------------------------
-- Helper Functions
------------------------------

local eventTypes = hs.eventtap.event.types

-- delay a function and suspend smode during the delay
local delay = function(f)
  hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
    f()
  end)
end

local isActivationKey = function(char)
  return char == KEY1 or char == KEY2
end

local isKeyDown = function(char)
  return keysDown[char]
end

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

local printTable = function(table)
  print(table)
  for k, v in pairs(table) do
    print('  ', k, v)
  end
  print('')
end

local clearTable = function(table)
  for k in pairs(table) do
    table[k] = nil
  end
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

local sendKeyDown = function(modifiers, key)
  hs.eventtap.event.newKeyEvent(modifiers, key, true):post()
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


------------------------------
-- Event Listeners
------------------------------

superDuperModeActivationListener = hs.eventtap.new({ eventTypes.keyDown }, function(event)
  -- If KEY1 or KEY2 is pressed in conjuction with any modifier keys
  -- but not together
  -- (e.g., command+KEY1), then we're not activating smode.
  if not active and not (next(event:getFlags()) == nil) then
    return false
  end

  local char = event:getCharacters(true):lower()

  if isActivationKey(char) then

    -- log.d('--' .. char .. '--')
    keysDown[char] = true

    local onceComplete = once
    once = false

    -- prevent held key presses to be typed when exiting smode
    if cooldown then
      -- log.d('disabled')
      return true
    end

    if onceComplete then
      -- print('complete', char)
      return false
    end

    -- Temporarily suppress this activation key keystroke. At this point, we're not sure if
    -- the user intends to type an activation key, or if the user is attempting to activate
    -- smode. If the other key is pressed by the time the following function
    -- executes, then activate smode. Otherwise, trigger an ordinary
    -- activation key keystroke.
    if not active then
      quickKeysDown[char] = true
      -- log.d('delay')
      hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
        quickKeysDown[char] = false
        if quickKeysDown[other(char)] then
          -- log.d('delay:activate')
          active = true
        elseif not active then
          -- log.d('delay:not')
          once = true
          sendKeyDown({}, char)
          for i,key in pairs(delayedKeys) do
            -- print('SENDING', key)
            once = true
            -- sendKeyDown({}, key)
            hs.eventtap.keyStroke({}, key)
          end
          clearTable(delayedKeys)
        end
      end)
    end

    return true
  elseif quickKeysDown[KEY1] or quickKeysDown[KEY2] then

    -- queue the key to be inserted after the delay
    table.insert(delayedKeys, event:getKeyCode())
    -- print('DELAY', event:getKeyCode())

    return true
  end
end):start()

superDuperModeDeactivationListener = hs.eventtap.new({ eventTypes.keyUp }, function(event)

  local char = event:getCharacters(true):lower()

  if isActivationKey(char) then

    keysDown[char] = false

    -- if either key has been released, reset smode
    -- disable the use of the activation keys until both keys are release
    if active then
      -- log.d('disable')
      active = false
      cooldown = true
    end

    -- if both keys have been released, re-enable activation keys after a delay
    if cooldown and not isKeyDown(KEY1) and not isKeyDown(KEY2) then
      delay(function()
        -- log.d('enable')
        cooldown = false
      end)
    end
  end

end):start()

--------------------------------------------------------------------------------
-- Navigation
--------------------------------------------------------------------------------

superDuperModeNavListener = hs.eventtap.new({ eventTypes.keyDown }, function(event)
  if not active then
    return false
  end

  local mapping = findMapping(event:getCharacters(true):lower(), keys(event:getFlags()))
  if mapping then
    -- if toMod is not specified, pass whatever modifiers are pressed
    sendKeyDown(mapping.toMod or keys(event:getFlags()), mapping.to)
    return true
  end
end):start()
