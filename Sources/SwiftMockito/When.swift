/// Stubs a synchronous, non-throwing member: `when(client.cached(id: "42"))`.
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

/// Stubs a member that needs `try` or `await`: `when { try await client.fetch(id: "42") }`.
@discardableResult
public func when<R, E: Error>(
    isolation: isolated (any Actor)? = #isolation,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    _ call: @escaping () async throws(E) -> R
) -> Stub<R, E> {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let recorded = captureAll("when", site: site, isolation: isolation) { _ = isolation; _ = try await call() }?.recorded
    return Stub(target: exactlyOne("when", recorded, site: site).flatMap { stubTarget($0, site: site) })
}

private func stubTarget(_ recorded: Recorded, site: CallSite) -> StubTarget? {
    guard recorded.checkSupported(at: site) else { return nil }
    return StubTarget(runtime: recorded.runtime, member: recorded.member, key: recorded.key,
                      argumentsType: recorded.argumentsType, effects: recorded.effects, site: site)
}
