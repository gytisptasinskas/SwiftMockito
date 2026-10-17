import Foundation

/// Used by generated mocks; don't call it directly.
///
/// What a generated member does, as recorded during capture.
public struct Effects: OptionSet, Sendable {
    /// Used by generated mocks; don't call it directly.
    public let rawValue: Int
    /// Used by generated mocks; don't call it directly.
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// Used by generated mocks; don't call it directly. The member is `async`.
    public static let async = Effects(rawValue: 1 << 0)
    /// Used by generated mocks; don't call it directly. The member `throws`.
    public static let throwing = Effects(rawValue: 1 << 1)
}

struct StubTarget {
    let runtime: MockRuntime
    let member: String
    let key: [Argument]
    let argumentsType: Any.Type
    let effects: Effects
    /// The member's declared return type, which `thenReturn`/`thenAnswer` must match.
    let returnType: Any.Type
    let site: CallSite

    var qualifiedMember: String { "\(runtime.mockName).\(member)" }
}

struct StoredAnswer {
    let argumentsType: Any.Type
    let isAsync: Bool
    let sync: ((Any) throws -> Any)?
    let async: (nonisolated(nonsending) (Any) async throws -> Any)?
}

enum StoredResponse {
    case values([Any])
    case error(any Error)
    case answer(StoredAnswer)
}

/// Configures the response of one recorded call.
///
/// ``when(_:fileID:filePath:line:column:)`` and ``when(isolation:fileID:filePath:line:column:_:)``
/// return a `Stub`. Finish it with ``thenReturn(_:)``, ``thenThrow(_:)`` or `thenAnswer(_:)`:
///
/// ```swift
/// when(client.cached(id: "42")).thenReturn(.fixture)
/// when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)
/// ```
///
/// `R` is the member's return type. `Failure` is `Never` for members that cannot throw, so
/// ``thenThrow(_:)`` is unavailable for them at compile time.
///
/// Each `then…` call installs one stub and returns the same `Stub`. A misused stub, such as a
/// `thenAnswer` whose parameter types differ from the member's, is reported at the `when` line
/// and installs nothing.
public struct Stub<R, Failure: Error> {
    let target: StubTarget?

    init(target: StubTarget?) { self.target = target }

    /// Returns `values` in order on successive matching calls; the last one repeats.
    ///
    /// ```swift
    /// when(client.cached(id: "42")).thenReturn(nil, .fixture)
    /// client.cached(id: "42")   // nil
    /// client.cached(id: "42")   // .fixture
    /// client.cached(id: "42")   // .fixture
    /// ```
    ///
    /// Passing no values is reported as a misuse and installs nothing.
    ///
    /// - Parameter values: One value, or several to return in sequence.
    /// - Returns: This stub.
    @discardableResult
    public func thenReturn(_ values: R...) -> Self {
        guard let target else { return self }
        guard !values.isEmpty else {
            Reporter.fail("thenReturn for \(target.qualifiedMember) needs at least one value.", at: target.site)
            return self
        }
        guard checkReturnType(of: target) else { return self }
        target.runtime.install(StubRecord(target: target, response: .values(values)))
        return self
    }

    /// Reports and returns false when the stub's `R` is not the member's return type. Such a
    /// stub would otherwise install and later trap at `as! R` when the real call is answered.
    fileprivate func checkReturnType(of target: StubTarget) -> Bool {
        guard ObjectIdentifier(R.self) != ObjectIdentifier(target.returnType) else { return true }
        Reporter.fail(
            "when: the closure evaluates to \(typeDescription(R.self)) but \(target.qualifiedMember) returns \(typeDescription(target.returnType)); put only the member call in the closure (no try?, ??, or conversions).",
            at: target.site
        )
        return false
    }

    /// Computes the result from the call's arguments.
    ///
    /// The closure receives the arguments in declaration order and returns the result. It may
    /// throw only when the member can, and the error is thrown to the caller:
    ///
    /// ```swift
    /// when(client.cached(id: "42")).thenAnswer { id in User(id: id, name: "Gytis") }
    /// when { try client.save(.fixture) }.thenAnswer { (user: User) in
    ///     if user.name.isEmpty { throw ClientError.offline }
    /// }
    /// ```
    ///
    /// Annotate the parameter types when a member takes a callback. The closure runs on
    /// whatever thread or actor the code under test calls the mock from.
    ///
    /// - Parameter body: A closure that takes the member's arguments and returns its result.
    /// - Returns: This stub.
    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) throws(Failure) -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: false, sync: { packed in
            let args = packed as! (repeat each A)   // checked against argumentsType when installed
            return try body(repeat each args)
        }, async: nil))
    }

    /// Computes the result of an `async` member from the call's arguments.
    ///
    /// The closure may `await`, and may throw only when the member can:
    ///
    /// ```swift
    /// when { try await client.fetch(id: "42") }.thenAnswer { (id: String) async throws in
    ///     try await Task.sleep(for: .milliseconds(10))
    ///     return User(id: id, name: "Gytis")
    /// }
    /// ```
    ///
    /// An `async` answer for a synchronous member is reported as a misuse and installs nothing.
    ///
    /// - Parameter body: An `async` closure that takes the member's arguments and returns its result.
    /// - Returns: This stub.
    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) async throws(Failure) -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: true, sync: nil, async: { packed in
            let args = UncheckedSendable(packed as! (repeat each A))
            return try await body(repeat each args.value)
        }))
    }

    fileprivate func install(_ answer: StoredAnswer) -> Self {
        guard let target else { return self }
        guard ObjectIdentifier(answer.argumentsType) == ObjectIdentifier(target.argumentsType) else {
            Reporter.fail(
                "thenAnswer for \(target.qualifiedMember) takes \(parenthesized(answer.argumentsType)) but the member passes \(parenthesized(target.argumentsType)).",
                at: target.site
            )
            return self
        }
        guard !answer.isAsync || target.effects.contains(.async) else {
            Reporter.fail("thenAnswer for \(target.qualifiedMember) is async but the member is synchronous.", at: target.site)
            return self
        }
        guard checkReturnType(of: target) else { return self }
        target.runtime.install(StubRecord(target: target, response: .answer(answer)))
        return self
    }
}

extension Stub where Failure == any Error {
    /// Computes the result of a throwing member from the call's arguments, without throwing.
    ///
    /// ```swift
    /// when { try client.save(.fixture) }.thenAnswer { (user: User) in print("saved", user.id) }
    /// ```
    ///
    /// This is a separate overload, because converting a non-throwing closure to
    /// `throws(any Error)` crashes the compiler when an argument is a callback.
    ///
    /// - Parameter body: A closure that takes the member's arguments and returns its result.
    /// - Returns: This stub.
    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: false, sync: { packed in
            let args = packed as! (repeat each A)
            return body(repeat each args)
        }, async: nil))
    }

    /// Computes the result of an `async` throwing member from the call's arguments, without throwing.
    ///
    /// ```swift
    /// when { try await client.fetch(id: "42") }.thenAnswer { (id: String) async in
    ///     await Task.yield()
    ///     return User(id: id, name: "Gytis")
    /// }
    /// ```
    ///
    /// An `async` answer for a synchronous member is reported as a misuse and installs nothing.
    ///
    /// - Parameter body: An `async` closure that takes the member's arguments and returns its result.
    /// - Returns: This stub.
    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) async -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: true, sync: nil, async: { packed in
            let args = UncheckedSendable(packed as! (repeat each A))
            return await body(repeat each args.value)
        }))
    }

    /// Throws `error` on every matching call.
    ///
    /// ```swift
    /// when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)
    /// ```
    ///
    /// Available only when the stubbed expression can throw. On a member that does not throw,
    /// the `when(_:)` form is a compile error, and the closure form is reported at the `when` line.
    ///
    /// - Parameter error: The error to throw.
    /// - Returns: This stub.
    @discardableResult
    public func thenThrow(_ error: any Error) -> Self {
        guard let target else { return self }
        guard target.effects.contains(.throwing) else {
            Reporter.fail("thenThrow for \(target.qualifiedMember): the member does not throw.", at: target.site)
            return self
        }
        target.runtime.install(StubRecord(target: target, response: .error(error)))
        return self
    }
}

/// `String(reflecting:)` without the `Swift.` module prefix of standard-library types.
func typeDescription(_ type: Any.Type) -> String {
    String(reflecting: type).replacingOccurrences(of: "Swift.", with: "")
}

/// Formats a type as an argument list: `(String)` for one type, `(String, Int)` for a
/// tuple, `()` for Void. Strips the `Swift.` module prefix of standard-library types.
func parenthesized(_ type: Any.Type) -> String {
    let name = typeDescription(type)
    return name.hasPrefix("(") ? name : "(\(name))"
}

/// Carries a stub's arguments to the user's answer. The answer closure is the user's own code,
/// and a mock call is expected to hand its arguments to it, so the usual non-`Sendable` check
/// is waived here rather than leaking into every answer signature. The hazard is real for sync
/// answers too: both kinds run on whatever thread or actor the code under test calls the mock from.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
