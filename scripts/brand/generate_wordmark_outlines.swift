#!/usr/bin/env swift

import CoreGraphics
import CoreText
import Foundation

struct Outline: Codable {
    let family: String
    let postScriptName: String
    let fontSize: Double
    let baseline: Double
    let areaWidth: Double
    let matrixWidth: Double
    let areaPath: String
    let matrixPath: String
}

guard CommandLine.arguments.count == 3 else {
    fputs("usage: generate_wordmark_outlines.swift FONT_FILE OUTPUT_JSON\n", stderr)
    exit(2)
}

let fontURL = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
var registrationError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL, .process, &registrationError) else {
    let message = registrationError?.takeRetainedValue().localizedDescription ?? "unknown error"
    fputs("font registration failed: \(message)\n", stderr)
    exit(1)
}

guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first else {
    fputs("font descriptor unavailable\n", stderr)
    exit(1)
}

let fontSize: CGFloat = 112
let baseline: CGFloat = 252
let font = CTFontCreateWithFontDescriptor(descriptor, fontSize, nil)

func number(_ value: CGFloat) -> String {
    let formatted = String(format: "%.3f", Double(value))
    return formatted.replacingOccurrences(of: ".000", with: "")
}

func outline(_ text: String) -> (path: String, width: CGFloat) {
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    var commands: [String] = []

    for run in runs {
        let count = CTRunGetGlyphCount(run)
        var glyphs = Array(repeating: CGGlyph(), count: count)
        var positions = Array(repeating: CGPoint.zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for index in 0..<count {
            guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
            var transform = CGAffineTransform(
                a: 1,
                b: 0,
                c: 0,
                d: -1,
                tx: positions[index].x,
                ty: baseline - positions[index].y
            )
            guard let path = glyphPath.copy(using: &transform) else { continue }
            path.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    commands.append("M\(number(element.points[0].x)) \(number(element.points[0].y))")
                case .addLineToPoint:
                    commands.append("L\(number(element.points[0].x)) \(number(element.points[0].y))")
                case .addQuadCurveToPoint:
                    commands.append(
                        "Q\(number(element.points[0].x)) \(number(element.points[0].y)) "
                            + "\(number(element.points[1].x)) \(number(element.points[1].y))"
                    )
                case .addCurveToPoint:
                    commands.append(
                        "C\(number(element.points[0].x)) \(number(element.points[0].y)) "
                            + "\(number(element.points[1].x)) \(number(element.points[1].y)) "
                            + "\(number(element.points[2].x)) \(number(element.points[2].y))"
                    )
                case .closeSubpath:
                    commands.append("Z")
                @unknown default:
                    break
                }
            }
        }
    }
    return (commands.joined(separator: " "), CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
}

let area = outline("Area")
let matrix = outline("Matrix")
let result = Outline(
    family: CTFontCopyFamilyName(font) as String,
    postScriptName: CTFontCopyPostScriptName(font) as String,
    fontSize: Double(fontSize),
    baseline: Double(baseline),
    areaWidth: Double(area.width),
    matrixWidth: Double(matrix.width),
    areaPath: area.path,
    matrixPath: matrix.path
)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var data = try encoder.encode(result)
data.append("\n".data(using: .utf8)!)
try data.write(to: output)
