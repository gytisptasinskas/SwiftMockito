import Foundation

/// Reports an unmatched non-`Void` mock invocation.
public struct MissingStubError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let invocation: Invocation

    public init(invocation: Invocation) {
        self.invocation = invocation
    }

    public var description: String {
        "Missing stub for \(invocation.member) at \(invocation.sourceLocation.fileID):\(invocation.sourceLocation.line)."
    }

    public var errorDescription: String? {
        description
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
