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
