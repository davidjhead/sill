# `mac-keys`

**Checks:** the Mac client's keys (`MacKeyMap`) against the host's (`KeyStrokes`): every keycode the client sends is a HID usage the host posts as that same keycode, every key the host can post is one the client sends, no two keycodes share a usage, a modifier key's flag is the one the host holds while it is down (caps lock its own), and the modifier bits on the wire are the host's flags with nothing else (fn, the numeric pad)

**Compiles:** `Sources/MacClient/MacKeyMap.swift` and `Sources/SillHost/KeyStrokes.swift` with StreamProtocol's sources as one module (`swiftc`)
