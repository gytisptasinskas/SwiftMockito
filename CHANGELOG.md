# Changelog

All notable changes to SwiftMockito. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/); while SwiftMockito is a proof of concept (0.x), a minor version may contain breaking changes, and they are listed under **Changed** with a migration note.

## [Unreleased]

### Added

- Mocks of protocols with associated types: `protocol Repository { associatedtype Item }` generates a generic `MockRepository<Item>`. Constraints carry over; associated types with a `where` clause are still unsupported. ([#8](https://github.com/gytisptasinskas/SwiftMockito/pull/8))
- A warning, not a failure, when an unstubbed `Void` member is called with a completion handler it will never call, since code waiting for it would hang. ([#6](https://github.com/gytisptasinskas/SwiftMockito/pull/6))
- XCTest acceptance tests and an XCTest section in the guide. ([#7](https://github.com/gytisptasinskas/SwiftMockito/pull/7))
- CI tests the example app against the pull request's code (`Scripts/test-example.sh`). ([#9](https://github.com/gytisptasinskas/SwiftMockito/pull/9))

### Changed

- **Breaking: minimum is now iOS 17 / macOS 14** (was iOS 26 / macOS 26). The closure forms of `when`, `verify`, `verifyNever` and `verifyInOrder` no longer run their closure synchronously through `Task.immediate`; when the call inside needs `await`, the form is `async` too. **Migration:** put `await` in front wherever the closure contains `await`:

  ```swift
  // 0.1.0
  when { try await client.fetch(id: "42") }.thenReturn(.fixture)
  // now
  await when { try await client.fetch(id: "42") }.thenReturn(.fixture)
  ```

  Closures without `await` (`when { try client.save(x) }`, `verify { client.token = "new" }`) and the plain forms (`when(client.cached(id: "42"))`) are unchanged. The compiler points at every line that needs `await`. The `isolation:` parameter of the closure forms is gone.
- `when`, `verify`, `verifyNever` and `verifyInOrder` now work from inside a custom actor instance, and an expression may suspend before reaching the mock; both used to be reported as misuse.
- A forgotten stub on a non-throwing member that returns a value now fails only that test and returns a dummy, instead of ending the whole test process. It still traps when no dummy exists for the return type. ([#6](https://github.com/gytisptasinskas/SwiftMockito/pull/6))
- Mocks from 0.1.0 still compile: the new `MockRuntime` parameters (`dummy:`, `callbacks:`) have defaults. Regenerate them to get the new behaviour.

### Fixed

- The example app adds SwiftMockito from GitHub, so the Xcode app runs the plugin, and it opens in Xcode 26 again (project format 77). ([#5](https://github.com/gytisptasinskas/SwiftMockito/pull/5), [#9](https://github.com/gytisptasinskas/SwiftMockito/pull/9))

## [0.1.0] - 2026-10-17

First release, a proof of concept.

### Added

- `@GenerateMock(P.self)` marker and the `SwiftMockitoPlugin` build-tool plugin, which generate a `MockP` class for each marked protocol on every build, for Swift packages and Xcode projects.
- `SwiftMockitoGenerator` command-line tool for mocks you commit to the repository.
- Stubbing with `when(…)` and `when { … }`: `thenReturn` (one value or a sequence), `thenThrow`, and `thenAnswer` (sync or `async`, with the call's arguments).
- Verification: `verify(…).called(_:)`, `called(atLeast:)`, `called(atMost:)`, `verifyNever`, `verifyInOrder` (sync and `await` forms), `verifyNoMoreInteractions` and `reset`.
- Exact matching by value with no argument matchers: `Equatable` values by `==`, class instances by identity, closures left out of matching, generic types part of the key.
- Dummy values for recording, with built-ins, generator-synthesized fallbacks and `provideDummy(_:)`.
- Support for `async`/`throws` members, properties, subscripts, non-escaping closure parameters, overloads, variadics, generic methods, and `@MainActor` (global-actor) protocols.
- Swift Testing and XCTest failure reporting at the line that called `when`/`verify`.
- DocC documentation, a guide, and an example SwiftUI app tested with generated mocks.

[Unreleased]: https://github.com/gytisptasinskas/SwiftMockito/compare/0.1.0...HEAD
[0.1.0]: https://github.com/gytisptasinskas/SwiftMockito/releases/tag/0.1.0
