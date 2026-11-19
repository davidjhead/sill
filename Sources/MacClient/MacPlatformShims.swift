import Foundation
import AppKit
import StreamProtocol

// Stage 1: the Mac client plays no sound yet. These are the few members the shared StreamClient calls on
// the iOS app's AudioOutput (AVAudioSession, UIKit), as no-ops, until the Mac player (AudioPlayer.swift)
// is moved to kind 43 (docs/mac-client-prd.md, 1.3).
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
    var macHasSound: Bool { false }
    func frameForSound(_ header: StreamHeader) {}
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
