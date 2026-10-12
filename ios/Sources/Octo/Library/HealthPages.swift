import OctoKit
import SwiftUI

/// Library health: what could be better in the library, check by check.
struct HealthPage: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Library health").padding(.top, detailTopGap)
                LibrarySpinner()
            }
        }
        .barClearance()
    }
}

/// One check's findings.
struct HealthCheckPage: View {
    let check: String

    var body: some View {
        ScrollView {
            ScreenTitle(check).padding(.top, detailTopGap)
        }
        .barClearance()
    }
}

/// The server's trash.
struct RecentlyRemovedPage: View {
    var body: some View {
        ScrollView {
            ScreenTitle("Recently removed").padding(.top, detailTopGap)
        }
        .barClearance()
    }
}
