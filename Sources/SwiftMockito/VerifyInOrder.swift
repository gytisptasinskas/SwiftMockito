/// Accepts plain, `try` and `await` lines. Lines are evaluated in order inside the
/// capture; with `Capture.continuesAfterRecord` set, throwing members do not stop the block.
@resultBuilder
public enum VerifyInOrderBuilder {
    public static func buildExpression<T>(_ expression: T) {}
    public static func buildBlock(_ components: Void...) {}
}

/// Checks that the calls in `calls` happened in this relative order. Unrelated calls may
/// occur in between. Matching calls are marked verified.
public func verifyInOrder(
    isolation: isolated (any Actor)? = #isolation,
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    @VerifyInOrderBuilder _ calls: @escaping () async throws -> Void
) {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    applyInOrder(captureAll("verifyInOrder", site: site, isolation: isolation, continuing: true, calls), site: site)
}

public func verifyInOrder(
    fileID: String = #fileID, filePath: StaticString = #filePath,
    line: UInt = #line, column: UInt = #column,
    @VerifyInOrderBuilder _ calls: () async throws -> Void
) async {
    let site = CallSite(fileID: fileID, filePath: filePath, line: line, column: column)
    let capture = Capture()
    var signalled = false
    do {
        try await Capture.$current.withValue(capture) {
            try await Capture.$currentSite.withValue(site) {
                try await Capture.$continuesAfterRecord.withValue(true) { try await calls() }
            }
        }
    } catch is CaptureSignal {
        signalled = true
    } catch {
        Reporter.fail("verifyInOrder: the block threw \(error) instead of reaching a mock call.", at: site)
        return
    }
    applyInOrder(CaptureOutcome(recorded: capture.snapshot, signalled: signalled), site: site)
}

private func applyInOrder(_ outcome: CaptureOutcome?, site: CallSite) {
    guard let outcome else { return }
    if outcome.signalled {
        let member = outcome.recorded.last?.qualifiedMember ?? "a mock member"
        Reporter.fail("verifyInOrder: \(member) has no placeholder return value, so the calls after it could not be recorded. Call provideDummy(_:) for its return type.", at: site)
        return
    }
    let recorded = outcome.recorded
    guard !recorded.isEmpty else {
        Reporter.fail("verifyInOrder: expected at least one mock call, recorded 0.", at: site)
        return
    }
    guard recorded.allSatisfy({ $0.checkSupported(at: site) }) else { return }

    var lastID = Int.min
    var previous: Recorded?
    for entry in recorded {
        let next = entry.runtime.callsSnapshot().first {
            !$0.verified && $0.id > lastID && $0.matches(member: entry.member, key: entry.key)
        }
        guard let next else {
            let after = previous.map { " after \($0.qualifiedMember) with \($0.keyDescription)" } ?? ""
            Reporter.fail(
                "verifyInOrder: \(entry.qualifiedMember) with \(entry.keyDescription) was not called\(after).\n"
                    + recordedCallsLine(entry),
                at: site
            )
            return
        }
        entry.runtime.markVerified([next.id])
        lastID = next.id
        previous = entry
    }
}
