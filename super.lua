--[[

Simultaneous VI Mode (smode)

Ad hoc testing guidelines:
  - press activation keys at same time -> should enter smode and enable navigation
  - tap activate keys several times -> should enter and exit smode smoothly
  - activate, hold, release one, hold, release other -> should exit smode smoothly
  - enter and exit smode and then press single activation key -> should type character
  - once activated, release one and then the other without releasing both -> should stay in smode
  - press and hold one activation key, then press and hold the other -> should type characters

--]]

------------------------------
-- Constants
------------------------------

-- Colemak remappings
local KEY1 = 'r'
local KEY2 = 's'

local mappings = {
  h = 'left',
  n = 'down',
  e = 'up',
  i = 'right',
  d = 'forwarddelete'
}

-- If KEY1 and KEY2 are *both* pressed within this time period, consider this to
-- mean that they've been pressed simultaneously, and therefore we should enter
-- smode.
local MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES = 00.02 -- 20 milliseconds

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
      -- log.d('once')
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
        end
      end)
    end

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
  local mappedKey = mappings[event:getCharacters(true):lower()]
  if active and mappedKey then
    sendKeyDown(keys(event:getFlags()), mappedKey)
    return true
  end
end):start()
