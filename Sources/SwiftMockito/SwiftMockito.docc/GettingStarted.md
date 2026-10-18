# Getting started

Add SwiftMockito to a test target, generate a mock, and write a first test.

## Overview

SwiftMockito has two parts: the `SwiftMockito` library, which your tests call, and the
`SwiftMockitoPlugin` build-tool plugin, which generates a mock for every protocol you mark with
``GenerateMock(_:)``. The mocks are generated on every build, so there is nothing to run and
nothing to commit.

### Add the package

**Swift Package Manager:** link `SwiftMockito` to your test target and attach its plugin:

```swift
dependencies: [
    .package(url: "https://github.com/gytisptasinskas/SwiftMockito", from: "0.1.0"),
],
targets: [
    .testTarget(
        name: "AppTests",
        dependencies: ["App", .product(name: "SwiftMockito", package: "SwiftMockito")],
        plugins: [.plugin(name: "SwiftMockitoPlugin", package: "SwiftMockito")]
    ),
]
```

**Xcode:** choose File > Add Package Dependencies with the URL above. Link `SwiftMockito` to
your test target, and add `SwiftMockitoPlugin` under the test target's Build Phases > Run Build
Tool Plug-ins. On the first build, Xcode asks you to trust the SwiftMockito macro and plugin;
choose **Trust & Enable**. On CI, pass `-skipMacroValidation -skipPackagePluginValidation` to
`xcodebuild`. The
[step-by-step setup](https://github.com/gytisptasinskas/SwiftMockito/blob/main/docs/xcode-plugin-verification.md)
covers the details.

### Write a test

The examples in this documentation mock this protocol and use it through a `UserRepository`:

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

Put ``GenerateMock(_:)`` on the suite, then create the generated `MockClient`, stub it with
``when(_:fileID:filePath:line:column:)``, and verify the calls:

```swift
import Testing
import SwiftMockito
@testable import App

@GenerateMock(Client.self)
struct UserRepositoryTests {
    let client = MockClient()

    @Test func returnsCachedUser() async throws {
        when(client.cached(id: "42")).thenReturn(.fixture)

        let user = try await UserRepository(client: client).user(id: "42")

        #expect(user == .fixture)
        verify(client.cached(id: "42")).called(1)
    }

    @Test func doesNotSaveWhenFetchFails() async {
        when(client.cached(id: "42")).thenReturn(nil)
        await when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)

        await #expect(throws: ClientError.offline) {
            try await UserRepository(client: client).user(id: "42")
        }
        verifyNever { try client.save(.fixture) }
    }
}
```

Use the plain form for synchronous calls, and the `{ … }` closure form when the call needs
`try` or `await`. Put `await` in front of the closure form when the call inside needs `await`.

### Cheat sheet

| You want to | Write |
|---|---|
| Stub a plain call | `when(client.cached(id: "42")).thenReturn(.fixture)` |
| Stub a `throws` call | `when { try client.save(.fixture) }.thenThrow(ClientError.offline)` |
| Stub an `async` call | `await when { try await client.fetch(id: "42") }.thenReturn(.fixture)` |
| Return values in sequence | `.thenReturn(nil, .fixture)` (the last one repeats) |
| Throw | `.thenThrow(ClientError.offline)` |
| Compute the result or call a callback | `.thenAnswer { id in … }` |
| Check a call happened | `verify(client.cached(id: "42")).called(1)` (also `atLeast:` / `atMost:`) |
| Check a call never happened | `verifyNever { try client.save(.fixture) }` |
| Check the order of calls | `await verifyInOrder { … }` |
| Check nothing else was called | `verifyNoMoreInteractions(client)` |
| Start over | `reset(client)` |

### Good to know

- **No argument matchers.** Arguments are compared by value: `fetch(id: "42")` only matches
  `"42"`. Closure arguments are ignored when matching. See <doc:Matching>.
- **Stub every call that returns a value.** If a non-throwing call that returns a value has no
  stub, that test fails and the call returns a dummy value. An unstubbed throwing call throws ``MissingStubError``, and an
  unstubbed `Void` call returns normally. See <doc:Stubbing#Unstubbed-calls>.
- **The newest stub wins** when several stubs match a call.
- **Callbacks in `thenAnswer` need typed parameters**:
  `{ (id: String, completion: @escaping (Result<User, Error>) -> Void) in completion(.success(.fixture)) }`.
- **`@MainActor` protocols** are mocked as `@MainActor` too; stub and verify them from
  `@MainActor` tests.
