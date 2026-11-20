import Foundation

/// The other Mac's sound waiting to play (AudioPlayer): interleaved samples in a ring made once per
/// format, so adding and playing only copy, and nothing is allocated or moved while the engine's render
/// thread waits on the player's lock. Playing starts once 40 ms are in, stops when it runs dry (until 40
/// ms are in again), and the oldest go when more than 150 ms wait, down to 60 ms, so the sound never
/// drifts behind the picture. A ring of a second holds far more than that; one that overruns drops its
/// oldest samples. Pure: Foundation only, checked with swiftc (Tests/checks/sample-ring).
struct SampleRing {
    let channels: Int
    /// Samples (not frames) in a millisecond: the rate in kHz times the channels.
    let perMs: Int
    private(set) var storage: [Float]
    private var readAt = 0
    private(set) var count = 0
    private(set) var playing = false

    /// A ring for `rate` Hz and `channels` channels, a second long.
    init(rate: Double, channels: Int) {
        self.channels = max(channels, 1)
        perMs = Int(rate / 1000) * self.channels
        storage = [Float](repeating: 0, count: max(Int(rate), 1) * self.channels)
    }

    /// Interleaved samples in, then the starting and catching-up rules.
    mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        let size = storage.count
        var writeAt = (readAt + count) % size
        for sample in samples {
            storage[writeAt] = sample
            writeAt += 1
            if writeAt == size { writeAt = 0 }
        }
        count += samples.count
        if count > size { readAt = (readAt + count - size) % size; count = size }   // overran: the oldest go
        if !playing, count >= 40 * perMs { playing = true }
        if count > 150 * perMs {                                                      // too far behind: catch up
            let keep = 60 * perMs - (60 * perMs) % channels
            readAt = (readAt + count - keep) % size
            count = keep
        }
    }

    /// The next frame's sample for `channel` without taking it (silence when not playing or empty).
    func peek(_ channel: Int) -> Float {
        guard playing, count >= channels, channel < channels else { return 0 }
        return storage[(readAt + channel) % storage.count]
    }

    /// One frame played: taken when there was one; running dry stops playing until 40 ms are in again.
    mutating func advance() {
        if playing, count >= channels {
            readAt = (readAt + channels) % storage.count
            count -= channels
        } else if playing {
            playing = false
        }
    }
}
