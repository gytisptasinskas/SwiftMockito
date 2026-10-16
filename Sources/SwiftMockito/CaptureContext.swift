// Replaced in Task 8.
#if false
import Foundation

/// Task-local capture mode toggled by `when`, `verify`, and `verifyInOrder` while they
/// evaluate the caller's mock-call expression.
///
/// Generated mock members (and, until Task 4/5 land, hand-written test doubles) consult
/// `CaptureContext.current` to decide whether to record invocation shape for later
/// matching instead of performing real dispatch. Using a `@TaskLocal` instead of a global
/// mutable variable keeps capture mode isolated per `Task`, so concurrent tests — and
/// concurrent `await` suspensions within one test — never observe or mutate each other's
/// capture state.
public enum CaptureContext {
    @TaskLocal public static var current: CaptureSession?
}

/// Accumulates invocations captured during one `when`/`verify`/`verifyInOrder` expression.
///
/// A generated mock member calls `record(_:arguments:runtime:)` while
/// `CaptureContext.current` is non-nil instead of recording a real dispatch or resolving a
/// stub. The member still returns a placeholder value so the surrounding call expression
/// type-checks; that value is discarded by the capturing API.
public final class CaptureSession: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [CapturedCall] = []

    public init() {}

    /// Records one captured invocation. Safe to call concurrently.
    public func record(_ invocation: Invocation, arguments: ExactArguments?, runtime: MockRuntime) {
        lock.lock()
        defer { lock.unlock() }
        calls.append(CapturedCall(invocation: invocation, arguments: arguments, runtime: runtime))
    }

    /// Everything recorded so far, in capture order.
    func snapshot() -> [CapturedCall] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }
}

/// One invocation captured while `CaptureContext.current` was active, paired with the
/// runtime that owns it so `when`/`verify`/`verifyInOrder` can query or mutate that mock's
/// interaction history afterward.
struct CapturedCall {
    let invocation: Invocation
    let arguments: ExactArguments?
    let runtime: MockRuntime
}

#endif
