/// The result of `verify`, which can tighten the expected call count.
///
/// By the time you hold a `Verification`, `verify` has already checked that at least one
/// matching call happened and marked the matching calls as verified. Add a count to be stricter:
///
/// ```swift
/// verify(client.cached(id: "42")).called(1)
/// verify { try await client.fetch(id: "42") }.called(atLeast: 2)
/// ```
///
/// The count is the number of matching calls that were not yet verified when `verify` ran.
/// To check that a call never happened, use ``verifyNever(_:fileID:filePath:line:column:)``
/// instead of `called(0)`.
public struct Verification {
    let recorded: Recorded?
    let count: Int

    /// Checks that exactly `n` matching calls happened.
    ///
    /// ```swift
    /// verify(client.cached(id: "42")).called(1)
    /// ```
    ///
    /// - Parameters:
    ///   - n: The expected number of calls.
    ///   - fileID: The file of the call site, reported on failure. Leave the default.
    ///   - filePath: The path of the call site, reported on failure. Leave the default.
    ///   - line: The line of the call site, reported on failure. Leave the default.
    ///   - column: The column of the call site, reported on failure. Leave the default.
    public func called(_ n: Int, fileID: String = #fileID, filePath: StaticString = #filePath,
                       line: UInt = #line, column: UInt = #column) {
        check(count == n, "exactly \(n) \(n == 1 ? "call" : "calls")",
              CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    /// Checks that `n` or more matching calls happened.
    ///
    /// ```swift
    /// verify(client.cached(id: "42")).called(atLeast: 2)
    /// ```
    ///
    /// - Parameters:
    ///   - n: The minimum number of calls.
    ///   - fileID: The file of the call site, reported on failure. Leave the default.
    ///   - filePath: The path of the call site, reported on failure. Leave the default.
    ///   - line: The line of the call site, reported on failure. Leave the default.
    ///   - column: The column of the call site, reported on failure. Leave the default.
    public func called(atLeast n: Int, fileID: String = #fileID, filePath: StaticString = #filePath,
                       line: UInt = #line, column: UInt = #column) {
        check(count >= n, "at least \(n) \(n == 1 ? "call" : "calls")",
              CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    /// Checks that no more than `n` matching calls happened.
    ///
    /// `verify` already requires at least one call, so this checks a range from 1 to `n`:
    ///
    /// ```swift
    /// verify(client.cached(id: "42")).called(atMost: 3)
    /// ```
    ///
    /// - Parameters:
    ///   - n: The maximum number of calls.
    ///   - fileID: The file of the call site, reported on failure. Leave the default.
    ///   - filePath: The path of the call site, reported on failure. Leave the default.
    ///   - line: The line of the call site, reported on failure. Leave the default.
    ///   - column: The column of the call site, reported on failure. Leave the default.
    public func called(atMost n: Int, fileID: String = #fileID, filePath: StaticString = #filePath,
                       line: UInt = #line, column: UInt = #column) {
        check(count <= n, "at most \(n) \(n == 1 ? "call" : "calls")",
              CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    private func check(_ passed: Bool, _ expectation: String, _ site: CallSite) {
        // `recorded == nil` or `count == 0` means `verify` already reported this failure.
        guard let recorded, count > 0, !passed else { return }
        Reporter.fail("verify: expected \(expectation) to \(recorded.qualifiedMember) with \(recorded.keyDescription), found \(count).", at: site)
    }
}

/// Checks that a synchronous, non-throwing member was called.
///
/// Write the mock call as the argument. It is recorded, not run:
///
/// ```swift
/// verify(client.cached(id: "42")).called(1)
/// verify(client.token).called(1)                  // a property getter
/// verify(catalog.notify({}))                     // closure arguments match any closure
/// ```
///
/// `verify` checks that at least one matching call happened that no earlier `verify` or
/// `verifyInOrder` has verified, then marks all of them as verified. Use the returned
/// ``Verification`` to check an exact count. Arguments are matched by value, and closure
/// arguments are left out of the match (see <doc:Matching>).
///
/// For a member that needs `try` or `await`, or for a property setter, use
/// ``verify(isolation:fileID:filePath:line:column:_:)``.
///
/// - Parameters:
///   - call: The mock call to verify, such as `client.cached(id: "42")`.
///   - fileID: The file of the call site, reported on failure. Leave the default.
///   - filePath: The path of the call site, reported on failure. Leave the default.
///   - line: The line of the call site, reported on failure. Leave the default.
///   - column: The column of the call site, reported on failure. Leave the default.
/// - Returns: A ``Verification`` that can check the number of calls.
@_disfavoredOverload
@discardableResult
public func verify<R>(
    _ call: @autoclosure () -> R,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column
) -> Verification {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    return applyVerify(exactlyOne("verify", captureAll(site: site) { _ = call() }, site: site), site: site)
}

/// Checks that a member that needs `try` or `await`, or a property setter, was called.
///
/// Write the mock call inside the closure, with its `try` and `await`. `verify` itself needs
/// neither:
///
/// ```swift
/// verify { try await client.fetch(id: "42") }.called(1)
/// verify { client.token = "new" }.called(1)     // a property setter
/// ```
///
/// It behaves like ``verify(_:fileID:filePath:line:column:)``: at least one matching,
/// not yet verified call must have happened, and the matching calls are marked as verified.
/// The closure must record exactly one mock call.
///
/// - Parameters:
///   - isolation: The caller's actor. Leave the default.
///   - fileID: The file of the call site, reported on failure. Leave the default.
///   - filePath: The path of the call site, reported on failure. Leave the default.
///   - line: The line of the call site, reported on failure. Leave the default.
///   - column: The column of the call site, reported on failure. Leave the default.
///   - call: A closure that contains only the mock call to verify.
/// - Returns: A ``Verification`` that can check the number of calls.
@discardableResult
public func verify<R, E: Error>(
    isolation: isolated (any Actor)? = #isolation,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    _ call: @escaping () async throws(E) -> R
) -> Verification {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = captureAll("verify", site: site, isolation: isolation) { _ = isolation; _ = try await call() }?.recorded
    return applyVerify(exactlyOne("verify", recorded, site: site), site: site)
}

/// Checks that a synchronous, non-throwing member was never called with these arguments.
///
/// ```swift
/// verifyNever(client.cached(id: "7"))
/// ```
///
/// Every matching call counts, including calls that an earlier `verify` already verified.
/// Calls with other arguments are fine.
///
/// For a member that needs `try` or `await`, use ``verifyNever(isolation:fileID:filePath:line:column:_:)``.
///
/// - Parameters:
///   - call: The mock call that must not have happened.
///   - fileID: The file of the call site, reported on failure. Leave the default.
///   - filePath: The path of the call site, reported on failure. Leave the default.
///   - line: The line of the call site, reported on failure. Leave the default.
///   - column: The column of the call site, reported on failure. Leave the default.
@_disfavoredOverload
public func verifyNever<R>(
    _ call: @autoclosure () -> R,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column
) {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    applyVerifyNever(exactlyOne("verifyNever", captureAll(site: site) { _ = call() }, site: site), site: site)
}

/// Checks that a member that needs `try` or `await`, or a property setter, was never called with these arguments.
///
/// ```swift
/// verifyNever { try client.save(.fixture) }
/// verifyNever { try await client.fetch(id: "7") }
/// ```
///
/// Every matching call counts, including calls that an earlier `verify` already verified.
///
/// - Parameters:
///   - isolation: The caller's actor. Leave the default.
///   - fileID: The file of the call site, reported on failure. Leave the default.
///   - filePath: The path of the call site, reported on failure. Leave the default.
///   - line: The line of the call site, reported on failure. Leave the default.
///   - column: The column of the call site, reported on failure. Leave the default.
///   - call: A closure that contains only the mock call that must not have happened.
public func verifyNever<R, E: Error>(
    isolation: isolated (any Actor)? = #isolation,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    _ call: @escaping () async throws(E) -> R
) {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = captureAll("verifyNever", site: site, isolation: isolation) { _ = isolation; _ = try await call() }?.recorded
    applyVerifyNever(exactlyOne("verifyNever", recorded, site: site), site: site)
}

/// Checks that every call on `mock` has been verified.
///
/// Call it after your `verify` and `verifyInOrder` checks. It fails, listing the calls, if the
/// mock recorded any call that no check has verified:
///
/// ```swift
/// verify(client.cached(id: "42")).called(1)
/// verify { try await client.fetch(id: "42") }.called(1)
/// verifyNoMoreInteractions(client)
/// ```
///
/// ``verifyNever(_:fileID:filePath:line:column:)`` does not verify calls.
///
/// - Parameters:
///   - mock: A generated mock.
///   - fileID: The file of the call site, reported on failure. Leave the default.
///   - filePath: The path of the call site, reported on failure. Leave the default.
///   - line: The line of the call site, reported on failure. Leave the default.
///   - column: The column of the call site, reported on failure. Leave the default.
public func verifyNoMoreInteractions(
    _ mock: Mock,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column
) {
    let unverified = mock.runtime.callsSnapshot().filter { !$0.verified }
    guard !unverified.isEmpty else { return }
    let list = unverified.map { "\($0.member) (\($0.key.map(\.description).joined(separator: ", ")))" }
    Reporter.fail(
        "verifyNoMoreInteractions: \(mock.runtime.mockName) has unverified calls: \(list.joined(separator: ", "))",
        at: CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    )
}

/// Clears `mock`'s stubs and recorded calls.
///
/// ```swift
/// when(client.cached(id: "42")).thenReturn(.fixture)
/// reset(client)
/// verifyNoMoreInteractions(client)   // passes: no calls are left
/// ```
///
/// Dummies registered with ``provideDummy(_:)`` are process-wide and are not cleared.
///
/// - Parameter mock: A generated mock.
public func reset(_ mock: Mock) {
    mock.runtime.reset()
}

private func applyVerify(_ recorded: Recorded?, site: CallSite) -> Verification {
    guard let recorded, recorded.checkSupported(at: site) else { return Verification(recorded: nil, count: 0) }
    let unverified = recorded.runtime.callsSnapshot()
        .filter { !$0.verified && $0.matches(member: recorded.member, key: recorded.key) }
    guard !unverified.isEmpty else {
        Reporter.fail(
            "verify: expected at least 1 unverified call to \(recorded.qualifiedMember) with \(recorded.keyDescription), found 0.\n"
                + recordedCallsLine(recorded),
            at: site
        )
        return Verification(recorded: recorded, count: 0)
    }
    recorded.runtime.markVerified(Set(unverified.map(\.id)))
    return Verification(recorded: recorded, count: unverified.count)
}

private func applyVerifyNever(_ recorded: Recorded?, site: CallSite) {
    guard let recorded, recorded.checkSupported(at: site) else { return }
    let count = recorded.runtime.callsSnapshot().filter { $0.matches(member: recorded.member, key: recorded.key) }.count
    guard count > 0 else { return }
    Reporter.fail("verifyNever: expected no calls to \(recorded.qualifiedMember) with \(recorded.keyDescription), found \(count).", at: site)
}
