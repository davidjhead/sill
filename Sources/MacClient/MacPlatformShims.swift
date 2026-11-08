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
    /// Whether the picture can be shown now (KeyframeRecovery): the app is active.
    var pictureActive: Bool { NSApp.isActive }
}
