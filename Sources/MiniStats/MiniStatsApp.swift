import SwiftUI
import AppKit

struct MiniStatsApp: App {
    @StateObject private var monitor = Monitor()

    var body: some Scene {
        MenuBarExtra {
            Dashboard(monitor: monitor)
        } label: {
            Image(nsImage: MenuBarLabel.image(
                upload: MetricFormat.speed(monitor.network?.upload),
                download: MetricFormat.speed(monitor.network?.download),
                cpu: MetricFormat.percent(monitor.cpu)
            ))
            .accessibilityLabel("上传 \(MetricFormat.speed(monitor.network?.upload))，下载 \(MetricFormat.speed(monitor.network?.download))，CPU \(MetricFormat.percent(monitor.cpu))")
        }
        .menuBarExtraStyle(.window)
    }
}

private enum MenuBarLabel {
    // Render both rows as one template image so the menu bar preserves the layout.
    // Fixed columns and tabular digits keep the item stable as values change.
    static func image(upload: String, download: String, cpu: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 94, height: 22), flipped: true) { _ in
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
            func draw(_ text: String, in rect: NSRect, alignment: NSTextAlignment, font: NSFont) {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = alignment
                paragraph.lineBreakMode = .byClipping
                (text as NSString).draw(in: rect, withAttributes: [
                    .font: font,
                    .foregroundColor: NSColor.black,
                    .paragraphStyle: paragraph
                ])
            }
            draw("↑", in: NSRect(x: 0, y: 0, width: 10, height: 11), alignment: .center, font: font)
            draw("↓", in: NSRect(x: 0, y: 11, width: 10, height: 11), alignment: .center, font: font)
            draw(upload, in: NSRect(x: 11, y: 0, width: 46, height: 11), alignment: .left, font: font)
            draw(download, in: NSRect(x: 11, y: 11, width: 46, height: 11), alignment: .left, font: font)
            NSColor.black.withAlphaComponent(0.25).setFill()
            NSRect(x: 61, y: 3, width: 1, height: 16).fill()
            draw("CPU", in: NSRect(x: 65, y: 0, width: 29, height: 11), alignment: .center,
                 font: .systemFont(ofSize: 8, weight: .medium))
            draw(cpu, in: NSRect(x: 65, y: 11, width: 29, height: 11), alignment: .center, font: font)
            return true
        }
        image.isTemplate = true
        return image
    }
}
