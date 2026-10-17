import Foundation

/// A throwing member was called with arguments that no stub matches.
public struct MissingStubError: Error, Sendable, CustomStringConvertible {
    public let mock: String
    public let member: String
    public let arguments: [String]
    public let configuredStubs: [String]
    public let site: CallSite

    public var description: String {
        var lines = ["No stub for \(mock).\(member) with arguments (\(arguments.joined(separator: ", ")))."]
        if configuredStubs.isEmpty {
            lines.append("No stubs configured for \(member).")
        } else {
            lines.append("Configured stubs for \(member):")
            lines += configuredStubs.map { "  \($0)" }
        }
        lines.append("Mock created at \(site).")
        return lines.joined(separator: "\n")
    }
}

/// A stub or verification used an argument that exact matching cannot compare.
public struct UnsupportedExactMatchingError: Error, Sendable, CustomStringConvertible {
    public let member: String
    public let position: Int
    public let typeName: String

    public init(member: String, position: Int, typeName: String) {
        self.member = member
        self.position = position
        self.typeName = typeName
    }

    public var description: String {
        "\(member) argument \(position) has type \(typeName), which is neither Equatable nor a class; exact matching cannot compare it."
    }
}

/// Recording a non-throwing member needed a placeholder value that SwiftMockito cannot build.
public struct MissingDummyError: Error, Sendable, CustomStringConvertible {
    public let typeName: String
    public let member: String

    public init(typeName: String, member: String) {
        self.typeName = typeName
        self.member = member
    }

    public var description: String {
        "No dummy value for \(typeName), needed while recording \(member). Call provideDummy(_:) with a \(typeName) value before stubbing or verifying this member."
    }
}
