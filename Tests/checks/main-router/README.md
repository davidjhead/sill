# `main-router`

**Checks:** the Mac client's `MainRouter`: the main stream's frames go to the window they belong to across focus changes; the old stream's frames still on their way stay on the old window until the new stream's parameter sets come (differing from the old, or after the host said it switched); a window's first picture is its own keyframe; and a window the main stream draws into, or is about to, is reported so its side frames stay out

**Compiles:** `Sources/MacClient/MainRouter.swift` with StreamProtocol's sources as one module (`swiftc`)
