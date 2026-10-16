# SwiftMockito — specification

## Overview

SwiftMockito is a Swift package for test doubles, modeled on Flutter Mockito. It generates type-safe mocks from Swift protocols and gives tests the same vocabulary Flutter developers know:

```swift
when(client.cached(id: "42")).thenReturn(.fixture)
verify(client.cached(id: "42")).called(1)
```

It targets iOS/macOS test targets using XCTest or Swift Testing, Swift 6 language mode, strict concurrency.

## Goals

- Generate mocks from protocols marked in test code.
- Exact-argument stubbing and verification only.
- Support synchronous, `async`, `throws`, `async throws` methods, properties (get/set), subscripts, overloads, generic methods, callback parameters, and global-actor-isolated protocols.
- Provide `thenReturn`, `thenThrow`, `thenAnswer`, `verify`, `verifyNever`, exact/at-least/at-most call counts, `verifyInOrder`, `verifyNoMoreInteractions`, and `reset`.
- Synthesize the dummy values needed while recording, so users rarely call `provideDummy`.
- Clear diagnostics naming the member, expected arguments, actual recorded calls, configured stubs, and source location.

## Non-goals

- No argument matchers: no `any()`, wildcards, predicates, or argument captors.
- No default stubs or "nice mock" behavior. Unstubbed real calls returning a value fail.
- Not supported: static requirements, initializers, `Self` requirements, associated types, `Actor`-constrained protocols (`protocol P: Actor`), class mocking, protocols available only in binary frameworks.
- No Objective-C runtime, swizzling, reflection-based dispatch, unsafe memory tricks, thread parking, or any dependency in production code.

## Public API

```swift
let client = MockClient()

// Sync, non-throwing members: plain expression
when(client.cached(id: "42")).thenReturn(.fixture)
when(client.currentUser).thenReturn(.fixture)

// Members needing `try` or `await`: closure form
when { try await client.fetch(id: "42") }.thenReturn(.fixture)
when { try client.save(.fixture) }.thenThrow(TestError.offline)

// Callback parameters: pass any closure; it is ignored for matching
when(client.load(id: "42", completion: { _ in })).thenAnswer { id, completion in
    completion(.success(User(id: id, name: "Gytis")))
}

// Sequential results
when(client.cached(id: "42")).thenReturn(nil, .fixture)

// Verification
verify(client.cached(id: "42")).called(1)
verify { try await client.fetch(id: "42") }.called(atLeast: 1)
verify { client.token = "" }.called(1)            // property setter
verifyNever { try client.save(.fixture) }
await verifyInOrder {
    client.cached(id: "42")
    try await client.fetch(id: "42")
    try client.save(.fixture)
}
verifyNoMoreInteractions(client)
reset(client)
```

### Stubbing

- `thenReturn(_ values: Return...)` — one value, or several returned in sequence; the last repeats.
- `thenThrow(_ error:)` — available only for throwing members (enforce at compile time where possible, otherwise runtime error).
- `thenAnswer(_ body:)` — receives the call's arguments, typed per member (use parameter packs), including callback arguments. The closure carries the member's effects (`async`, `throws`).
- When several stubs match, the newest wins.

### Verification

- `verify(...)` immediately asserts at least one matching unverified call and marks matching calls as verified. Returns a `@discardableResult` value.
- `.called(_ n: Int)`, `.called(atLeast:)`, `.called(atMost:)` tighten the count check.
- `verifyNever(...)` asserts zero matching calls.
- `verifyInOrder { ... }` (result builder, sync and `async` overloads) checks relative order only; unrelated calls may occur in between. Matching calls are marked verified. The builder accepts `try`/`await` expressions and the function itself does not throw.
- `verifyNoMoreInteractions(mock)` passes only if every recorded call has been verified.
- `reset(mock)` clears stubs and recorded calls.
- Each `when`/`verify` expression must record exactly one mock call. Zero or more than one is a misuse error with the source location.

## How recording works

`when`, `verify`, `verifyNever`, and `verifyInOrder` evaluate their expression inside a capture context stored in a `@TaskLocal`. This keeps parallel tests isolated and survives `await`. Do not use global mutable state.

Generated members check the context first:

```swift
func fetch(id: String) async throws -> User {
    if let capture = Capture.current {
        capture.record("fetch(id:)", key: [arg(id)])
        throw CaptureSignal()                 // caught by when/verify
    }
    return try await runtime.invoke("fetch(id:)", key: [arg(id)], args: id)
}

var currentUser: User {
    if let capture = Capture.current {
        capture.record("currentUser", key: [])
        return Dummies.resolve(User.self, fallback: Self._dummyUser)
    }
    return runtime.invokeGetter("currentUser")
}
```

| Member shape | While recording |
|---|---|
| `throws` / `async throws` | record, then throw `CaptureSignal` |
| returns `Void` | record, return |
| non-throwing, returns `T` | record, return a dummy `T` |

### Dummy values

Dummies exist only while recording and are never returned to code under test.

`Dummies.resolve` looks up in this order:

1. Values registered with `provideDummy(_:)`.
2. Built-ins: `Void`, `Bool`, integer and floating-point types, `String`, `Character`, `Optional` (`nil`), `Array`, `Dictionary`, `Set`, `Data`, `Date`, `URL`, `UUID`, `Result` (via its success type), tuples of supported types.
3. A fallback the generator synthesizes from the return type's source declaration:
   - `struct` → memberwise or accessible init, with dummy arguments, recursively.
   - `enum` → first case, payloads filled with dummies.
   - `class` → accessible init with dummy arguments.
   - protocol / `any P` → a generated `_DummyP: P` whose members trap if called.

If the generator cannot build a dummy (SDK or binary types without a built-in, only inaccessible initializers, generic return types like `func decode<T>() -> T`), it emits a build warning pointing at the `@GenerateMock` declaration. At runtime, a missing dummy raises `MissingDummyError` naming the type and suggesting `provideDummy`.

The dummy registry is process-wide and stores immutable values only.

## Real calls

Outside capture mode, a generated member records the call, finds the newest matching stub, and returns, throws, or runs the answer.

If no stub matches a non-`Void` member:
- throwing members throw `MissingStubError`;
- non-throwing members report the failure through the test reporter (member, actual arguments, configured stubs, location), then trap. Document that this ends the test process.

Unstubbed `Void` calls are recorded and return normally.

## Exact matching

Arguments are compared by value; there is no matcher API.

Each call has:
- a **key** of comparable arguments, used for matching stubs and verification;
- the **raw arguments**, including closures, passed to `thenAnswer`.

Generated code builds keys with `arg(_:)`. Overload resolution picks the strategy:

```swift
public func arg<T: Equatable>(_ v: T) -> Argument                 // ==
public func arg<T: AnyObject & Equatable>(_ v: T) -> Argument     // ==
public func arg<T: AnyObject>(_ v: T) -> Argument                 // identity (===)
@_disfavoredOverload
public func arg<T>(_ v: T) -> Argument  // runtime `as? any Equatable`, else .unsupported
```

Rules:
- Equatable values, including optionals, collections, and tuples of equatable values, compare with `==`.
- Non-equatable class instances compare by identity.
- Closure parameters are left out of the key by the generator. A call is identified by its non-closure arguments.
- For generic methods the key includes the concrete generic types (`T.self`).
- Any other non-equatable value is `.unsupported`. Stubbing or verifying such a call fails with `UnsupportedExactMatchingError` (member, argument position, type). Real calls still work.

These checks happen at runtime because the generator only sees syntax and cannot prove `Equatable` conformance.

## Test reporting

One reporter handles all failures: `Issue.record` when running under Swift Testing (`Test.current != nil`), otherwise `XCTFail`. Every public function takes the caller's source location (`#fileID`, `#filePath`, `#line`, `#column`).

## Mock generation

Mark protocols in test code:

```swift
@GenerateMock(Client.self)
enum Mocks {}
```

- `@GenerateMock` is a marker macro that expands to nothing. A macro can't see the protocol's body, and annotating production code would add a production dependency, so generation runs in a build plugin.
- The SPM build-tool plugin parses the marked test sources with SwiftSyntax. It then finds the protocol, its inherited protocols, typealiases, and return-type declarations (for dummies) in the source files of the test target's dependencies.
- It writes a deterministic `MockClient.swift` to the plugin work directory. The mock is a `final class` subclassing `Mock` and conforming to the protocol, with the same signatures, effects, and global-actor isolation. Its access level matches the protocol; internal protocols need `@testable import`.
- Generated code must compile in Swift 6 mode with strict concurrency. Runtime storage is lock-protected and `@unchecked Sendable`.
- Diagnostics (unsupported members, dummies it can't build, name collisions) point at the `@GenerateMock` declaration.
- Xcode projects use the same plugin through `XcodeProjectPlugin`. A CLI runs the same generator for CI or checked-in mocks.

## Package layout

| Target | Purpose |
|---|---|
| `SwiftMockito` | Runtime and public API |
| `SwiftMockitoMacros` | `@GenerateMock` marker macro |
| `SwiftMockitoGenerator` | SwiftSyntax generator executable / CLI |
| `SwiftMockitoPlugin` | Build-tool plugin (SPM + `XcodeProjectPlugin`) |
| `SwiftMockitoTests` | Runtime tests |
| `GeneratorTests` | Fixture-based snapshot and compile tests |

## Example

```swift
// Production code
protocol Client {
    var token: String { get set }
    var currentUser: User { get }
    func cached(id: String) -> User?
    func fetch(id: String) async throws -> User
    func save(_ user: User) throws
    func load(id: String, completion: @escaping (Result<User, Error>) -> Void)
}
```

```swift
// Test code
import Testing
import SwiftMockito
@testable import MyApp

@GenerateMock(Client.self)
enum Mocks {}

@Suite struct UserRepositoryTests {
    let client = MockClient()
    var sut: UserRepository { UserRepository(client: client) }

    @Test func returnsCachedUserWithoutNetwork() async throws {
        when(client.cached(id: "42")).thenReturn(.fixture)

        let user = try await sut.user(id: "42")

        #expect(user == .fixture)
        verify(client.cached(id: "42")).called(1)
        verifyNoMoreInteractions(client)
    }

    @Test func doesNotSaveWhenFetchFails() async {
        when(client.cached(id: "42")).thenReturn(nil)
        when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)

        await #expect(throws: ClientError.offline) { try await sut.user(id: "42") }
        verifyNever { try client.save(.fixture) }
    }

    @Test func legacyLoadDeliversUser() async throws {
        when(client.load(id: "42", completion: { _ in })).thenAnswer { id, completion in
            completion(.success(User(id: id, name: "Gytis")))
        }

        let user = try await sut.legacyUser(id: "42")

        #expect(user.id == "42")
    }
}
```

## Suggested implementation order

1. **Runtime core:** `Mock`, `MockRuntime` (locked storage), `Argument` + `arg(_:)` overloads, stub storage with newest-first lookup, sequential returns, errors.
2. **Capture and API:** `@TaskLocal` capture context, `CaptureSignal`, `when`/`verify`/`verifyNever`/`verifyInOrder`/`verifyNoMoreInteractions`/`reset`, misuse checks, test reporter.
3. **Dummies:** registry, built-ins, `provideDummy`, `MissingDummyError`.
4. **Handwritten mock fixture:** write by hand the code the generator will emit for the example `Client` protocol, and test the whole API against it. This fixes the generated-code shape before writing the generator.
5. **Generator:** SwiftSyntax parsing, protocol and dependency resolution, emitting members for each supported shape, closure exclusion, dummy synthesis, diagnostics, snapshot and compile tests.
6. **Macro and plugin:** marker macro, SPM build-tool plugin, `XcodeProjectPlugin`, CLI, end-to-end integration fixture.
7. **Docs and CI.**

## Acceptance criteria

- Generated code compiles (Swift 6, strict concurrency) and behaves correctly for every supported member shape.
- Runtime tests cover: equality matching, identity matching, closure exclusion, generic-type keys, newest-stub precedence, sequential returns, missing-stub throw and trap paths, typed `thenAnswer` with callbacks, call counts, ordered verification, verified-call consumption, reset, misuse errors, and diagnostic content.
- Capture tests show isolation between parallel tests and across `await`.
- Dummy tests cover built-ins, synthesized struct/enum/class/protocol dummies, `provideDummy` override, build warnings for unbuildable types, `MissingDummyError`, and that dummies never reach code under test.
- Reporter tests cover Swift Testing and XCTest routing.
- The public API contains no matcher symbols.
