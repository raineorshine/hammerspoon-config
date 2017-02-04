local log = hs.logger.new('init.lua', 'debug')
local eventtap = hs.eventtap
local eventTypes = hs.eventtap.event.types

-- Colemak remappings
local simKeyA = 'r'
local simKeyB = 's'

-- If simKeyA and simKeyB are *both* pressed within this time period, consider this to
-- mean that they've been pressed simultaneously, and therefore we should enter
-- Super Duper Mode.
local MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES = 00.02 -- 20 milliseconds

local superDuperMode = {
  reset = function(self)
    self.active = false
    self.disableActivationKeys = false
    self.wait = false
    self.allowNextAKey = false
    self.allowNextBKey = false
    self.modifiers = {}
  end,

  bothUp = function(self)
    return not self.isKeyADown and not self.isKeyBDown
  end,

  bothDown = function(self)
    return self.isKeyADown and self.isKeyBDown
  end,

  delay = function(self)
    self.wait = true
    hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
      self.wait = false
    end)
  end
}
superDuperMode.isKeyADown = false
superDuperMode.isKeyBDown = false
superDuperMode:reset()

superDuperModeActivationListener = eventtap.new({ eventTypes.keyDown }, function(event)
  -- If simKeyA or simKeyB is pressed in conjuction with any modifier keys
  -- but not together
  -- (e.g., command+simKeyA), then we're not activating Super Duper Mode.
  if not superDuperMode:bothDown() and not (next(event:getFlags()) == nil) then
    return false
  end

  local characters = event:getCharacters(true):lower()

  if characters == simKeyA then
    -- Temporarily suppress this simKeyA keystroke. At this point, we're not sure if
    -- the user intends to type an simKeyA, or if the user is attempting to activate
    -- Super Duper Mode. If simKeyB is pressed by the time the following function
    -- executes, then activate Super Duper Mode. Otherwise, trigger an ordinary
    -- simKeyA keystroke.

    -- log.d('--r--')
    superDuperMode.isKeyADown = true

    if superDuperMode.disableActivationKeys then
      -- log.d('disabled')
      superDuperMode.allowNextAKey = false
      return true
    end

    if superDuperMode.wait then
      -- log.d('wait')
      superDuperMode.allowNextAKey = false
      return true
    end

    if superDuperMode.allowNextAKey then
      -- log.d('allow')
      superDuperMode.allowNextAKey = false
      return false
    end

    hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
      -- log.d('yo')
      if superDuperMode.isKeyBDown then
        -- log.d('delay:activate')
        superDuperMode.active = true
      elseif not superDuperMode.wait and not superDuperMode.active then
        -- log.d('delay:not')
        superDuperMode.allowNextAKey = true
        keyUpDown({}, simKeyA)
      end
      return true
    end)
    return true
  elseif characters == simKeyB then

    -- log.d('--s--')

    -- Temporarily suppress this simKeyB keystroke. At this point, we're not sure if
    -- the user intends to type a simKeyB, or if the user is attempting to activate
    -- Super Duper Mode. If simKeyA is pressed by the time the following function
    -- executes, then activate Super Duper Mode. Otherwise, trigger an ordinary
    -- simKeyB keystroke.

    superDuperMode.isKeyBDown = true

    if superDuperMode.disableActivationKeys then
      superDuperMode.allowNextBKey = false
      return true
    end

    if superDuperMode.wait then
      -- log.d('wait')
      superDuperMode.allowNextBKey = false
      return true
    end

    if superDuperMode.allowNextBKey then
      -- log.d('allow')
      superDuperMode.allowNextBKey = false
      return false
    end

    hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
      if superDuperMode.isKeyADown then
        -- log.d('delay:activate')
        superDuperMode.active = true
      elseif not superDuperMode.wait and not superDuperMode.active then
        -- log.d('delay:not')
        superDuperMode.allowNextBKey = true
        keyUpDown({}, simKeyB)
      end
      return true
    end)
    return true
  end
end):start()

superDuperModeDeactivationListener = eventtap.new({ eventTypes.keyUp }, function(event)
  local characters = event:getCharacters(true):lower()

  -- track state of activation keys
  if characters == simKeyA then
    -- log.d('r up')
    superDuperMode.isKeyADown = false
  end

  if characters == simKeyB then
    -- log.d('s up')
    superDuperMode.isKeyBDown = false
  end

  -- if either key is been released, reset super duper mode
  -- disable the use of the activation keys
  if (superDuperMode.active and (characters == simKeyA or characters == simKeyB)) then
    superDuperMode:reset()
    -- log.d('disable')
    superDuperMode.disableActivationKeys = true
  end

  -- if both keys have been released, do not re-enable activation keys
  if not superDuperMode.wait and superDuperMode.disableActivationKeys and superDuperMode:bothUp() then
     superDuperMode.disableActivationKeys = false
     superDuperMode:delay()
     -- log.d('enable')
  end

end):start()

--------------------------------------------------------------------------------
-- Watch for key down/up events that represent modifiers in Super Duper Mode
--------------------------------------------------------------------------------
-- superDuperModeModifierKeyListener = eventtap.new({ eventTypes.keyDown, eventTypes.keyUp }, function(event)
--   if not superDuperMode.active then
--     return false
--   end

--   local charactersToModifers = {}
--   charactersToModifers['a'] = 'alt'
--   charactersToModifers['f'] = 'cmd'
--   charactersToModifers[' '] = 'shift'

--   local modifier = charactersToModifers[event:getCharacters()]
--   if modifier then
--     if (event:getType() == eventTypes.keyDown) then
--       superDuperMode.modifiers[modifier] = true
--     else
--       superDuperMode.modifiers[modifier] = nil
--     end
--     return true
--   end
-- end):start()

--------------------------------------------------------------------------------
-- Watch for h/j/k/l key down events in Super Duper Mode, and trigger the
-- corresponding arrow key events
--------------------------------------------------------------------------------
superDuperModeNavListener = eventtap.new({ eventTypes.keyDown }, function(event)
  if not superDuperMode.active then
    return false
  end

  local charactersToKeystrokes = {
    h = 'left',
    n = 'down',
    e = 'up',
    i = 'right',
    d = 'forwarddelete'
  }

  local keystroke = charactersToKeystrokes[event:getCharacters(true):lower():lower()]
  if keystroke then
    local modifiers = {}
    n = 0
    for flag, v in pairs(event:getFlags()) do
      n = n + 1
      modifiers[n] = flag
    end

    keyUpDown(modifiers, keystroke)
    return true
  end
end):start()

--------------------------------------------------------------------------------
-- Watch for i/o key down events in Super Duper Mode, and trigger the
-- corresponding key events to navigate to the previous/next tab respectively
--------------------------------------------------------------------------------
-- superDuperModeTabNavKeyListener = eventtap.new({ eventTypes.keyDown }, function(event)
--   if not superDuperMode.active then
--     return false
--   end

--   local charactersToKeystrokes = {
--     u = { {'cmd'}, '1' },          -- go to first tab
--     i = { {'cmd', 'shift'}, '[' }, -- go to previous tab
--     o = { {'cmd', 'shift'}, ']' }, -- go to next tab
--     p = { {'cmd'}, '9' },          -- go to last tab
--   }
--   local keystroke = charactersToKeystrokes[event:getCharacters()]

--   if keystroke then
--     keyUpDown(table.unpack(keystroke))
--     return true
--   end
-- end):start()
