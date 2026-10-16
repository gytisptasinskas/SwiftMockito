# API spike results (Task 4)

Toolchain: swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
(Target arm64-apple-macosx27.0.0, SDK MacOSX27.0, Testing Library 2084, Swift 6 language mode, `-strict-concurrency=complete` for probes.)

Spike package: `.superpowers/sdd/2026-10-16-mockito-swift/spike/` (git-ignored). Raw logs in its `logs/` and `failed/` directories.

## Results

Runtime tests are run with the `when` closure overload in **variant 1** (see D1x below): `sending` dropped, `nonisolated(unsafe) let body = call` added before `Task.immediate`. The brief's original form (with `sending`) does not compile for `XCTestCaptureProbe`. Every test other than `XCTestCaptureProbe` gave the same result with the original `sending` form.

| Probe | Result | Notes / compiler output |
|---|---|---|
| test `d1SyncWhenInAsyncTest` | PASS | |
| test `d1SyncWhenInSyncTest` | PASS | |
| test `d1SyncWhenOnMainActor` | **FAIL** | `Expectation failed: stub.completed`; `stub → Stub<User, Error>(members: [], completed: false)`. The async closure suspends (hops off the MainActor to call the nonisolated async `fetch`) before the mock records. See Notes. |
| test `d1SetterClosureAndAutoclosure` | PASS | |
| test `d1SuspendingClosureIsDetected` | PASS | observed `D1-yield completed=false` |
| test `d2AnnotatedAnswer` | PASS | |
| test `packedTupleCast` | PASS | |
| test `recordedArgTypesMatchAnswerTypes` | PASS | |
| test `d3TupleArg` | PASS | |
| test `d5InOrderRecordsEveryLine` | **FAIL** | Does not compile (the test could not run), because `InOrderBuilder.buildExpression` fails to compile. See the `InOrderBuilder` row below. |
| declaration `InOrderBuilder` / `inOrder` (D5 support code) | **FAIL** | `error: 'async' autoclosure parameter in a non-'async' function` at `public static func buildExpression<T>(_ expression: @autoclosure @escaping () async throws -> T) -> Step` (note: add 'async' to function 'buildExpression' to make it asynchronous). This broke the whole `Probe` module build, so it was moved out to `spike/failed/D5-inorder-standalone.swift` and its test to `spike/failed/D5-test.txt`. |
| `XCTestCaptureProbe.testWhenCapturingSelf` (original, `sending` intact) | **FAIL** | `ProbeTests.swift:83:20: error: passing closure as a 'sending' parameter risks causing data races between code in the current isolation context and concurrent execution of the closure` / `note: closure captures 'self' which is accessible to code in the current isolation context`. |
| `XCTestCaptureProbe.testWhenCapturingSelf` (variant 1: no `sending`, `nonisolated(unsafe) let body`) | PASS | compiles with no new warning and passes. |
| `XCTestCaptureProbe.testWhenCapturingSelf` (variant 2: also drop `isolation:`) | PASS (not needed) | Exploratory only: variant 2 regressed `d1SyncWhenInSyncTest` (members `[]`) and `d1SetterClosureAndAutoclosure`, in addition to `d1SyncWhenOnMainActor`. Variant 1 is therefore the one to use. |
| `probes/D1-no-await-in-async.swift` | PASS | |
| `probes/D1-throw-on-nonthrowing.swift` | PASS | Errors as expected: `error: cannot convert value of type 'User?' to expected argument type '() async throws -> R'` (the error is reported against the closure overload, but it is an error). |
| `probes/D1-throw-on-nonthrowing-closure.swift` | **FAIL** | expected error, got compile. `when { client.cached(id: "42") }` alone infers `Stub<User?, Never>`, but when `.thenThrow(...)` is chained the solver picks `E = any Error` (`Stub<User?, any Error>`) and the code compiles. `thenThrow` on a non-throwing closure is not rejected. |
| `probes/D1-mainactor-test.swift` | PASS | Compiles (but the runtime `d1SyncWhenOnMainActor` test fails; see above). |
| `probes/D2-unannotated-answer.swift` | **FAIL** | `D2-unannotated-answer.swift:4:76: error: cannot infer type of closure parameter 'completion' without a type annotation` |
| `probes/D2-unannotated-single.swift` | PASS | |
| `probes/D4a-mainactor-subclass.swift` | PASS | |
| `probes/D4b-mainactor-witnesses.swift` | PASS | |
| `probes/D4c-nonisolated-class.swift` | PASS | |
| `probes/P8-empty-pack.swift` | PASS | |

## Decisions
- D1: Fallback. `d1SyncWhenOnMainActor` fails, and `D1-throw-on-nonthrowing-closure` compiles instead of erroring. (`D1-no-await-in-async`, `D1-mainactor-test` compile, `D1-throw-on-nonthrowing` errors, and the other `d1*` tests pass.)
- D1x: Fallback (variant 1 compiled: drop `sending` and add `nonisolated(unsafe) let body = call` before `Task.immediate`; keep `isolation:`). `XCTestCaptureProbe` does not compile with `sending` intact.
- D2: Fallback. `D2-unannotated-answer` (the variadic completion-handler form) fails to infer; `D2-unannotated-single` passes. The annotated form (`d2AnnotatedAnswer`) works.
- D3: Primary. `d3TupleArg` passes.
- D4: a. `@MainActor final class MockScreen: Mock, Screen` compiles.
- D5: Fallback. The brief's `InOrderBuilder` does not compile, and `d5InOrderRecordsEveryLine` therefore could not pass.
- D1-yield: completed=false

## Notes
- `run-probes.sh` was used unchanged. The `$BIN/Modules` directory does not exist on this toolchain, so the script's fallback to `$BIN` (`.build/out/Products/Debug`, which holds `Probe.swiftmodule`) is what makes `-I` work; `-target arm64-apple-macosx26.0` works.
- Every build emits this warning (not an error): `warning: class 'ProbeClient' must restate inherited '@unchecked Sendable' conformance` (Probe.swift, `public final class ProbeClient: Mock, Client`). Generated mocks should restate `@unchecked Sendable`.
- **Why `d1SyncWhenOnMainActor` fails, and a likely fix.** Diagnostics (not part of the brief): inside a `@MainActor` test, `when { try await client.fetch(id:) }` leaves `completed=false, members=[]`, because the closure inherits MainActor isolation and awaiting the nonisolated async `fetch` hops to the global executor, so `Task.immediate` returns before the mock records. A sync closure in the same MainActor async test completed fine (`completed=true`, `members=["save(_:)"]`). Marking the mock's async member `nonisolated(nonsending) public func fetch(id:) async throws -> User` made `d1SyncWhenOnMainActor` pass (`completed=true`, `members=["fetch(id:)"]`), as well as all other d1 tests, with `D1-yield completed=false` unchanged. So async mock members probably need to be `nonisolated(nonsending)` for the sync-`when` design to work from MainActor; this was only tried on `ProbeClient.fetch`, with the protocol requirement unchanged.
- `when { client.cached(id: "42") }.thenThrow(...)` compiling is an inference artifact: standalone, the closure overload infers `E = Never` (`Stub<User?, Never>`); with a chained `thenThrow` member (which needs `Failure == any Error`) the solver infers `any Error`. A non-throwing closure is therefore not protected by the type system when `.thenThrow` is chained. The autoclosure form `when(client.cached(id:)).thenThrow(...)` is rejected.
- D5 exploration (not part of the brief): an async-builder alternative (`static func buildExpression<T>(_ e: @autoclosure () async throws -> T) async` with an `async` builder closure) compiles, but then every line at the call site needs `await` (`error: expression is 'async' but is not marked with 'await'`), which defeats the no-`await` goal. It is not a drop-in fix.
