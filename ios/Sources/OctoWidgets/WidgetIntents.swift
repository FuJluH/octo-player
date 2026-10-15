import AppIntents
import OctoIntents

/// The intents the widgets' buttons take from OctoIntents.
struct OctoWidgetIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [OctoIntentsPackage.self] }
}
