import Foundation

enum ActionKind: String, Sendable {
    case openLink, copyLink, copyText, copyImage, copyQRContent, copyError
    case showInFinder, favorite, unfavorite, archive, restore, delete
}

enum SuggestedActionRole: Sendable { case normal, destructive }

struct SuggestedAction: Identifiable, Equatable, Sendable {
    let kind: ActionKind
    let title: String
    let systemImage: String
    let priority: Int
    let role: SuggestedActionRole

    var id: ActionKind { kind }
    var isPrimary: Bool { priority >= 100 }
}
