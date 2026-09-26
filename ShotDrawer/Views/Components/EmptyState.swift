import SwiftUI

struct EmptyState: View {
    let destination: SidebarDestination

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        destination == .inbox ? "Inbox Zero" : "Nothing Here Yet"
    }

    private var icon: String {
        destination == .inbox ? "checkmark.circle" : destination.systemImage
    }

    private var message: String {
        switch destination {
        case .inbox: "All screenshots handled."
        case .allScreenshots: "New screenshots will appear here in the next milestone."
        case .favorites: "Favorite screenshots will appear here."
        case .archive: "Archived screenshots will appear here."
        }
    }
}
