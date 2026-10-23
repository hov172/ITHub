import SwiftUI

struct QuickActionsView: View {
    @ObservedObject var store: QuickActionStore
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Quick Actions").font(.subheadline.weight(.semibold))
                Spacer()
                if let running = store.runningScript {
                    ProgressView().controlSize(.small)
                    Text("Running \(running)…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if store.groups.isEmpty {
                Text("No actions configured. Add menu.json to /Library/Application Support/IT Hub or ~/Library/Application Support/IT Hub.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(store.groups) { group in groupTile(group) }
                }
            }
        }
    }
    private func groupTile(_ group: QuickActionGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.title).font(.caption.weight(.semibold))
            ForEach(group.actions) { action in
                if case .info(let text) = action.kind {
                    Text(text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Button { store.perform(action) } label: {
                        Label(action.title, systemImage: action.icon).font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain).foregroundStyle(.blue)
                    .disabled(store.runningScript != nil)
                    .help(actionHelp(action))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
    private func actionHelp(_ action: QuickAction) -> String {
        switch action.kind {
        case .info: ""
        case .link(let url): url.absoluteString
        case .app(let bundleID, let name): "Open \(name ?? bundleID ?? "app")"
        case .script(let command, _): "Run: \(command)"
        }
    }
}
