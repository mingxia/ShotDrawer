import AppKit
import SwiftUI

struct FloatingCardView: View {
    let item: ScreenshotItem
    let thumbnailURL: URL
    let presentation: ScreenshotPresentation
    let actions: [SuggestedAction]
    let additionalInboxCount: Int
    let feedback: String?
    let onAction: (SuggestedAction) -> Void
    let onHoverChanged: (Bool) -> Void

    private var primary: [SuggestedAction] { Array(actions.filter(\.isPrimary).prefix(3)) }
    private var secondary: [SuggestedAction] { actions.filter { !primary.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let image = NSImage(contentsOf: thumbnailURL) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary).overlay { Image(systemName: "photo") }
                }
            }
            .frame(height: 132).clipped()

            VStack(alignment: .leading, spacing: 8) {
                Label(presentation.typeName, systemImage: presentation.systemImage)
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(presentation.displayTitle).font(.headline).lineLimit(1)
                if let feedback { Text(feedback).font(.caption.weight(.semibold)).foregroundStyle(.green) }
                if additionalInboxCount > 0 {
                    Text("+\(additionalInboxCount) more in Inbox").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(primary) { action in
                        Button(action.title) { onAction(action) }.buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                    if !secondary.isEmpty {
                        Menu {
                            ForEach(secondary) { action in
                                Button(action.title, systemImage: action.systemImage) { onAction(action) }
                            }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                    }
                }
                .controlSize(.small)
            }.padding(12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor).opacity(0.5)) }
        .shadow(radius: 16, y: 6)
        .onHover(perform: onHoverChanged)
    }
}
