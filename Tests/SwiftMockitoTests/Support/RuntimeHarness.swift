@testable import SwiftMockito

/// Builds a stub directly on a runtime. Stands in for `when(...)` until Task 8.
func stub<R, each A>(
    _ runtime: MockRuntime,
    _ member: String,
    key: [Argument],
    argumentTypes: (repeat each A).Type,
    effects: Effects = [],
    returning: R.Type = R.self,
    site: CallSite = CallSite()
) -> Stub<R, any Error> {
    Stub(target: StubTarget(runtime: runtime, member: member, key: key,
                            argumentsType: argumentTypes, effects: effects, site: site))
}

final class Harness: Mock, @unchecked Sendable {
    init() { super.init(name: "Harness", site: CallSite(fileID: "Harness.swift", line: 1, column: 1)) }
}
