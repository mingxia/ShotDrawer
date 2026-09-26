import Foundation

enum SidebarDestination: String, CaseIterable, Identifiable {
    case inbox
    case allScreenshots
    case favorites
    case archive

    var id: Self { self }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .allScreenshots: "All Screenshots"
        case .favorites: "Favorites"
        case .archive: "Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox: "tray"
        case .allScreenshots: "rectangle.stack"
        case .favorites: "star"
        case .archive: "archivebox"
        }
    }
}
