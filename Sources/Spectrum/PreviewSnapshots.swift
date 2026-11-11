import CoreGraphics
import Foundation
import ImageIO
import SpectrumCore

@MainActor
enum PreviewSnapshots {
    enum SnapshotError: Error, CustomStringConvertible {
        case image(String)
        case changed(String, Double?)

        var description: String {
            switch self {
            case .image(let name): "couldn't read preview \(name)"
            case .changed(let name, .some(let difference)):
                "preview \(name) changed by \(String(format: "%.2f%%", difference * 100))"
            case .changed(let name, .none): "preview \(name) changed size or is missing"
            }
        }
    }

    private static let names = [
        "AppIcon", "compact-pill", "expanded-waiting", "permission", "agents-office-night",
        "agents-boss",
    ]
    private static let tolerance = 0.018

    static func run(reference: URL, update: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "spectrum-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try PreviewRenderer.render(to: directory)
        var actual: [String: PreviewFingerprint] = [:]
        for name in names {
            actual[name] = try fingerprint(directory.appending(path: name + ".png"), name: name)
        }
        if update {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try (encoder.encode(actual) + Data("\n".utf8)).write(to: reference, options: .atomic)
            return
        }
        let expected = try JSONDecoder().decode(
            [String: PreviewFingerprint].self, from: Data(contentsOf: reference))
        for name in names {
            let difference = expected[name].flatMap { actual[name]?.difference(from: $0) }
            guard let difference, difference <= tolerance else {
                throw SnapshotError.changed(name, difference)
            }
            print("\(name): \(String(format: "%.2f%%", difference * 100)) mean difference")
        }
    }

    private static func fingerprint(_ url: URL, name: String) throws -> PreviewFingerprint {
        let columns = 64
        let rows = 32
        let bytesPerRow = columns * 4
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { throw SnapshotError.image(name) }
        context.interpolationQuality = .medium
        let bounds = CGRect(x: 0, y: 0, width: columns, height: rows)
        context.clear(bounds)
        context.draw(image, in: bounds)
        return PreviewFingerprint(
            width: image.width, height: image.height,
            pixels: Data(bytes: data, count: bytesPerRow * rows))
    }
}
