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

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragment: String,
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        contains: [expectedFragment],
        includeLabels: includeLabels,
        maxDepth: maxDepth,
        file: file,
        line: line
    )
}

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragments: [String],
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let description = testMirrorDescription(of: value, includeLabels: includeLabels, maxDepth: maxDepth)
    assertTestDescription(description, contains: expectedFragments, file: file, line: line)
}

func assertTestMirrorDescription(
    of value: Any,
    doesNotContain unexpectedFragment: String,
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        doesNotContain: [unexpectedFragment],
        includeLabels: includeLabels,
        maxDepth: maxDepth,
        file: file,
        line: line
    )
}

func assertTestMirrorDescription(
    of value: Any,
    doesNotContain unexpectedFragments: [String],
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let description = testMirrorDescription(of: value, includeLabels: includeLabels, maxDepth: maxDepth)
    assertTestDescription(description, doesNotContain: unexpectedFragments, file: file, line: line)
}

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragments: [String],
    doesNotContain unexpectedFragments: [String],
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let description = testMirrorDescription(of: value, includeLabels: includeLabels, maxDepth: maxDepth)
    assertTestDescription(description, contains: expectedFragments, file: file, line: line)
    assertTestDescription(description, doesNotContain: unexpectedFragments, file: file, line: line)
}

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragment: String,
    doesNotContain unexpectedFragment: String,
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        contains: [expectedFragment],
        doesNotContain: [unexpectedFragment],
        includeLabels: includeLabels,
        maxDepth: maxDepth,
        file: file,
        line: line
    )
}

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragment: String,
    doesNotContain unexpectedFragments: [String],
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        contains: [expectedFragment],
        doesNotContain: unexpectedFragments,
        includeLabels: includeLabels,
        maxDepth: maxDepth,
        file: file,
        line: line
    )
}

func assertTestMirrorDescription(
    of value: Any,
    contains expectedFragments: [String],
    doesNotContain unexpectedFragment: String,
    includeLabels: Bool = true,
    maxDepth: Int? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestMirrorDescription(
        of: value,
        contains: expectedFragments,
        doesNotContain: [unexpectedFragment],
        includeLabels: includeLabels,
        maxDepth: maxDepth,
        file: file,
        line: line
    )
}

func assertTestDescription(
    _ description: String,
    contains expectedFragment: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestDescription(description, contains: [expectedFragment], file: file, line: line)
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
    doesNotContain unexpectedFragment: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    assertTestDescription(description, doesNotContain: [unexpectedFragment], file: file, line: line)
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

@MainActor
func waitForMainActorTestValue<Value>(
    attempts: Int = 100,
    delayNanoseconds: UInt64? = nil,
    failureMessage: () -> String,
    file: StaticString = #filePath,
    line: UInt = #line,
    value: () -> Value?
) async -> Value? {
    for _ in 0 ..< attempts {
        if let value = value() {
            return value
        }

        if let delayNanoseconds {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        } else {
            await Task.yield()
        }
    }

    XCTFail(failureMessage(), file: file, line: line)
    return nil
}

func waitForActorTestValue<Value>(
    on _: isolated some Actor,
    attempts: Int = 1000,
    delayNanoseconds: UInt64? = nil,
    failureMessage: () -> String,
    file: StaticString = #filePath,
    line: UInt = #line,
    value: () -> Value?
) async -> Value? {
    for _ in 0 ..< attempts {
        if let value = value() {
            return value
        }

        if let delayNanoseconds {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        } else {
            await Task.yield()
        }
    }

    XCTFail(failureMessage(), file: file, line: line)
    return nil
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
