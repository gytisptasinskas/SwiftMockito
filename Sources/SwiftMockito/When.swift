/// Stubs a synchronous, non-throwing member.
///
/// Write the mock call as the argument. SwiftMockito records it instead of running it,
/// then installs whatever you configure on the returned ``Stub``:
///
/// ```swift
/// when(client.cached(id: "42")).thenReturn(.fixture)
/// when(client.currentUser).thenReturn(.fixture)    // a property getter
/// when(catalog[1]).thenReturn("one")              // a subscript
/// ```
///
/// The expression must record exactly one mock call; zero or several are reported at this
/// line. Arguments are matched by value (see <doc:Matching>). When several stubs match a call,
/// the newest one wins. Because the member cannot throw, ``Stub/thenThrow(_:)`` is not
/// available on the result.
///
/// For a member that needs `try`, use ``when(fileID:filePath:line:column:_:)-1fm7k``; for one that needs `await`, use
/// ``when(fileID:filePath:line:column:_:)-3fqwn``.
///
/// - Parameters:
///   - call: The mock call to stub, such as `client.cached(id: "42")`.
///   - fileID: The file of the call site, reported on misuse. Leave the default.
///   - filePath: The path of the call site, reported on misuse. Leave the default.
///   - line: The line of the call site, reported on misuse. Leave the default.
///   - column: The column of the call site, reported on misuse. Leave the default.
/// - Returns: A ``Stub`` that configures the response.
@_disfavoredOverload
@discardableResult
public func when<R>(
    _ call: @autoclosure () -> R,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column
) -> Stub<R, Never> {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = exactlyOne("when", captureAll(site: site) { _ = call() }, site: site)
    return Stub(target: recorded.flatMap { stubTarget($0, site: site) })
}

/// Stubs a member that needs `try`, or a property setter.
///
/// Write the mock call inside the closure, with its `try`. The closure is recorded, not run
/// against the stubs, and `when` itself needs no `try`:
///
/// ```swift
/// when { try client.save(.fixture) }.thenThrow(ClientError.offline)
/// ```
///
/// The closure may contain only the mock call. It must record exactly one call and evaluate
/// to the member's own return type: wrapping the call in `try?`, `??` or a conversion is
/// reported at this line and installs no stub. When several stubs match a call, the newest
/// one wins. For a call that needs `await`, write `await when { … }`.
///
/// - Parameters:
///   - fileID: The file of the call site, reported on misuse. Leave the default.
///   - filePath: The path of the call site, reported on misuse. Leave the default.
///   - line: The line of the call site, reported on misuse. Leave the default.
///   - column: The column of the call site, reported on misuse. Leave the default.
///   - call: A closure that contains only the mock call to stub.
/// - Returns: A ``Stub`` that configures the response.
@discardableResult
public func when<R, E: Error>(
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    _ call: () throws(E) -> R
) -> Stub<R, E> {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = captureAll("when", site: site) { _ = try call() }?.recorded
    return Stub(target: exactlyOne("when", recorded, site: site).flatMap { stubTarget($0, site: site) })
}

/// Stubs a member that needs `await`.
///
/// Write the mock call inside the closure, with its `try` and `await`, and `await` the `when`:
///
/// ```swift
/// await when { try await client.fetch(id: "42") }.thenReturn(.fixture)
/// await when { try await client.fetch(id: "7") }.thenThrow(ClientError.offline)
/// ```
///
/// The closure is recorded, not run against the stubs, with the same rules as the
/// synchronous closure form. The recording follows the call across actor hops.
///
/// - Parameters:
///   - fileID: The file of the call site, reported on misuse. Leave the default.
///   - filePath: The path of the call site, reported on misuse. Leave the default.
///   - line: The line of the call site, reported on misuse. Leave the default.
///   - column: The column of the call site, reported on misuse. Leave the default.
///   - call: A closure that contains only the mock call to stub.
/// - Returns: A ``Stub`` that configures the response.
@_disfavoredOverload
@discardableResult
nonisolated(nonsending) public func when<R, E: Error>(
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    _ call: () async throws(E) -> R
) async -> Stub<R, E> {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = await captureAll("when", site: site) { _ = try await call() }?.recorded
    return Stub(target: exactlyOne("when", recorded, site: site).flatMap { stubTarget($0, site: site) })
}

private func stubTarget(_ recorded: Recorded, site: CallSite) -> StubTarget? {
    guard recorded.checkSupported(at: site) else { return nil }
    return StubTarget(runtime: recorded.runtime, member: recorded.member, key: recorded.key,
                      argumentsType: recorded.argumentsType, effects: recorded.effects,
                      returnType: recorded.returnType, site: site)
}
