import Foundation
import Observation
import OctoKit
import SwiftUI

/// The pages of the account part of Settings, pushed on the Settings stack.
enum AccountRoute: Hashable, Codable {
    case shares
    case radioStations
    case family
    case admin
    case imports
}

extension View {
    /// The account pages a tab can open, each without the system's bar.
    func accountRoutes() -> some View {
        navigationDestination(for: AccountRoute.self) { route in
            Group {
                switch route {
                case .shares: SharesScreen()
                case .radioStations: RadioStationsScreen()
                case .family: FamilyScreen()
                case .admin: OctoAdminScreen()
                case .imports: ImportScreen()
                }
            }
            .detailPage()
        }
    }
}

/// The app-wide parts of the account: Family, lists shared in for Import, and the share card.
@MainActor
@Observable
final class Accounts {
    let family: FamilyHub
    let imports: ImportInbox
    /// The share card's request, while it shows.
    var sharing: ShareRequest?

    /// Opens the share card for a link to make.
    func share(_ request: ShareRequest) { sharing = request }

    init(session: Session, router: Router) {
        family = FamilyHub(session: session, router: router)
        imports = ImportInbox()
    }

    func start() {
        family.start()
    }
}
