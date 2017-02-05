log = hs.logger.new('init.lua', 'debug')

sendKeyDown = function(modifiers, key)
  log.d('Sending keystroke:', hs.inspect(modifiers), key)
  hs.eventtap.event.newKeyEvent(modifiers, key, true):post()
end

require('super')

hs.notify.new({ title='Hammerspoon', informativeText='Ready to rock 🤘' }):send()
