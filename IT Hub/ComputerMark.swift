import SwiftUI

/// Shared geometry for the header and the coloured menu-bar computer.
struct ComputerMark: View {
    var color: Color = .primary
    var body: some View {
        Image(systemName: "laptopcomputer")
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(color)
            .frame(width: 22, height: 18)
            .accessibilityHidden(true)
    }
}
