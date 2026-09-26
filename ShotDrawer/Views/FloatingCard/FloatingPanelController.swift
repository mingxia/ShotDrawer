import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController {
    private weak var appState: AppState?
    private var panel: NonActivatingPanel?
    private var dismissTask: Task<Void, Never>?
    private var currentItem: ScreenshotItem?
    private var queue: [ScreenshotItem] = []
    private var feedback: String?

    init(appState: AppState) { self.appState = appState }

    func show(_ item: ScreenshotItem) {
        guard let appState, appState.showFloatingCard else { return }
        if let currentItem {
            if currentItem.id == item.id {
                self.currentItem = item
                render(item, additionalCount: queue.count)
            } else if let index = queue.firstIndex(where: { $0.id == item.id }) {
                queue[index] = item
            } else {
                queue.append(item)
                render(currentItem, additionalCount: queue.count)
            }
            return
        }
        currentItem = item
        feedback = nil
        render(item, additionalCount: queue.count)
    }

    private func render(_ item: ScreenshotItem, additionalCount: Int) {
        guard let appState else { return }
        let actions = appState.actionEngine.actions(for: item)
        let view = FloatingCardView(
            item: item,
            thumbnailURL: appState.thumbnailService.url(for: item.id),
            presentation: appState.presentationService.presentation(for: item),
            actions: actions,
            additionalInboxCount: additionalCount,
            feedback: feedback,
            onAction: { [weak self] action in self?.execute(action, item: item) },
            onHoverChanged: { [weak self] hovering in hovering ? self?.pauseDismissal() : self?.scheduleDismissal() }
        )
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: view)
        panel.setContentSize(NSSize(width: 360, height: 250))
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18; panel.animator().alphaValue = 1
        }
        self.panel = panel
        scheduleDismissal()
    }

    func dismiss() {
        dismissTask?.cancel(); dismissTask = nil; currentItem = nil; feedback = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18; panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            Task { @MainActor in self?.showNext() }
        })
    }

    private func showNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        show(next)
    }

    private func execute(_ action: SuggestedAction, item: ScreenshotItem) {
        guard let appState else { return }
        if action.kind == .delete, !confirmTrash() { return }
        Task {
            await appState.perform(action, for: item)
            if [.archive, .restore, .openLink, .delete].contains(action.kind) {
                dismiss()
            } else if [.copyText, .copyLink, .copyImage, .copyQRContent, .copyError].contains(action.kind) {
                feedback = "Copied"
                render(item, additionalCount: queue.count)
                scheduleDismissal(after: 0.8)
            }
        }
    }

    private func confirmTrash() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move this screenshot to Trash?"
        alert.informativeText = "The original screenshot will be moved to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makePanel() -> NonActivatingPanel {
        let panel = NonActivatingPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 20, y: visible.minY + 20))
    }

    private func pauseDismissal() { dismissTask?.cancel(); dismissTask = nil }
    private func scheduleDismissal(after seconds: Double = 6) {
        pauseDismissal()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
