// Stages an Icon Composer .icon package for actool.
//
// Xcode 26.5's actool crashes on the SVG-backed .icon package produced for
// iGhostty. Icon Composer/actool accept PNG-backed packages, so this script
// rasterizes SVG layer masks to transparent PNGs and rewrites icon.json in a
// temporary copy. The source .icon package remains unchanged in the repo.
//
// Usage: swift scripts/normalize_icon_composer.swift <input.icon> <output.icon>
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: normalize_icon_composer.swift <input.icon> <output.icon>\n".data(using: .utf8)!)
    exit(1)
}

let inputURL = URL(fileURLWithPath: args[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: args[2], isDirectory: true)
let inputAssetsURL = inputURL.appendingPathComponent("Assets", isDirectory: true)
let outputAssetsURL = outputURL.appendingPathComponent("Assets", isDirectory: true)

let fm = FileManager.default
if fm.fileExists(atPath: outputURL.path) {
    try fm.removeItem(at: outputURL)
}
try fm.createDirectory(at: outputAssetsURL, withIntermediateDirectories: true)

func dict(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

func array(_ value: Any?) -> [[String: Any]] {
    value as? [[String: Any]] ?? []
}

struct SVGPath {
    var data: String
    var transform: AffineTransform?
}

final class SVGPathParser {
    private let tokens: [String]
    private var index = 0
    private var command: Character?
    private var current = NSPoint.zero

    init(_ data: String) {
        let pattern = #"([MmLlHhVvCcZz])|([-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let range = NSRange(data.startIndex..<data.endIndex, in: data)
        tokens = regex.matches(in: data, range: range).compactMap {
            Range($0.range, in: data).map { String(data[$0]) }
        }
    }

    func parse() -> NSBezierPath {
        let path = NSBezierPath()
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = first
                index += 1
            }
            guard let command else { break }
            switch command {
            case "M", "m": parseMove(command, into: path)
            case "L", "l": parseLine(command, into: path)
            case "H", "h": parseHorizontal(command, into: path)
            case "V", "v": parseVertical(command, into: path)
            case "C", "c": parseCurve(command, into: path)
            case "Z", "z":
                path.close()
                self.command = nil
            default:
                index += 1
            }
        }
        return path
    }

    private func hasNumber() -> Bool {
        index < tokens.count && !(tokens[index].first?.isLetter ?? false)
    }

    private func nextNumber() -> CGFloat? {
        guard hasNumber(), let value = Double(tokens[index]) else { return nil }
        index += 1
        return CGFloat(value)
    }

    private func nextPoint(relative: Bool) -> NSPoint? {
        guard let x = nextNumber(), let y = nextNumber() else { return nil }
        let point = NSPoint(x: x, y: y)
        return relative ? NSPoint(x: current.x + point.x, y: current.y + point.y) : point
    }

    private func parseMove(_ command: Character, into path: NSBezierPath) {
        guard let first = nextPoint(relative: command == "m") else { return }
        path.move(to: first)
        current = first
        self.command = command == "m" ? "l" : "L"
        while hasNumber() {
            guard let point = nextPoint(relative: command == "m") else { return }
            path.line(to: point)
            current = point
        }
    }

    private func parseLine(_ command: Character, into path: NSBezierPath) {
        while hasNumber() {
            guard let point = nextPoint(relative: command == "l") else { return }
            path.line(to: point)
            current = point
        }
    }

    private func parseHorizontal(_ command: Character, into path: NSBezierPath) {
        while hasNumber() {
            guard let x = nextNumber() else { return }
            current = NSPoint(x: command == "h" ? current.x + x : x, y: current.y)
            path.line(to: current)
        }
    }

    private func parseVertical(_ command: Character, into path: NSBezierPath) {
        while hasNumber() {
            guard let y = nextNumber() else { return }
            current = NSPoint(x: current.x, y: command == "v" ? current.y + y : y)
            path.line(to: current)
        }
    }

    private func parseCurve(_ command: Character, into path: NSBezierPath) {
        while hasNumber() {
            guard let cp1 = nextPoint(relative: command == "c"),
                  let cp2 = nextPoint(relative: command == "c"),
                  let end = nextPoint(relative: command == "c") else { return }
            path.curve(to: end, controlPoint1: cp1, controlPoint2: cp2)
            current = end
        }
    }
}

func svgTransform(from encoded: String) -> AffineTransform? {
    let values = encoded
        .split(separator: ",")
        .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    guard values.count == 6 else { return nil }
    return AffineTransform(
        m11: CGFloat(values[0]),
        m12: CGFloat(values[1]),
        m21: CGFloat(values[2]),
        m22: CGFloat(values[3]),
        tX: CGFloat(values[4]),
        tY: CGFloat(values[5])
    )
}

func svgPaths(from url: URL) throws -> [SVGPath] {
    let data = try String(contentsOf: url, encoding: .utf8)
    var paths: [SVGPath] = []
    var transforms: [AffineTransform] = []

    for line in data.components(separatedBy: .newlines) {
        if let matrixRange = line.range(of: #"transform="matrix\(([^)]*)\)""#, options: .regularExpression) {
            let match = String(line[matrixRange])
            let encoded = match
                .replacingOccurrences(of: #"transform="matrix("#, with: "")
                .replacingOccurrences(of: #")""#, with: "")
            if let transform = svgTransform(from: encoded) {
                transforms.append(transform)
            }
        }
        if line.contains("</g>"), !transforms.isEmpty {
            transforms.removeLast()
        }
        if let dRange = line.range(of: #"d="([^"]+)""#, options: .regularExpression) {
            let match = String(line[dRange])
            let data = String(match.dropFirst(3).dropLast(1))
            paths.append(SVGPath(data: data, transform: transforms.last))
        }
    }
    return paths
}

func renderSVGMask(from source: URL, to destination: URL, size: Int = 2000) throws {
    let paths = try svgPaths(from: source)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "iGhosttyIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let combined = NSBezierPath()
    for item in paths {
        let path = SVGPathParser(item.data).parse()
        if let transform = item.transform {
            path.transform(using: transform)
        }
        var placement = AffineTransform()
        placement.translate(x: 0, y: CGFloat(size))
        placement.scale(x: CGFloat(size) / 2000, y: -CGFloat(size) / 2000)
        path.transform(using: placement)
        combined.append(path)
    }
    NSColor.white.setFill()
    combined.fill()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "iGhosttyIcon", code: 2)
    }
    try png.write(to: destination)
}

func rewriteLayers(in groups: inout [[String: Any]]) throws {
    for groupIndex in groups.indices {
        var group = groups[groupIndex]
        var layers = array(group["layers"])
        for layerIndex in layers.indices {
            guard let imageName = layers[layerIndex]["image-name"] as? String else { continue }
            let source = inputAssetsURL.appendingPathComponent(imageName)
            if imageName.lowercased().hasSuffix(".svg") {
                let pngName = imageName.replacingOccurrences(of: ".svg", with: ".png", options: [.caseInsensitive])
                try renderSVGMask(from: source, to: outputAssetsURL.appendingPathComponent(pngName))
                layers[layerIndex]["image-name"] = pngName
            } else {
                try fm.copyItem(at: source, to: outputAssetsURL.appendingPathComponent(imageName))
            }
        }
        group["layers"] = layers
        groups[groupIndex] = group
    }
}

let jsonURL = inputURL.appendingPathComponent("icon.json")
let jsonData = try Data(contentsOf: jsonURL)
guard var root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
    FileHandle.standardError.write("invalid icon.json\n".data(using: .utf8)!)
    exit(1)
}

var groups = array(root["groups"])
try rewriteLayers(in: &groups)
// Xcode 26.5's command-line actool crashes on this SVG-origin icon when
// `features` advertises specular-location and a group uses string-valued
// `specular-specializations` ("inside"/"outside"). Preserve the effect as the
// supported boolean `specular` shape and keep the rest of the group effects.
root.removeValue(forKey: "features")
for groupIndex in groups.indices {
    if groups[groupIndex].removeValue(forKey: "specular-specializations") != nil {
        groups[groupIndex]["specular"] = true
    }
}
root["groups"] = groups

let outputJSON = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
try outputJSON.write(to: outputURL.appendingPathComponent("icon.json"))
print("normalized icon written to \(outputURL.path)")
