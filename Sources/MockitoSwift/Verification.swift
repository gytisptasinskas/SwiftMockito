import Foundation
import Testing
import XCTest

// MARK: - when

/// Activates capture mode for `call`, then configures a stub for the single mock
/// invocation it captured.
///
/// `call` must evaluate to exactly one generated mock member invocation; zero or more than
/// one is a misuse that is reported at `fileID`/`line` and yields a no-op stub.
@discardableResult
public func when<Value>(
    _ call: @autoclosure () throws -> Value,
    fileID: String = #fileID,
    line: Int = #line
) rethrows -> Stub {
    guard let captured = try captureSingleCall(fileID: fileID, line: line, call: call) else {
        return Stub { _ in }
    }
    return stubbing(captured, fileID: fileID, line: line)
}

/// `async`/`throws`-preserving overload of `when(_:)`. Use the explicit closure form so
/// `await`/`try` inside the call expression remain visible at the call site, e.g.
/// `when { try await client.fetch(id: "42") }`.
@discardableResult
public func when<Value>(
    fileID: String = #fileID,
    line: Int = #line,
    _ call: () async throws -> Value
) async rethrows -> Stub {
    guard let captured = try await captureSingleCall(fileID: fileID, line: line, call: call) else {
        return Stub { _ in }
    }
    return stubbing(captured, fileID: fileID, line: line)
}

private func stubbing(_ captured: CapturedCall, fileID: String, line: Int) -> Stub {
    guard let arguments = captured.arguments else {
        FailureReporting.report(
            "Cannot configure \(captured.invocation.member): its arguments are not exact-matchable.",
            fileID: fileID,
            line: line
        )
        return Stub { _ in }
    }
    return captured.runtime.stub(for: captured.invocation, arguments: arguments)
}

// MARK: - verify

/// Activates capture mode for `call`, then immediately asserts at least one unverified
/// recorded call matches it, consuming every match it finds. The returned value supports
/// `.called(...)` for a more precise count assertion.
///
/// `call` must evaluate to exactly one generated mock member invocation; zero or more than
/// one is a misuse reported at `fileID`/`line`.
@discardableResult
public func verify<Value>(
    _ call: @autoclosure () throws -> Value,
    fileID: String = #fileID,
    line: Int = #line
) rethrows -> Verification {
    guard let captured = try captureSingleCall(fileID: fileID, line: line, call: call) else {
        return Verification(matchCount: 0, failed: true, fileID: fileID, line: line)
    }
    return applyVerify(captured, fileID: fileID, line: line)
}

/// `async`/`throws`-preserving overload of `verify(_:)`, e.g.
/// `verify { try await client.fetch(id: "42") }.called(once())`.
@discardableResult
public func verify<Value>(
    fileID: String = #fileID,
    line: Int = #line,
    _ call: () async throws -> Value
) async rethrows -> Verification {
    guard let captured = try await captureSingleCall(fileID: fileID, line: line, call: call) else {
        return Verification(matchCount: 0, failed: true, fileID: fileID, line: line)
    }
    return applyVerify(captured, fileID: fileID, line: line)
}

private func applyVerify(_ captured: CapturedCall, fileID: String, line: Int) -> Verification {
    let matchIDs = captured.runtime.matchingInteractionIDs(
        invocation: captured.invocation,
        arguments: captured.arguments,
        unverifiedOnly: true
    )
    guard !matchIDs.isEmpty else {
        FailureReporting.report(
            "Expected at least 1 call to \(captured.invocation.member) but found 0.",
            fileID: fileID,
            line: line
        )
        // The "at least 1" check above already reported a failure; `.called(...)` must not
        // report a second failure for the same zero-match outcome.
        return Verification(matchCount: 0, failed: true, fileID: fileID, line: line)
    }
    captured.runtime.markVerified(Set(matchIDs))
    return Verification(matchCount: matchIDs.count, failed: false, fileID: fileID, line: line)
}

/// The outcome of a `verify(_:)` call. Matching interactions are already consumed by the
/// time this value exists; `.called(...)` only checks the count against expectations.
public struct Verification {
    let matchCount: Int
    /// `true` when `verify` already reported a failure (misuse, or zero matching calls),
    /// so `.called(...)` must not report a second failure for the same outcome.
    let failed: Bool
    let fileID: String
    let line: Int

    /// Asserts the call was matched exactly `n` times.
    @discardableResult
    public func called(_ n: Int) -> Bool {
        assertCount(.exact(n))
    }

    /// Asserts the call was matched the number of times described by `count`
    /// (see `once()`, `atLeast(_:)`, `atMost(_:)`).
    @discardableResult
    public func called(_ count: CallCount) -> Bool {
        assertCount(count.kind)
    }

    /// Asserts the call was matched at least `n` times.
    @discardableResult
    public func called(atLeast n: Int) -> Bool {
        assertCount(.atLeast(n))
    }

    /// Asserts the call was matched at most `n` times.
    @discardableResult
    public func called(atMost n: Int) -> Bool {
        assertCount(.atMost(n))
    }

    private func assertCount(_ kind: CallCount.Kind) -> Bool {
        guard !failed else {
            return false
        }
        guard kind.matches(matchCount) else {
            FailureReporting.report(
                "Expected \(kind.description) call(s) but was called \(matchCount) time(s).",
                fileID: fileID,
                line: line
            )
            return false
        }
        return true
    }
}

// MARK: - verifyNever

/// Activates capture mode for `call`, then asserts it matches zero recorded calls —
/// verified or not, since the point of `verifyNever` is to prove the call never happened.
@discardableResult
public func verifyNever<Value>(
    _ call: @autoclosure () throws -> Value,
    fileID: String = #fileID,
    line: Int = #line
) rethrows -> Bool {
    guard let captured = try captureSingleCall(fileID: fileID, line: line, call: call) else {
        return false
    }
    return applyVerifyNever(captured, fileID: fileID, line: line)
}

/// `async`/`throws`-preserving overload of `verifyNever(_:)`.
@discardableResult
public func verifyNever<Value>(
    fileID: String = #fileID,
    line: Int = #line,
    _ call: () async throws -> Value
) async rethrows -> Bool {
    guard let captured = try await captureSingleCall(fileID: fileID, line: line, call: call) else {
        return false
    }
    return applyVerifyNever(captured, fileID: fileID, line: line)
}

private func applyVerifyNever(_ captured: CapturedCall, fileID: String, line: Int) -> Bool {
    let matchIDs = captured.runtime.matchingInteractionIDs(
        invocation: captured.invocation,
        arguments: captured.arguments,
        unverifiedOnly: false
    )
    guard matchIDs.isEmpty else {
        FailureReporting.report(
            "Expected 0 calls to \(captured.invocation.member) but found \(matchIDs.count).",
            fileID: fileID,
            line: line
        )
        return false
    }
    return true
}

// MARK: - call counts

/// Describes how many times a verified call is expected to have happened.
public struct CallCount: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case exact(Int)
        case atLeast(Int)
        case atMost(Int)

        func matches(_ count: Int) -> Bool {
            switch self {
            case .exact(let n): return count == n
            case .atLeast(let n): return count >= n
            case .atMost(let n): return count <= n
            }
        }

        var description: String {
            switch self {
            case .exact(let n): return "exactly \(n)"
            case .atLeast(let n): return "at least \(n)"
            case .atMost(let n): return "at most \(n)"
            }
        }
    }

    let kind: Kind
}

/// A `CallCount` matching exactly one call, for `verify(...).called(once())`.
public func once() -> CallCount {
    CallCount(kind: .exact(1))
}

/// A `CallCount` matching `n` or more calls.
public func atLeast(_ n: Int) -> CallCount {
    CallCount(kind: .atLeast(n))
}

/// A `CallCount` matching `n` or fewer calls.
public func atMost(_ n: Int) -> CallCount {
    CallCount(kind: .atMost(n))
}

// MARK: - verifyInOrder

/// Marks expressions inside a `verifyInOrder` block as captured calls instead of leaving
/// their (usually unused) results to trigger "result is unused" warnings.
@resultBuilder
public enum VerificationBuilder {
    public static func buildExpression<Value>(_ expression: Value) {}
    public static func buildExpression(_ expression: Void) {}
    public static func buildBlock(_ components: Void...) {}
}

/// Captures every mock call made inside `build`, in order, then asserts they occurred in
/// that relative order against each mock's recorded history. Unrelated calls may occur
/// between expected calls. Matching calls are consumed.
///
/// `build` may contain `try`/`throws` call expressions (capture mode never really
/// dispatches, so this should not throw in practice), but `verifyInOrder` itself does not
/// throw: an error escaping `build` is reported as a failure instead of propagating.
public func verifyInOrder(
    fileID: String = #fileID,
    line: Int = #line,
    @VerificationBuilder _ build: () throws -> Void
) {
    let session = CaptureSession()
    do {
        try CaptureContext.$current.withValue(session) {
            try build()
        }
    } catch {
        FailureReporting.report("verifyInOrder block threw \(error).", fileID: fileID, line: line)
        return
    }
    applyInOrderVerification(session.snapshot(), fileID: fileID, line: line)
}

/// `async`-preserving overload of `verifyInOrder(_:)`, e.g.
/// `await verifyInOrder { try await client.fetch(id: "42") }`.
public func verifyInOrder(
    fileID: String = #fileID,
    line: Int = #line,
    @VerificationBuilder _ build: () async throws -> Void
) async {
    let session = CaptureSession()
    do {
        try await CaptureContext.$current.withValue(session) {
            try await build()
        }
    } catch {
        FailureReporting.report("verifyInOrder block threw \(error).", fileID: fileID, line: line)
        return
    }
    applyInOrderVerification(session.snapshot(), fileID: fileID, line: line)
}

private func applyInOrderVerification(_ calls: [CapturedCall], fileID: String, line: Int) {
    guard !calls.isEmpty else {
        FailureReporting.report("verifyInOrder requires at least one call.", fileID: fileID, line: line)
        return
    }
    var cursors: [ObjectIdentifier: Int] = [:]
    for captured in calls {
        let key = ObjectIdentifier(captured.runtime)
        let startIndex = cursors[key] ?? 0
        guard let foundIndex = captured.runtime.consumeNextMatchingInteraction(
            after: startIndex,
            invocation: captured.invocation,
            arguments: captured.arguments
        ) else {
            FailureReporting.report(
                "Expected \(captured.invocation.member) in order but found no matching unverified call.",
                fileID: fileID,
                line: line
            )
            continue
        }
        cursors[key] = foundIndex + 1
    }
}

// MARK: - verifyNoMoreInteractions

/// Asserts every call recorded on `mock` has already been verified.
@discardableResult
public func verifyNoMoreInteractions(_ mock: Mock, fileID: String = #fileID, line: Int = #line) -> Bool {
    let unverified = mock.runtime.interactionSnapshot(for: mock.id).filter { !$0.verified }
    guard unverified.isEmpty else {
        let members = unverified.map(\.invocation.member).joined(separator: ", ")
        FailureReporting.report(
            "Expected no more interactions but found unverified call(s): \(members).",
            fileID: fileID,
            line: line
        )
        return false
    }
    return true
}

// MARK: - reset

/// Removes `mock`'s configured stubs and recorded calls.
public func reset(_ mock: Mock) {
    mock.runtime.reset()
}

// MARK: - capture plumbing

private func captureSingleCall<Value>(
    fileID: String,
    line: Int,
    call: () throws -> Value
) rethrows -> CapturedCall? {
    let session = CaptureSession()
    _ = try CaptureContext.$current.withValue(session) {
        try call()
    }
    return singleCapturedCall(from: session, fileID: fileID, line: line)
}

private func captureSingleCall<Value>(
    fileID: String,
    line: Int,
    call: () async throws -> Value
) async rethrows -> CapturedCall? {
    let session = CaptureSession()
    _ = try await CaptureContext.$current.withValue(session) {
        try await call()
    }
    return singleCapturedCall(from: session, fileID: fileID, line: line)
}

private func singleCapturedCall(from session: CaptureSession, fileID: String, line: Int) -> CapturedCall? {
    let calls = session.snapshot()
    guard calls.count == 1 else {
        FailureReporting.report(
            "Expected exactly one mock call in this expression but captured \(calls.count).",
            fileID: fileID,
            line: line
        )
        return nil
    }
    return calls[0]
}

// MARK: - failure reporting

/// Routes verification failures to the active test framework: `Issue.record` under Swift
/// Testing, `XCTFail` otherwise. Tests of MockitoSwift itself use `override` to capture
/// failure messages instead of failing the enclosing test.
enum FailureReporting {
    @TaskLocal static var override: (@Sendable (String) -> Void)?

    static func report(_ message: String, fileID: String, line: Int) {
        let full = "\(message) (\(fileID):\(line))"
        if let override {
            override(full)
            return
        }
        if Test.current != nil {
            Issue.record(Comment(rawValue: full))
        } else {
            XCTFail(full)
        }
    }
}
