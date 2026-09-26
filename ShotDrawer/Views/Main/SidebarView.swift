import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarDestination?
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarDestination.allCases) { destination in
                    Label(destination.title, systemImage: destination.systemImage)
                        .tag(destination)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ShotDrawer")
        .safeAreaInset(edge: .bottom) {
            Button {
                appState.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .accessibilityHint("Opens ShotDrawer settings")
        }
        .frame(minWidth: 190)
    }
}
