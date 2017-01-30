local log = hs.logger.new('init.lua', 'debug')
local eventtap = hs.eventtap
local eventTypes = hs.eventtap.event.types

-- Colemak remappings
local simKeyA = 's'
local simKeyB = 'r'

-- If simKeyA and simKeyB are *both* pressed within this time period, consider this to
-- mean that they've been pressed simultaneously, and therefore we should enter
-- Super Duper Mode.
local MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES = 0.02 -- 20 milliseconds

local superDuperMode = {
  reset = function(self)
    self.active = false
    self.isSDown = false
    self.isDDown = false
    self.ignoreNextS = false
    self.ignoreNextD = false
    self.modifiers = {}
  end,
}
superDuperMode:reset()

superDuperModeActivationListener = eventtap.new({ eventTypes.keyDown }, function(event)
  -- If simKeyA or simKeyB is pressed in conjuction with any modifier keys
  -- (e.g., command+simKeyA), then we're not activating Super Duper Mode.
  if not (next(event:getFlags()) == nil) then
    return false
  end

  local characters = event:getCharacters()

  if characters == simKeyA then
    if superDuperMode.ignoreNextS then
      superDuperMode.ignoreNextS = false
      return false
    end
    -- Temporarily suppress this simKeyA keystroke. At this point, we're not sure if
    -- the user intends to type an simKeyA, or if the user is attempting to activate
    -- Super Duper Mode. If simKeyB is pressed by the time the following function
    -- executes, then activate Super Duper Mode. Otherwise, trigger an ordinary
    -- simKeyA keystroke.
    superDuperMode.isSDown = true
    hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
      if superDuperMode.isDDown then
        superDuperMode.active = true
      else
        superDuperMode.ignoreNextS = true
        keyUpDown({}, simKeyA)
        return false
      end
    end)
    return true
  elseif characters == simKeyB then
    if superDuperMode.ignoreNextD then
      superDuperMode.ignoreNextD = false
      return false
    end
    -- Temporarily suppress this simKeyB keystroke. At this point, we're not sure if
    -- the user intends to type a simKeyB, or if the user is attempting to activate
    -- Super Duper Mode. If simKeyA is pressed by the time the following function
    -- executes, then activate Super Duper Mode. Otherwise, trigger an ordinary
    -- simKeyB keystroke.
    superDuperMode.isDDown = true
    hs.timer.doAfter(MAX_TIME_BETWEEN_SIMULTANEOUS_KEY_PRESSES, function()
      if superDuperMode.isSDown then
        superDuperMode.active = true
      else
        superDuperMode.ignoreNextD = true
        keyUpDown({}, simKeyB)
        return false
      end
    end)
    return true
  end
end):start()

superDuperModeDeactivationListener = eventtap.new({ eventTypes.keyUp }, function(event)
  local characters = event:getCharacters()
  if characters == simKeyA or characters == simKeyB then
    superDuperMode:reset()
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
  }

  local keystroke = charactersToKeystrokes[event:getCharacters(true)]
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
