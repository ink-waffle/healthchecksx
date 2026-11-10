import AppKit
import SwiftUI

/// The menu bar icon: everything worth knowing at a glance, without opening the panel.
struct MenuBarLabel: View {
    let store: ChecksStore

    var body: some View {
        Image(nsImage: Self.image(for: store.health))
    }

    static func image(for health: ChecksStore.Health) -> NSImage {
        switch health {
        case .down(let count): badge(symbol: "xmark", text: "\(count)", color: .systemRed, description: "\(count) down")
        case .late: badge(symbol: "exclamationmark", text: nil, color: .systemOrange, description: "Late")
        case .ok: template(symbol: "waveform.path.ecg.rectangle", description: "All healthy")
        case .unknown: template(symbol: "questionmark.circle.dashed", description: "Status unknown")
        }
    }

    private static func template(symbol: String, description: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)!.withSymbolConfiguration(configuration)!
        image.isTemplate = true
        return image
    }

    /// A filled pill rather than a tinted glyph, so it stands out among the menu bar's monochrome icons.
    private static func badge(symbol: String, text: String?, color: NSColor, description: String) -> NSImage {
        let height: CGFloat = 18
        let padding: CGFloat = 6
        let gap: CGFloat = 3
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy).applying(.init(paletteColors: [.white]))
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!.withSymbolConfiguration(configuration)!
        let label = text.map {
            NSAttributedString(string: $0, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.white])
        }
        let labelWidth = label.map { gap + ceil($0.size().width) } ?? 0
        let size = NSSize(width: max(height, padding * 2 + glyph.size.width + labelWidth), height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            let contentWidth = glyph.size.width + labelWidth
            let glyphX = (rect.width - contentWidth) / 2
            glyph.draw(in: NSRect(x: glyphX, y: (height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height))
            if let label {
                let labelSize = label.size()
                label.draw(at: NSPoint(x: glyphX + glyph.size.width + gap, y: (height - labelSize.height) / 2))
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = description
        return image
    }
}
