import Foundation

extension Bundle {
    /// The app's own resources. A SwiftPM build makes `Bundle.module` for the target's resources;
    /// in the Xcode app target they are in the app bundle itself.
    static var module: Bundle { .main }
}
