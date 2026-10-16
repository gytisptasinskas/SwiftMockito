import Foundation

/// Thread-safe exact stubbing and interaction storage for one mock.
public final class MockRuntime: @unchecked Sendable {
    private let lock = NSLock()
    private var stubEntries: [StubEntry] = []
    private var interactions: [RecordedInteraction] = []

    public init() {}

    /// Recorded dispatches in insertion order.
    public var recordedInvocations: [Invocation] {
        withLock { interactions.map(\.invocation) }
    }

    /// Begins an exact stub configuration. The response is installed when a
    /// `thenReturn`, `thenThrow`, or `thenAnswer` method is called.
    public func stub(for invocation: Invocation, arguments: ExactArguments) -> Stub {
        Stub { [self] response in
            withLock {
                stubEntries.append(StubEntry(invocation: invocation, arguments: arguments, response: response))
            }
        }
    }

    /// Records a dispatch without resolving a response.
    public func record(_ invocation: Invocation, arguments: ExactArguments? = nil) {
        withLock {
            appendInteraction(invocation, arguments: arguments)
        }
    }

    /// Records and resolves a normal dispatch using the newest exact stub.
    /// Unmatched `Void` members succeed; unmatched values throw
    /// `MissingStubError`.
    public func resolve<Value>(_ invocation: Invocation, arguments: ExactArguments?) throws -> Value {
        let stubs = withLock { () -> [StubEntry] in
            appendInteraction(invocation, arguments: arguments)
            return stubEntries
        }
        let response = arguments.flatMap { actualArguments in
            stubs.last(where: { $0.matches(invocation, arguments: actualArguments) })?.response
        }

        guard let response else {
            if Value.self == Void.self {
                return () as! Value
            }
            throw MissingStubError(invocation: invocation)
        }

        let value: Any
        switch response {
        case .value(let configuredValue):
            value = configuredValue
        case .failure(let error):
            throw error
        case .answer(let answer):
            value = try answer(ExactArguments.values(from: arguments))
        }

        guard let typedValue = value as? Value else {
            throw StubResponseTypeMismatchError(
                member: invocation.member,
                expectedType: String(reflecting: Value.self),
                actualType: String(reflecting: type(of: value))
            )
        }
        return typedValue
    }

    func interactionSnapshot(for mockID: UUID? = nil) -> [RecordedInteraction] {
        withLock {
            guard let mockID else {
                return interactions
            }
            return interactions.filter { $0.invocation.mockID == mockID }
        }
    }

    private func appendInteraction(_ invocation: Invocation, arguments: ExactArguments?) {
        interactions.append(
            RecordedInteraction(
                invocation: invocation,
                arguments: arguments
            )
        )
    }

    private func withLock<Value>(_ operation: () throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

struct RecordedInteraction {
    let invocation: Invocation
    let arguments: ExactArguments?
}

private struct StubEntry {
    let invocation: Invocation
    let arguments: ExactArguments
    let response: StubResponse

    func matches(_ actual: Invocation, arguments actualArguments: ExactArguments) -> Bool {
        invocation.mockID == actual.mockID
            && invocation.member == actual.member
            && invocation.argumentLabels == actual.argumentLabels
            && arguments == actualArguments
    }
}
