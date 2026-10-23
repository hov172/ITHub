import SwiftUI
import Combine

@MainActor final class SupportActions: NSObject, ObservableObject, NSWindowDelegate {
    private var previewWindow: NSWindow?
    @Published var report = ""
    @Published var feedback = ""
    func showPreview(_ text: String) {
        report = text
        if previewWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 460), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "IT Hub — Support Details"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SupportPreviewView(actions: self))
            window.center()
            previewWindow = window
        }
        if let window = previewWindow { WindowPresentation.prepare(window) }
    }
    func closePreview() {
        if let window = previewWindow {
            window.close()
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, previewWindow === window else { return }
        window.contentView = nil
        previewWindow = nil
    }
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        feedback = NSPasteboard.general.setString(text, forType: .string) ? "Copied to clipboard" : "Could not copy"
    }
}
struct DeviceSupportCard: View {
    @ObservedObject var hardware: HardwareService
    let ram: String
    let makeReport: () -> String
    @StateObject private var actions = SupportActions()
    var body: some View {
        DashboardCard(title: "Device & Support", icon: "laptopcomputer") {
            if hardware.checking { Text("Reading hardware…").font(.caption).foregroundStyle(.secondary) }
            field("Device", hardware.snapshot?.deviceName)
            field("Model", hardware.snapshot?.model)
            field("Chip / RAM", hardware.snapshot?.chip.map { "\($0) · \(ram)" } ?? "Chip unavailable · \(ram)")
            HStack(alignment: .firstTextBaseline) {
                Text("Serial").foregroundStyle(.secondary)
                Spacer()
                Text(hardware.snapshot?.serial ?? "Unavailable").textSelection(.enabled)
                Button { if let serial = hardware.snapshot?.serial { actions.copy(serial) } } label: {
                    Image(systemName: "document.on.document")
                }.buttonStyle(.plain).foregroundStyle(.blue).disabled(hardware.snapshot?.serial == nil).accessibilityLabel("Copy serial number")
            }.font(.caption)
            HStack {
                Button { actions.copy(makeReport()) } label: {
                    Label("Copy Support Details", systemImage: "doc.on.clipboard")
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
                Spacer(minLength: 4)
                Button("Preview") { actions.showPreview(makeReport()) }
                    .buttonStyle(.plain).foregroundStyle(.blue)
            }.font(.caption)
            if !actions.feedback.isEmpty { Text(actions.feedback).font(.caption2).foregroundStyle(.secondary) }
        }
    }
    private func field(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value ?? "Unavailable").multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.caption)
    }
}

struct SupportPreviewView: View {
    @ObservedObject var actions: SupportActions
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Support Details").font(.title2.bold())
            Text("Review before copying into a ticket or chat.").font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(actions.report).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button("Copy report") { actions.copy(actions.report) }
                Text(actions.feedback).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { actions.closePreview() }.keyboardShortcut(.cancelAction)
            }
        }.padding(22).frame(minWidth: 500, minHeight: 360)
    }
}
