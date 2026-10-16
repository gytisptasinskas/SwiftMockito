import Foundation

/// What a generated member does, as recorded during capture.
public struct Effects: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let async = Effects(rawValue: 1 << 0)
    public static let throwing = Effects(rawValue: 1 << 1)
}

struct StubTarget {
    let runtime: MockRuntime
    let member: String
    let key: [Argument]
    let argumentsType: Any.Type
    let effects: Effects
    let site: CallSite

    var qualifiedMember: String { "\(runtime.mockName).\(member)" }
}

struct StoredAnswer {
    let argumentsType: Any.Type
    let isAsync: Bool
    let sync: ((Any) throws -> Any)?
    let async: ((Any) async throws -> Any)?
}

enum StoredResponse {
    case values([Any])
    case error(any Error)
    case answer(StoredAnswer)
}

/// Configures the response of one recorded call. `Failure` is `Never` for members
/// that cannot throw, so `thenThrow` is unavailable for them at compile time.
public struct Stub<R, Failure: Error> {
    let target: StubTarget?

    init(target: StubTarget?) { self.target = target }

    /// Returns `values` in order on successive matching calls; the last one repeats.
    @discardableResult
    public func thenReturn(_ values: R...) -> Self {
        guard let target else { return self }
        guard !values.isEmpty else {
            Reporter.fail("thenReturn for \(target.qualifiedMember) needs at least one value.", at: target.site)
            return self
        }
        target.runtime.install(StubRecord(target: target, response: .values(values)))
        return self
    }

    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) throws(Failure) -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: false, sync: { packed in
            let args = packed as! (repeat each A)   // checked against argumentsType when installed
            return try body(repeat each args)
        }, async: nil))
    }

    @discardableResult
    public func thenAnswer<each A>(_ body: @escaping (repeat each A) async throws(Failure) -> R) -> Self {
        install(StoredAnswer(argumentsType: (repeat each A).self, isAsync: true, sync: nil, async: { packed in
            let args = packed as! (repeat each A)
            return try await body(repeat each args)
        }))
    }

    private func install(_ answer: StoredAnswer) -> Self {
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
        target.runtime.install(StubRecord(target: target, response: .answer(answer)))
        return self
    }
}

extension Stub where Failure == any Error {
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

/// Formats a type as an argument list: `(String)` for one type, `(String, Int)` for a
/// tuple, `()` for Void. Strips the `Swift.` module prefix of standard-library types.
func parenthesized(_ type: Any.Type) -> String {
    let name = String(reflecting: type).replacingOccurrences(of: "Swift.", with: "")
    return name.hasPrefix("(") ? name : "(\(name))"
}
