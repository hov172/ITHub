import SwiftUI
import AppKit
@main struct IconCheck {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let black = ImageRenderer(content: ComputerMark(color: .black)); black.scale = 2
        let green = ImageRenderer(content: ComputerMark(color: .green)); green.scale = 2
        guard let a = black.cgImage, let b = green.cgImage else { fatalError("Render failed") }
        precondition(a.width == b.width && a.height == b.height)
        let first = NSBitmapImageRep(cgImage: a), second = NSBitmapImageRep(cgImage: b)
        var filled = 0
        for x in 0..<a.width { for y in 0..<a.height {
            let aa = first.colorAt(x: x, y: y)!.alphaComponent
            let bb = second.colorAt(x: x, y: y)!.alphaComponent
            precondition(abs(aa-bb) < 0.02)
            if aa > 0.1 { filled += 1 }
        }}
        precondition(filled > 0)
        let preview = ImageRenderer(content: HStack(spacing: 20) { ComputerMark(color: .black); ComputerMark(color: .green) }.padding(12).background(.white))
        preview.scale = 4
        if let cg = preview.cgImage {
            try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/ithub-icon-match.png"))
        }
        print("Header and green icon dimensions and alpha masks match")
    }
}
