import Foundation
import StreamProtocol

/// The other Mac's word that the link can't carry the quality (`HostSettingsState.link`, "behind": it
/// withholds frames, so every picture that gets through is a whole new frame and they fall seconds
/// behind; picks and launches wait behind them too). The Viewer says so as the iPhone's stream screen
/// does (AwayCopy.callout), with the lower quality the Mac recommends a click away: the launcher's
/// banner and each window's toolbar (WindowToolbar). Gone as soon as the Mac reports the link keeping up.
enum LinkWarning {
    #if DEBUG
    /// The harness's report in place of the Mac's (`linkwarning behind|clear`): a test host on loopback
    /// never falls behind.
    static var testLink: LinkReport?
    #endif

    /// What to show now, or nil while the link keeps up. Main thread.
    static func callout(_ client: StreamClient) -> AwayCopy.Callout? {
        var link = client.settings.host?.link
        #if DEBUG
        if let testLink { link = testLink }
        #endif
        return AwayCopy.callout(link: link, away: client.settings.host?.away, mac: client.macName)
    }
}
