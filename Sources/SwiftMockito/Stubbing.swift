import Foundation

/// A response configuration for one exact invocation pattern.
public struct Stub {
    private let install: (StubResponse) -> Void

    init(install: @escaping (StubResponse) -> Void) {
        self.install = install
    }

    /// Configures a typed value response.
    @discardableResult
    public func thenReturn<Value>(_ value: Value) -> Stub {
        install(.value(value))
        return self
    }

    /// Configures an error response.
    @discardableResult
    public func thenThrow<Failure: Error>(_ error: Failure) -> Stub {
        install(.failure(error))
        return self
    }

    /// Configures an answer that receives the actual exact arguments.
    @discardableResult
    public func thenAnswer<Value>(_ answer: @escaping ([Any]) throws -> Value) -> Stub {
        install(.answer { arguments in
            try answer(arguments) as Any
        })
        return self
    }

    /// Configures an answer that does not need the invocation arguments.
    @discardableResult
    public func thenAnswer<Value>(_ answer: @escaping () throws -> Value) -> Stub {
        install(.answer { _ in
            try answer() as Any
        })
        return self
    }
}

enum StubResponse {
    case value(Any)
    case failure(any Error)
    case answer(([Any]) throws -> Any)
}

/// Reports an attempt to resolve a stub whose configured result type differs
/// from the generated member's declared result type.
public struct StubResponseTypeMismatchError: Error, Sendable, Equatable, CustomStringConvertible, LocalizedError {
    public let member: String
    public let expectedType: String
    public let actualType: String

    public init(member: String, expectedType: String, actualType: String) {
        self.member = member
        self.expectedType = expectedType
        self.actualType = actualType
    }

    public var description: String {
        "Stub for \(member) returned \(actualType), expected \(expectedType)."
    }

    public var errorDescription: String? {
        description
    }
}
