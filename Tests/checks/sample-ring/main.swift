import Foundation

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func add(_ r: inout SampleRing, _ samples: [Float]) { samples.withUnsafeBufferPointer { r.append($0) } }
/// Plays `frames` frames, each channel's sample, as the render thread does.
func play(_ r: inout SampleRing, _ frames: Int) -> [Float] {
    var out: [Float] = []
    for _ in 0..<frames { for c in 0..<r.channels { out.append(r.peek(c)) }; r.advance() }
    return out
}

// 1 kHz, 2 channels: 2 samples a millisecond, a ring of 2000 samples.
do {
    var r = SampleRing(rate: 1000, channels: 2)
    check(r.perMs == 2 && r.storage.count == 2000, "a second's ring, 2 samples a millisecond")
    add(&r, (0..<78).map(Float.init))
    check(!r.playing, "not playing under 40 ms (78 samples)")
    check(play(&r, 1) == [0, 0] && r.count == 78, "silence, nothing taken, before it plays")
    add(&r, [78, 79])
    check(r.playing, "playing from 40 ms (80 samples)")
    check(play(&r, 3) == [0, 1, 2, 3, 4, 5], "frames in order, channels interleaved")
    check(r.count == 74, "what was played is taken: \(r.count)")
}

// Across the ring's end: what goes in comes out in order.
do {
    var r = SampleRing(rate: 1000, channels: 1)   // 1 sample a ms, a ring of 1000
    add(&r, (0..<100).map(Float.init))
    _ = play(&r, 90)                              // the read point near the start, 10 waiting
    var all: [Float] = []
    for k in 0..<12 {                             // 12 × 90 samples: past the end of the ring several times
        add(&r, (0..<90).map { Float(1000 + k * 90 + $0) })
        all += play(&r, 90)
    }
    let expected = (90..<100).map(Float.init) + (0..<(12 * 90 - 10)).map { Float(1000 + $0) }
    check(all == expected, "in order across the ring's end: first wrong at \(zip(all, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? -1)")
}

// Running dry: silence, and playing again only from 40 ms.
do {
    var r = SampleRing(rate: 1000, channels: 1)
    add(&r, [Float](repeating: 1, count: 40))
    _ = play(&r, 40)
    check(play(&r, 1) == [0] && !r.playing, "dry: silence and not playing")
    add(&r, [Float](repeating: 2, count: 39))
    check(!r.playing && play(&r, 1) == [0], "not again under 40 ms")
    add(&r, [2])
    check(r.playing && play(&r, 1) == [2], "again from 40 ms")
}

// Too far behind: past 150 ms the oldest go, down to 60 ms, a whole frame kept.
do {
    var r = SampleRing(rate: 1000, channels: 2)
    add(&r, (0..<300).map(Float.init))           // exactly 150 ms: kept
    check(r.count == 300, "150 ms kept whole: \(r.count)")
    add(&r, [300, 301])                           // past it
    check(r.count == 120, "cut to 60 ms: \(r.count)")
    check(play(&r, 1) == [182, 183], "the newest kept, the oldest gone: \(play(&r, 0))")
}

// Overrun: more than the ring holds at once keeps the newest.
do {
    var r = SampleRing(rate: 1000, channels: 1)
    add(&r, (0..<2500).map(Float.init))
    check(r.count == 60, "an overrun ends at 60 ms like any catch-up: \(r.count)")
    check(play(&r, 1) == [2440], "the newest kept: \(r.peek(0))")
}

// A channel past the format's: silence.
do {
    var r = SampleRing(rate: 1000, channels: 1)
    add(&r, [Float](repeating: 5, count: 50))
    check(r.peek(1) == 0 && r.peek(0) == 5, "only the format's channels")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
