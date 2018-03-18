A hammerspoon config for Simultaneous VI Mode (smode), i.e. pressing and holding `s` and `d` at the same time activates VI Mode globally.

## Feature Completion

- [x] press activation keys at same time -> should enter smode and enable navigation
- [x] tap activation keys several times -> should enter and exit smode smoothly
- [x] enter and exit smode and then press single activation key -> should type character
- [x] activate, release one, re-activate, release other -> should enter and exit smode smoothly without typing characters.
- [x] activation keys not doubled ('12x' does not produce '122x')
- [ ] press and hold one activation key, then press and hold the other -> should type characters
- [ ] press g1<enter> within MAX_TIME -> enter gets delayed until after activation key 1

## Development

```
hs.reload()
```
