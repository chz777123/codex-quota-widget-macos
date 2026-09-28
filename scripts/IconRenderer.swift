import SwiftUI
import AppKit

// Apply the native icon container to the original artwork at every target size.
// Keep the full-bleed source unchanged and make the exterior genuinely transparent.
@main
struct IconRenderer {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3,
              let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
            fatalError("Usage: IconRenderer artwork.png output.iconset")
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let content = Image(nsImage: source)
            .resizable().interpolation(.high)
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .padding(100)
            .frame(width: 1024, height: 1024)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: content)
                renderer.isOpaque = false
                renderer.scale = CGFloat(size * scale) / 1024
                guard let image = renderer.cgImage else { fatalError("Render failed") }
                let bitmap = NSBitmapImageRep(cgImage: image)
                precondition(bitmap.hasAlpha)
                precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
                let suffix = scale == 2 ? "@2x" : ""
                let file = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                try bitmap.representation(using: .png, properties: [:])!.write(to: file)
            }
        }
        print("Rendered 10 icon sizes with continuous corners and verified transparent exterior.")
    }
}
