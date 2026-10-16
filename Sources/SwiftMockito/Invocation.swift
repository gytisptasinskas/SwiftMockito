import Foundation

/// Identifies whether generated mock code is capturing configuration or dispatching a real call.
public enum InvocationPhase: Sendable, Equatable {
    case capture
    case dispatch
}

/// Immutable metadata describing one generated mock-member invocation.
public struct Invocation: Sendable, Equatable {
    /// The mock instance that received the invocation.
    public let mockID: UUID

    /// The fully labelled member identity, such as `fetch(id:)`.
    public let member: String

    /// The argument labels in declaration order.
    public let argumentLabels: [String]

    /// The source location of the generated call.
    public let sourceLocation: SourceLocation

    /// Whether this invocation captures configuration or dispatches a real call.
    public let phase: InvocationPhase

    public init(
        mockID: UUID,
        member: String,
        argumentLabels: [String],
        sourceLocation: SourceLocation = .init(),
        phase: InvocationPhase
    ) {
        self.mockID = mockID
        self.member = member
        self.argumentLabels = argumentLabels
        self.sourceLocation = sourceLocation
        self.phase = phase
    }
}

extension Invocation {
    /// A stable source position for mock diagnostics.
    public struct SourceLocation: Sendable, Equatable {
        public let fileID: String
        public let line: Int

        public init(fileID: String = #fileID, line: Int = #line) {
            self.fileID = fileID
            self.line = line
        }
    }
}
