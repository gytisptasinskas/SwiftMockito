import Foundation

/// Used by generated mocks; don't call it directly.
///
/// Thrown by generated throwing members while recording. `when`/`verify` catch it.
public struct CaptureSignal: Error, Sendable {
    /// Used by generated mocks; don't call it directly.
    public init() {}
}

/// Used by generated mocks; don't call it directly.
///
/// The recording context that `when`, `verify`, `verifyNever` and `verifyInOrder`
/// install around their expression. It is task-local, so parallel tests never share it.
public final class Capture: @unchecked Sendable {
    /// Used by generated mocks; don't call it directly.
    ///
    /// The active recording context, or `nil` when the mock should answer from its stubs.
    @TaskLocal public static var current: Capture?
    /// Used by generated mocks; don't call it directly.
    ///
    /// Set by `verifyInOrder`. While true, generated throwing members return a
    /// placeholder after recording instead of throwing `CaptureSignal`, so the
    /// lines after them are recorded too.
    @TaskLocal public static var continuesAfterRecord = false
    /// Where the capturing API was called, so dummy traps point at the test line.
    @TaskLocal static var currentSite: CallSite?

    private let lock = NSLock()
    private var recorded: [Recorded] = []

    init() {}

    /// Used by generated mocks; don't call it directly.
    ///
    /// Records one call instead of running it.
    ///
    /// - Parameters:
    ///   - runtime: The mock's runtime.
    ///   - member: The member's name, such as `fetch(id:)`.
    ///   - key: The arguments that take part in matching.
    ///   - args: Every argument, closures included, in declaration order.
    ///   - effects: Whether the member is `async` or `throws`.
    ///   - returns: The member's declared return type.
    public func record<each A>(
        _ runtime: MockRuntime,
        _ member: String,
        key: [Argument],
        args: repeat each A,
        effects: Effects = [],
        returns: Any.Type = Void.self
    ) {
        let entry = Recorded(runtime: runtime, member: member, key: key,
                             argumentsType: (repeat each A).self, effects: effects, returnType: returns)
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
    /// The member's declared return type; `Void` when it returns nothing.
    let returnType: Any.Type

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

/// Runs `body` with a fresh capture installed and returns what it recorded, for the closure
/// forms whose call needs no `await`. Returns `nil` after reporting when the expression threw
/// something other than `CaptureSignal`.
func captureAll(_ verb: String, site: CallSite, continuing: Bool = false, _ body: () throws -> Void) -> CaptureOutcome? {
    let capture = Capture()
    do {
        try Capture.$current.withValue(capture) {
            try Capture.$currentSite.withValue(site) {
                try Capture.$continuesAfterRecord.withValue(continuing, operation: body)
            }
        }
    } catch is CaptureSignal {
        return CaptureOutcome(recorded: capture.snapshot, signalled: true)
    } catch {
        Reporter.fail("\(verb): the expression threw \(error) instead of reaching a mock call.", at: site)
        return nil
    }
    return CaptureOutcome(recorded: capture.snapshot, signalled: false)
}

/// The same for closure forms whose call needs `await`. The capture is task-local, so it
/// follows the expression across any actor hop on the way to the mock.
nonisolated(nonsending) func captureAll(_ verb: String, site: CallSite, continuing: Bool = false,
                                        _ body: () async throws -> Void) async -> CaptureOutcome? {
    let capture = Capture()
    do {
        try await Capture.$current.withValue(capture) {
            try await Capture.$currentSite.withValue(site) {
                try await Capture.$continuesAfterRecord.withValue(continuing) { try await body() }
            }
        }
    } catch is CaptureSignal {
        return CaptureOutcome(recorded: capture.snapshot, signalled: true)
    } catch {
        Reporter.fail("\(verb): the expression threw \(error) instead of reaching a mock call.", at: site)
        return nil
    }
    return CaptureOutcome(recorded: capture.snapshot, signalled: false)
}

/// Synchronous variant for the autoclosure overloads.
func captureAll(site: CallSite, _ body: () -> Void) -> [Recorded] {
    let capture = Capture()
    Capture.$current.withValue(capture) {
        Capture.$currentSite.withValue(site) {
            Capture.$continuesAfterRecord.withValue(false, operation: body)
        }
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
