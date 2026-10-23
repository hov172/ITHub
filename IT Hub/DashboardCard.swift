import SwiftUI

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let status: HealthStatus?
    let statusLabel: String
    let minimumContentHeight: CGFloat
    private let content: Content
    init(title: String, icon: String, status: HealthStatus? = nil, statusLabel: String = "", minimumContentHeight: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.status = status
        self.statusLabel = statusLabel; self.minimumContentHeight = minimumContentHeight
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(.blue).frame(width: 18)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                if let status { StatusIndicator(status: status, label: statusLabel) }
            }
            VStack(alignment: .leading, spacing: 8) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: minimumContentHeight, alignment: .topLeading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: false, vertical: true)
    }
}
