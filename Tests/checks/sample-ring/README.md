# `sample-ring`

**Checks:** the Viewer's sound ring (`SampleRing`): a second of samples for the format; frames out in order, channels interleaved, across the ring's end; silence and nothing taken before 40 ms are in, then playing; silence and a stop when it runs dry, playing again only from 40 ms; past 150 ms the oldest dropped down to 60 ms, a whole frame kept and the newest kept; an overrun keeps the newest; a channel past the format's is silent

**Compiles:** `Sources/MacClient/SampleRing.swift` with the check (`swiftc`, Foundation only)
