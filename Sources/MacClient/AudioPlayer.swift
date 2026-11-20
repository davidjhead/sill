import AVFoundation
import os
import StreamProtocol

/// The other Mac's sound (kind 33): the apps whose windows are open here, played on this Mac's
/// output. Packets of about 10 ms go into a short buffer that the engine pulls from: playback starts
/// once 40 ms are in and the buffer is cut back to 60 ms whenever it passes 150 ms, so the sound
/// never drifts behind the picture; an empty buffer plays silence. Play Sound in the status item
/// turns it off (the host then keeps the apps' sound). The sound comes compressed (AAC-ELD, about 96
/// kbit/s) unless `SillClient.plainAudio` is set; a host that cannot encode sends PCM, played as it
/// comes. Packets arrive on the network queue.
final class AudioPlayer: @unchecked Sendable {
    static let defaultsKey = "SillClient.playSound"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) == nil || UserDefaults.standard.bool(forKey: defaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    /// The codec asked for: AAC-ELD unless the default `SillClient.plainAudio` says plain PCM.
    static var codec: String? { UserDefaults.standard.bool(forKey: "SillClient.plainAudio") ? nil : AudioPacket.aacELD }

    private let lock = OSAllocatedUnfairLock()
    private var decoder: AACDecoder?
    /// The samples waiting to play (SampleRing), made once per format: under the lock, which the
    /// engine's render thread takes too, held only while samples are copied in or out.
    private var ring: SampleRing?
    private var rate: Double = 0           // the playing format: under the lock
    private var channels = 0
    private var engine: AVAudioEngine?     // main thread
    private var configObserver: NSObjectProtocol?

    /// One kind 33 payload. Network queue.
    func receive(_ payload: Data) {
        if let e = AudioPacket.unpackEncoded(payload) {
            if decoder?.matches(rate: e.sampleRate, channels: e.channels, cookie: e.cookie) != true {
                decoder = AACDecoder(rate: e.sampleRate, channels: e.channels, cookie: e.cookie)
            }
            decoder?.decode(e.packet) { samples in append(samples, rate: e.sampleRate, channels: e.channels) }
            return
        }
        guard let packet = AudioPacket.unpack(payload) else { return }
        let floats = packet.samples.map { Float($0) / 32767 }
        floats.withUnsafeBufferPointer { append($0, rate: packet.sampleRate, channels: packet.channels) }
    }

    /// Interleaved samples into the ring the engine plays from. Network queue.
    private func append(_ samples: UnsafeBufferPointer<Float>, rate packetRate: Double, channels packetChannels: Int) {
        guard packetRate >= 1000, packetChannels > 0 else { return }
        let changed = lock.withLock { () -> Bool in
            guard packetRate != rate || packetChannels != channels else { return false }
            rate = packetRate; channels = packetChannels
            ring = SampleRing(rate: packetRate, channels: packetChannels)
            return true
        }
        if changed {
            let r = packetRate, c = packetChannels
            DispatchQueue.main.async { [weak self] in self?.restart(rate: r, channels: c) }
        }
        lock.withLockUnchecked { ring?.append(samples) }   // synchronous: the pointer is used only within it
    }

    /// Stops playing and forgets what waited (a disconnect, Play Sound off). Main thread.
    func stop() {
        engine?.stop()
        engine = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        lock.withLock { ring = nil; rate = 0; channels = 0 }
    }

    private func restart(rate: Double, channels: Int) {
        engine?.stop()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: false)
        else { return }
        let source = AVAudioSourceNode(format: format) { [weak self] _, _, frames, list -> OSStatus in
            let out = UnsafeMutableAudioBufferListPointer(list)
            guard let self else { return noErr }
            self.lock.withLock {
                guard var ring = self.ring else { return }
                for f in 0..<Int(frames) {
                    for c in 0..<min(channels, out.count) {
                        guard let base = out[c].mData else { continue }
                        base.assumingMemoryBound(to: Float.self)[f] = ring.peek(c)
                    }
                    ring.advance()
                }
                self.ring = ring
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            self.engine = engine
            print("audio: playing \(Int(rate)) Hz, \(channels) channel\(channels == 1 ? "" : "s")")
        } catch {
            print("audio: could not start (\(error))")
            return
        }
        // The output changed (AirPods connected, another device chosen, a display's speakers gone): the
        // engine stops itself and stays silent until started again, as it now is, on the new output.
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.engine === engine else { return }
            print("audio: the output changed; starting again")
            self.restart(rate: rate, channels: channels)
        }
    }
}

/// AAC-ELD packets back to interleaved float samples. Network queue.
private final class AACDecoder {
    private let converter: AVAudioConverter
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let rate: Double, channels: Int, cookie: Data

    init?(rate: Double, channels: Int, cookie: Data) {
        var desc = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
                                               mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
                                               mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &desc),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else { return nil }
        converter.magicCookie = cookie
        self.input = input; self.output = output; self.converter = converter
        self.rate = rate; self.channels = channels; self.cookie = cookie
    }

    func matches(rate: Double, channels: Int, cookie: Data) -> Bool { rate == self.rate && channels == self.channels && cookie == self.cookie }

    /// Its buffers, kept between packets (a hundred a second): the compressed one grown when a packet
    /// is larger.
    private var compressed: AVAudioCompressedBuffer?
    private var pcm: AVAudioPCMBuffer?

    /// One packet decoded, its samples handed to `use` (interleaved), valid only during the call.
    func decode(_ packet: Data, _ use: (UnsafeBufferPointer<Float>) -> Void) {
        guard !packet.isEmpty else { return }   // nothing to copy: its bytes have no address
        if compressed == nil || compressed!.maximumPacketSize < packet.count {
            compressed = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: max(packet.count, 1536))
        }
        if pcm == nil { pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 1024) }
        guard let compressed, let pcm else { return }
        packet.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            compressed.data.copyMemory(from: base, byteCount: packet.count)
        }
        compressed.byteLength = UInt32(packet.count)
        compressed.packetCount = 1
        compressed.packetDescriptions?.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                              mDataByteSize: UInt32(packet.count))
        pcm.frameLength = 0
        var given = false
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, outStatus in
            if given { outStatus.pointee = .noDataNow; return nil }
            given = true
            outStatus.pointee = .haveData
            return compressed
        }
        guard status != .error, let data = pcm.floatChannelData else { return }
        use(UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength) * channels))
    }
}
