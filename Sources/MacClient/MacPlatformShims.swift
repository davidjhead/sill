import Foundation
import AppKit
import StreamProtocol

// The few members the shared StreamClient calls on the iOS app's AudioOutput (AVAudioSession, UIKit), as
// no-ops: the Mac's sound (kind 43) goes to Sill Viewer's own player instead (AudioPlayer.swift, through
// `onAudio`; docs/mac-client-prd.md, 1.3).
final class AudioOutput {
    var onRouteMuted: (() -> Void)?
    init(refresh: Double) {}
    func setMuted(_ on: Bool) {}
    func sessionStarted(away: Bool) {}
    func sessionEnded() {}
    func setAway(_ on: Bool) {}
    func setStreamFPS(_ fps: Int) {}
    func rtt(median ms: Int?) {}
    func takeSecond() -> (behindMs: Int?, late: Int)? { nil }
    func setPictureInPicture(_ state: PictureInPicturePolicy.State) {}
}

extension StreamClient {
    static let soundMutedKey = "Sill.soundMuted"
    /// The other Mac has sound: its settings carry Send Audio, on or off (as the iPhone app reads it).
    var macHasSound: Bool { settings.displayed?.sendAudio != nil }
    func frameForSound(_ header: StreamHeader) {}
    /// A kind 43 on the session's connection, to Sill Viewer's player as it came. Network queue.
    func receiveAudio(_ header: StreamHeader, _ data: Data) { onAudio?(data) }
}

extension StreamClient {
    /// Whether the picture's window is the one in front (the tile's picture is taken only then).
    var pictureWindowInFront: Bool { NSApp.isActive && displayView.window?.isKeyWindow == true }
}

extension StreamClient {
    /// This window's picture can be shown now (KeyframeRecovery): the app is active.
    var sceneInFront: Bool { NSApp.isActive }
}

// Picture in Picture (#291) and the device's auto-lock hold are iPhone and iPad features: the Mac client
// has neither, so the shared StreamClient meets these no-ops.
final class PictureInPicture {
    static let supported = false
    init(client: StreamClient) {}
    func end(_ ending: PictureInPicturePolicy.Ending, why: String) {}
}

final class PictureInPictureHub {
    static let shared = PictureInPictureHub()
    func used(_ client: StreamClient) {}
    func update() {}
}

final class DeviceIdleTimer {
    static let shared = DeviceIdleTimer()
    func used() {}
    func update() {}
}
