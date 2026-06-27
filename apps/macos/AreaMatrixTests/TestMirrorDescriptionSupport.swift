import XCTest

func testMirrorDescription(
    of value: Any,
    includeLabels: Bool = true,
    maxDepth: Int? = nil
) -> String {
    var lines: [String] = []
    appendTestMirrorDescription(of: value, to: &lines, depth: 0, includeLabels: includeLabels, maxDepth: maxDepth)
    return lines.joined(separator: "\n")
}

func assertTestDescription(
    _ description: String,
    contains expectedFragments: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for fragment in expectedFragments {
        XCTAssertTrue(
            description.contains(fragment),
            "Expected test description to contain: \(fragment)",
            file: file,
            line: line
        )
    }
}

func assertTestDescription(
    _ description: String,
    doesNotContain unexpectedFragments: [String],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for fragment in unexpectedFragments {
        XCTAssertFalse(
            description.contains(fragment),
            "Expected test description not to contain: \(fragment)",
            file: file,
            line: line
        )
    }
}

private func appendTestMirrorDescription(
    of value: Any,
    to lines: inout [String],
    depth: Int,
    includeLabels: Bool,
    maxDepth: Int?
) {
    if let maxDepth, depth >= maxDepth {
        return
    }

    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if includeLabels, let label = child.label {
            lines.append(label)
        }
        appendTestMirrorDescription(
            of: child.value,
            to: &lines,
            depth: depth + 1,
            includeLabels: includeLabels,
            maxDepth: maxDepth
        )
    }
}
