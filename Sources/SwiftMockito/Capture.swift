import Foundation

/// Thrown by generated throwing members while recording. `when`/`verify` catch it.
public struct CaptureSignal: Error, Sendable {
    public init() {}
}

/// The recording context that `when`, `verify`, `verifyNever` and `verifyInOrder`
/// install around their expression. It is task-local, so parallel tests never share it.
public final class Capture: @unchecked Sendable {
    @TaskLocal public static var current: Capture?
    /// Set by `verifyInOrder`. While true, generated throwing members return a
    /// placeholder after recording instead of throwing `CaptureSignal`, so the
    /// lines after them are recorded too.
    @TaskLocal public static var continuesAfterRecord = false
    /// Where the capturing API was called, so dummy traps point at the test line.
    @TaskLocal static var currentSite: CallSite?

    private let lock = NSLock()
    private var recorded: [Recorded] = []

    init() {}

    public func record<each A>(
        _ runtime: MockRuntime,
        _ member: String,
        key: [Argument],
        args: repeat each A,
        effects: Effects = []
    ) {
        let entry = Recorded(runtime: runtime, member: member, key: key,
                             argumentsType: (repeat each A).self, effects: effects)
        lock.withLock { recorded.append(entry) }
    }

    var snapshot: [Recorded] { lock.withLock { recorded } }
}

struct Recorded {
    let runtime: MockRuntime
    let member: String
    let key: [Argument]
    let argumentsType: Any.Type
    let effects: Effects

    var qualifiedMember: String { "\(runtime.mockName).\(member)" }
    var keyDescription: String { "(\(key.map(\.description).joined(separator: ", ")))" }

    /// Reports `UnsupportedExactMatchingError` for the first unsupported key argument.
    func checkSupported(at site: CallSite) -> Bool {
        guard let position = key.firstIndex(where: { !$0.isSupported }) else { return true }
        Reporter.fail(
            UnsupportedExactMatchingError(member: qualifiedMember, position: position,
                                          typeName: key[position].typeName).description,
            at: site
        )
        return false
    }
}

struct CaptureOutcome {
    let recorded: [Recorded]
    /// The body ended by a `CaptureSignal` (normal for `when`/`verify`; a misuse
    /// for `verifyInOrder`, where it means a member had no placeholder).
    let signalled: Bool
}

/// Shared between the caller and the capture task. If the body suspends, the task
/// outlives `captureAll`, so every field is read and written under one lock.
private final class Completion: @unchecked Sendable {
    private let lock = NSLock()
    /// The thread inside `captureAll`. A body that finishes synchronously finishes here.
    private let callerThread = pthread_self()
    private var finished = false
    private var abandoned = false
    private var signalled = false
    private var unexpected: (any Error)?

    /// Called by the task when the body ends. A no-op once the caller has given up.
    /// A body that finishes on another thread suspended on the way (the caller thread is
    /// blocked in `captureAll`, so it cannot have resumed it there). That counts as not
    /// finished even when it wins the race against `settle()`, so reporting is deterministic.
    func finish(signalled: Bool, unexpected: (any Error)?) {
        lock.withLock {
            guard !abandoned, pthread_equal(pthread_self(), callerThread) != 0 else { return }
            finished = true
            self.signalled = signalled
            self.unexpected = unexpected
        }
    }

    /// Called by the caller after `Task.immediate` returns. Abandons the task if it has not finished.
    func settle() -> (finished: Bool, signalled: Bool, unexpected: (any Error)?) {
        lock.withLock {
            if !finished { abandoned = true }
            return (finished, signalled, unexpected)
        }
    }
}

/// Runs `body` synchronously with a fresh capture installed, via `Task.immediate`.
/// Capture-mode members never suspend, so the task finishes before this returns.
/// Returns `nil` after reporting when the expression suspended or threw something
/// other than `CaptureSignal`.
func captureAll(
    _ verb: String,
    site: CallSite,
    isolation: isolated (any Actor)?,
    continuing: Bool = false,
    _ body: @escaping () async throws -> Void
) -> CaptureOutcome? {
    let capture = Capture()
    let completion = Completion()
    // `body` is `@escaping` rather than `sending`, which rejects XCTest closures capturing
    // `self`. Safe because `Task.immediate` runs on this thread and finishes before we return.
    Capture.$current.withValue(capture) {
        Capture.$currentSite.withValue(site) {
            Capture.$continuesAfterRecord.withValue(continuing) {
                _ = Task.immediate {
                    _ = isolation   // Load-bearing: keeps this closure on the caller's actor and lets the non-`sending` capture of `body` compile.
                    var signalled = false
                    var unexpected: (any Error)?
                    do { try await body() } catch is CaptureSignal { signalled = true } catch { unexpected = error }
                    completion.finish(signalled: signalled, unexpected: unexpected)
                }
            }
        }
    }
    let result = completion.settle()
    guard result.finished else {
        Reporter.fail("\(verb): the expression suspended before reaching a mock call. Keep only the mock call inside the closure; a mock of a global-actor protocol must be used from a test isolated to that actor.", at: site)
        return nil
    }
    if let error = result.unexpected {
        Reporter.fail("\(verb): the expression threw \(error) instead of reaching a mock call.", at: site)
        return nil
    }
    return CaptureOutcome(recorded: capture.snapshot, signalled: result.signalled)
}

/// Synchronous variant for the autoclosure overloads.
func captureAll(site: CallSite, _ body: () -> Void) -> [Recorded] {
    let capture = Capture()
    Capture.$current.withValue(capture) {
        Capture.$currentSite.withValue(site, operation: body)
    }
    return capture.snapshot
}

func exactlyOne(_ verb: String, _ recorded: [Recorded]?, site: CallSite) -> Recorded? {
    guard let recorded else { return nil }
    guard recorded.count == 1 else {
        let names = recorded.map(\.qualifiedMember).joined(separator: ", ")
        let suffix = recorded.isEmpty ? "" : " (\(names))"
        Reporter.fail("\(verb): expected exactly one mock call, recorded \(recorded.count)\(suffix).", at: site)
        return nil
    }
    return recorded[0]
}

/// "Recorded calls to m: (a), (b) [verified]", or "No calls to m were recorded."
func recordedCallsLine(_ recorded: Recorded) -> String {
    let calls = recorded.runtime.callsSnapshot().filter { $0.member == recorded.member }
    guard !calls.isEmpty else { return "No calls to \(recorded.member) were recorded." }
    let list = calls.map { call in
        "(\(call.key.map(\.description).joined(separator: ", ")))\(call.verified ? " [verified]" : "")"
    }
    return "Recorded calls to \(recorded.member): \(list.joined(separator: ", "))"
}
