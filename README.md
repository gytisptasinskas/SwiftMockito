# SwiftMockito

SwiftMockito is a mocking library for Swift protocols, modelled on Flutter's Mockito. You generate a `Mock…` class for each protocol, **stub** it with `when(…).thenReturn(…)`, run the code under test, and **verify** the calls with `verify(…)`. Arguments are compared by value, and there are no matchers.

```swift
when(client.cached(id: "42")).thenReturn(.fixture)
// … run the code under test …
verify(client.cached(id: "42")).called(1)
```

> **Proof of concept.** SwiftMockito tests an idea: Mockito-style mock generation for Swift, where you mark a protocol and a build plugin generates its mock. It is not production-ready yet, and its API may change.

## Requirements

Requires Swift 6.2+ and macOS 26 / iOS 26 (`Task.immediate`). Tested with Swift 6.4 (Xcode 27) on macOS 27; earlier 6.x toolchains are untested. Use Swift 6 language mode.

## Installation

Add the package to `Package.swift`, link `SwiftMockito` to your test target, and attach the build-tool plugin to it:

```swift
dependencies: [
    .package(path: "../SwiftMockito"),
],
targets: [
    .testTarget(
        name: "AppTests",
        dependencies: ["App", .product(name: "SwiftMockito", package: "SwiftMockito")],
        plugins: [.plugin(name: "SwiftMockitoPlugin", package: "SwiftMockito")]
    ),
]
```

Once the package is published, replace the path dependency with `.package(url: "<repository URL>", from: "0.1.0")`.

In an Xcode project, add the package, add `SwiftMockitoPlugin` under the test target's Build Phases > Run Build Tool Plug-ins, and link `SwiftMockito` to the test target. See [docs/xcode-plugin-verification.md](docs/xcode-plugin-verification.md) for the step-by-step setup. The first build asks you to trust the SwiftMockito macro and plugin; choose Trust & Enable. On CI, pass `-skipMacroValidation -skipPackagePluginValidation` to `xcodebuild`.

## Example app

[`example/`](example/README.md) is a small SwiftUI app built with MVVM on top of the JSONPlaceholder API. Its view models are tested against a generated mock. Open `example/app.xcodeproj` and press ⌘U.

## Generating mocks

Mark the protocols a test suite mocks, on the suite itself:

```swift
import SwiftMockito
@testable import App

@GenerateMock(Client.self)
struct UserRepositoryTests {
    let client = MockClient()
    // …
}
```

`@SwiftMockito.GenerateMock(…)` works too. The marker can sit on any declaration in the test target, such as a suite or an empty `enum Mocks {}`. Mocks belong to the whole test target, so several suites can mark the same protocol and still share one `MockClient`. The build plugin finds `Client` in your test target's dependencies and generates a `MockClient` class with the same signatures, effects and access level. Protocols declared `internal` need `@testable import` of their module, as above.

The examples below mock this protocol and use it through a `UserRepository`:

```swift
protocol Client {
    var token: String { get set }
    var currentUser: User { get }
    func cached(id: String) -> User?
    func fetch(id: String) async throws -> User
    func save(_ user: User) throws
    func load(id: String, completion: @escaping (Result<User, Error>) -> Void)
}
```

### Checked-in mocks (CLI)

The same generator runs from the command line, for CI or for mocks you commit to the repository:

```bash
swift run SwiftMockitoGenerator generate \
  --test-module AppTests \
  --output Tests/AppTests/Generated \
  --marked Tests/AppTests/Mocks.swift \
  --source-dir App=Sources/App
```

| Flag | Meaning |
|---|---|
| `--test-module` | Name of the test module the mocks belong to. |
| `--output` | Directory that receives the `Mock….swift` files. |
| `--marked` | A test file that contains `@GenerateMock`. Repeatable. |
| `--source Module=path` | One source file that declares protocols or dummy types. Repeatable. |
| `--source-dir Module=path` | Every `.swift` file under a directory. Repeatable. |
| `--source-list file` | A file with one `Module=path` per line, read like `--source`. The build plugin passes its sources this way so large dependency graphs stay under the command-line length limit. Repeatable. |
| `--expect MockName.swift` | A file that must exist in the output. If no active marker produces it, a placeholder file is written. A marker that produces a file not listed is an error. Repeatable. |

Exit codes: 0 on success, 1 for generation or write errors, 2 for a usage error or an unreadable input.

`IntegrationTests/CheckedInMocks/check.sh` runs the generator and diffs its output against the checked-in files, which is how CI keeps them current.

## Stubbing

Members that are synchronous and do not throw are stubbed with a plain expression. Members that need `try` or `await` use the closure form. Neither form needs an `await` in front of `when`:

```swift
when(client.cached(id: "42")).thenReturn(nil)
when { try await client.fetch(id: "42") }.thenReturn(.fixture)
```

**`thenReturn`** takes one value, or several that are returned in sequence. The last value repeats:

```swift
when(client.cached(id: "42")).thenReturn(nil, .fixture)
#expect(client.cached(id: "42") == nil)
#expect(client.cached(id: "42") == .fixture)
#expect(client.cached(id: "42") == .fixture)
```

**`thenThrow`** is for throwing members. Calling it on a `when(expr)` form of a non-throwing member is a compile error. In the closure form it is a runtime failure reported at the call site.

```swift
when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)
```

**`thenAnswer`** receives the call's arguments and returns the result. Single-parameter answers infer their type. When a member takes a callback, annotate the closure's parameters:

```swift
when(client.load(id: "42", completion: { _ in }))
    .thenAnswer { (id: String, completion: @escaping (Result<User, Error>) -> Void) in
        completion(.success(User(id: id, name: "Gytis")))
    }
```

Pass any closure for the callback argument when you stub; closures are not part of matching.

Non-escaping closure parameters, such as `func perform(_ work: () -> Void)`, work the same way. The answer annotates them `@escaping` and may call them, but must not keep them:

```swift
when(worker.perform({})).thenAnswer { (work: @escaping () -> Void) in work() }
```

Properties are stubbed by their getter, and subscripts by their arguments:

```swift
when(client.currentUser).thenReturn(.fixture)
when(client.token).thenReturn("t")
when(catalog[1]).thenReturn("one")
```

When several stubs match a call, the newest one wins.

## Verifying

`verify` asserts that at least one matching, not yet verified call happened, and marks the matching calls as verified. `.called(_:)`, `.called(atLeast:)` and `.called(atMost:)` tighten the count.

```swift
verify(client.cached(id: "42")).called(1)
verify { try await client.fetch(id: "42") }.called(atLeast: 1)
verifyNever { try client.save(.fixture) }
verifyNoMoreInteractions(client)
```

`verify`, `verifyNever` and `verifyInOrder` need no `await` in front, even when the expression inside them does.

A property setter is verified with an assignment inside the closure form:

```swift
client.token = "new"
verify { client.token = "new" }.called(1)
verify(client.token).called(1)   // the getter
```

**`verifyInOrder`** checks relative order only; unrelated calls may happen in between. It has a synchronous form and an `await` form for async tests. Every line is recorded, including `try` and `await` lines, and the function itself does not throw:

```swift
await verifyInOrder {
    client.cached(id: "42")
    try await client.fetch(id: "42")
    try client.save(.fixture)
}
```

A throwing line is recorded and the block continues. A throwing member with no placeholder, meaning any return type that has no built-in or synthesized dummy and not only a generic one, cannot continue the block, so register a dummy with `provideDummy` for that type first. Throwing members get no build warning for this.

**`reset(client)`** clears the mock's stubs and recorded calls.

Each `when` or `verify` expression must record exactly one mock call. Zero or several is reported as a misuse at the call site.

### Actors

A mock of a `@MainActor` protocol, or of a protocol that inherits from one, is isolated to the main actor too. It is stubbed and verified from a `@MainActor` test:

```swift
@MainActor
@Suite struct ScreenAcceptanceTests {
    let screen = MockScreen()

    @Test func globalActorMockWorks() {
        when(screen.isVisible).thenReturn(true)
        screen.render(title: "Home")
        #expect(screen.isVisible)
        verify(screen.render(title: "Home")).called(1)
    }
}
```

## Exact matching

There are no argument matchers: no `any()`, wildcards, predicates or captors. A call is identified by its arguments, compared by value.

- `Equatable` values compare with `==`. That includes optionals, collections and tuples of equatable values.
- Class instances compare by identity (`===`), unless the class is `Equatable`, in which case `==` is used.
- Closure parameters are left out of the key, so `verify(catalog.notify({}))` matches any closure.
- Generic methods include the concrete generic types (`T.self`) in the key.
- Overloads are separate members.
- Variadic arguments match as an array.
- Any other non-`Equatable` value is unsupported. Stubbing or verifying such a call reports `UnsupportedExactMatchingError`, naming the member, the argument position and the type. Real calls still work.

These examples use a `MockCatalog` named `catalog`:

```swift
// Class arguments match by identity
let a = Reference(), b = Reference()
when(catalog.describe(a)).thenReturn("a")
verifyNever(catalog.describe(b))

// Tuples match by value
catalog.tag((1, "x"))
verify(catalog.tag((1, "x"))).called(1)

// The generic type is part of the key
when { try catalog.decode(Data(), as: Int.self) }.thenReturn(7)
when { try catalog.decode(Data(), as: String.self) }.thenReturn("seven")
```

## Unstubbed calls

A call that matches no stub behaves according to the member:

| Member | Result |
|---|---|
| Throwing | Throws `MissingStubError`. |
| Non-throwing, returns a value | Reports the failure (member, actual arguments, configured stubs, location), **then traps, which ends the whole test process**. |
| Returns `Void` | Recorded, then returns normally. |

```swift
@Test func missingStubOnThrowingMemberThrows() async {
    await #expect(throws: MissingStubError.self) { try await client.fetch(id: "1") }
}

@Test func unstubbedVoidMemberReturns() {
    client.load(id: "1") { _ in Issue.record("completion must not run") }
    verify(client.load(id: "1", completion: { _ in })).called(1)
}
```

Stub every non-throwing member that returns a value, or the whole test run stops at the first one you forgot.

The same applies while recording: a non-throwing member whose return type has no dummy (see Dummies below) is reported as `MissingDummyError`, then traps.

## Dummies

While `when` or `verify` records a call, a non-throwing member must return something. SwiftMockito returns a dummy value. Dummies exist only while recording and never reach the code under test.

A dummy comes from, in order:

1. A value you registered with `provideDummy(_:)`.
2. A built-in: `Void`, `Bool`, integer and floating-point types, `String`, `Character`, `Optional` (`nil`), `Array`, `Dictionary`, `Set`, `Data`, `Date`, `URL`, `UUID` and `Result`.
3. A fallback the generator synthesizes from the type's source declaration: a struct from its memberwise or accessible initializer, an enum from its first case, a class from an accessible initializer, a tuple from the dummies of its elements, and a protocol as a stand-in whose members trap if called.

When the generator cannot build a dummy, it reports a build warning at the `@GenerateMock` declaration. For a protocol with `func size() -> CGSize`:

```
warning: MockP.size(): cannot build a dummy CGSize (not declared in sources); register one with provideDummy(_:) before stubbing or verifying it
```

Register one before you stub or verify that member. The registry is process-wide and holds immutable values:

```swift
provideDummy(CGSize(width: 1, height: 1))
```

`provideDummy` registers by exact type, and the value must be `Sendable`. For a member that returns `Base`, register a `Base`; `provideDummy(Sub() as Base)` requires `Base: Sendable`:

```swift
provideDummy(Sub() as Base)
```

If a non-throwing member is recorded and no dummy exists for its return type, SwiftMockito reports `MissingDummyError` (the type and the member, with a hint to call `provideDummy`) **and then traps, which ends the whole test process**.

## Not supported

- Argument matchers: no `any()`, wildcards, predicates or argument captors.
- Default stubs or "nice mock" behavior. An unstubbed call that returns a value fails.
- Static requirements, initializers, `Self` requirements and associated types.
- Subscripts with `async` or `throws` getters, and generic subscripts.
- `rethrows` members.
- Objective-C protocols (`@objc`, or `optional` requirements).
- Members named `runtime` or `arg`, which collide with names the generated mock uses. Parameters named `arg` are fine.
- `Actor`-constrained protocols (`protocol P: Actor`).
- Protocols that declare no global actor but inherit different ones from their parents.
- Class mocking, and protocols available only in binary frameworks.
- The Objective-C runtime, swizzling and reflection-based dispatch.

## Known limitations

- `when`, `verify`, `verifyNever` and the synchronous `verifyInOrder` cannot be called from inside a custom actor *instance*: they report that the expression suspended. Global actors such as `@MainActor` or a custom `@globalActor` work when the test is isolated to them.
- Mocks of global-actor protocols are stubbed and verified from tests isolated to that actor.
- `thenAnswer` bodies run, and `thenReturn` values are handed over, on whatever thread or actor the code under test calls the mock from. Don't touch actor-isolated test state from an answer.
- A `when` closure must evaluate to the member's own return type. Wrapping the call in `try?`, `??` or a conversion is reported at the `when`, and no stub is installed.
- The generator looks up protocols, inherited protocols, typealiases and dummy types by name. A name declared in more than one dependency module is an error at the marker; rename one of them. A declaration in the test module itself shadows the others.
- A `thenAnswer` must not store a non-escaping closure parameter, or anything that captures it, for use after it returns. The mock lends the closure through `withoutActuallyEscaping`, so in debug builds such an answer traps with `closure argument was escaped in withoutActuallyEscaping block`, pointing at the generated mock. Optimized builds do not check, and calling the stored closure later is undefined behavior.
- `thenAnswer` closures with callback parameters need annotated parameter types.
- `provideDummy` registers by exact type: use `provideDummy(Sub() as Base)` for a `Base` return.
- Types whose initializers are not reachable from the test module produce a build warning and need `provideDummy`.
- In Xcode, the first build asks you to trust the SwiftMockito macro and plugin. On CI, pass `-skipMacroValidation -skipPackagePluginValidation` to `xcodebuild`.
- The Xcode plugin derives the test module name from the target's display name, so a customised `PRODUCT_MODULE_NAME` is not supported. See [docs/xcode-plugin-verification.md](docs/xcode-plugin-verification.md).

## Development

```bash
swift test                                           # runtime and generator tests
swift test --package-path IntegrationTests/PluginFixture   # plugin end to end
bash IntegrationTests/CheckedInMocks/check.sh        # checked-in mocks are current
bash Scripts/check-public-api.sh                     # the public API has no matcher symbols
```
