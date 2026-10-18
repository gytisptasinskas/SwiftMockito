# SwiftMockito

Mockito-style mocks for Swift protocols. Mark a protocol with `@GenerateMock`, and a build plugin generates its `Mock…` class. Then **stub** it with `when`, run your code, and **verify** the calls with `verify`.

```swift
when(client.cached(id: "42")).thenReturn(.fixture)
// … run the code under test …
verify(client.cached(id: "42")).called(1)
```

> **Proof of concept.** SwiftMockito tests an idea: Mockito-style mock generation for Swift, where you mark a protocol and a build plugin generates its mock. It is not production-ready yet, and its API may change.

Works with Swift Testing and XCTest. Requires Swift 6.2+ and iOS 26 / macOS 26, in Swift 6 language mode. Tested with Xcode 27.

## Quick start

### 1. Add the package

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

**Xcode:** File > Add Package Dependencies with the URL above. Link `SwiftMockito` to your test target, and add `SwiftMockitoPlugin` under the test target's Build Phases > Run Build Tool Plug-ins. On the first build, choose **Trust & Enable**. [Step-by-step setup](docs/xcode-plugin-verification.md).

### 2. Write a test

Put `@GenerateMock` on the suite. The mock is generated on every build, so there is nothing to run and nothing to commit.

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
        when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)

        await #expect(throws: ClientError.offline) {
            try await UserRepository(client: client).user(id: "42")
        }
        verifyNever { try client.save(.fixture) }
    }
}
```

## Cheat sheet

| You want to | Write |
|---|---|
| Stub a plain call | `when(client.cached(id: "42")).thenReturn(.fixture)` |
| Stub an `async` or `throws` call | `when { try await client.fetch(id: "42") }.thenReturn(.fixture)` |
| Return values in sequence | `.thenReturn(nil, .fixture)` (the last one repeats) |
| Throw | `.thenThrow(ClientError.offline)` |
| Compute the result or call a callback | `.thenAnswer { id in … }` |
| Check a call happened | `verify(client.cached(id: "42")).called(1)` (also `atLeast:` / `atMost:`) |
| Check a call never happened | `verifyNever { try client.save(.fixture) }` |
| Check the order of calls | `await verifyInOrder { … }` |
| Check nothing else was called | `verifyNoMoreInteractions(client)` |
| Start over | `reset(client)` |

Use the plain form for synchronous calls, and the `{ … }` closure form when the call needs `try` or `await`.

## Good to know

- **No argument matchers.** Arguments are compared by value: `fetch(id: "42")` only matches `"42"`. Closure arguments are ignored when matching.
- **Stub every call that returns a value.** If a non-throwing call that returns a value has no stub, the whole test run stops. An unstubbed throwing call throws `MissingStubError`, and an unstubbed `Void` call just returns.
- **The newest stub wins** when several stubs match a call.
- **Callbacks in `thenAnswer` need typed parameters**: `{ (id: String, completion: @escaping (Result<User, Error>) -> Void) in completion(.success(.fixture)) }`.
- **`@MainActor` protocols** are mocked as `@MainActor` too; stub and verify them from `@MainActor` tests.

## Example app

[`example/`](example/README.md) is a small SwiftUI MVVM app on top of the JSONPlaceholder API, with its view models tested against generated mocks. Open `example/app.xcodeproj` and press ⌘U.

## More

The [guide](docs/guide.md) covers everything else:
- properties, subscripts and setters
- how arguments are matched
- dummies and `provideDummy`
- generating mocks you commit to the repo, from the command line
- what isn't supported, and known limitations

## Development

```bash
swift test                                                 # runtime and generator tests
swift test --package-path IntegrationTests/PluginFixture   # plugin end to end
bash IntegrationTests/CheckedInMocks/check.sh              # checked-in mocks are current
bash Scripts/check-public-api.sh                           # the public API has no matcher symbols
```
