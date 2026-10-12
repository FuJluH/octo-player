import Foundation
import SwiftUI
import WidgetKit

/// Octo's home screen widgets: the song that is on, and four ways to start music.
@main
struct OctoWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingWidget()
        QuickPlayWidget()
    }
}

/// What every widget shares: Octo's colors, and how its buttons reach the app.
enum WidgetLook {
    static let background = Color(red: 0x0C / 255, green: 0x0C / 255, blue: 0x0D / 255)
    static let coverTile = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1B / 255)
    static let accent = Color(red: 0x97 / 255, green: 0xB1 / 255, blue: 0xB9 / 255)
    static let tile = Color.white.opacity(0.08)
    static let secondary = Color.white.opacity(0.7)

    /// Whether this build carries the App Intents metadata the system needs to run a button's
    /// intent. Without it the buttons are links that open Octo to do the same.
    static let intentsReady = Bundle.main.url(forResource: "Metadata", withExtension: "appintents") != nil
}
