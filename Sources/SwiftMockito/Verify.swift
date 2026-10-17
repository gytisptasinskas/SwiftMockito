/// Result of `verify`. The matching calls are already marked verified.
public struct Verification {
    let recorded: Recorded?
    let count: Int

    public func called(_ n: Int, fileID: String = #fileID, filePath: StaticString = #filePath,
                       line: UInt = #line, column: UInt = #column) {
        check(count == n, "exactly \(n) \(n == 1 ? "call" : "calls")",
              CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    public func called(atLeast n: Int, fileID: String = #fileID, filePath: StaticString = #filePath,
                       line: UInt = #line, column: UInt = #column) {
        check(count >= n, "at least \(n) \(n == 1 ? "call" : "calls")",
              CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

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

@_disfavoredOverload
public func verifyNever<R>(
    _ call: @autoclosure () -> R,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column
) {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    applyVerifyNever(exactlyOne("verifyNever", captureAll(site: site) { _ = call() }, site: site), site: site)
}

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
