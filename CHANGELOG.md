# Changelog

All notable changes to SwiftMockito. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/); while SwiftMockito is a proof of concept (0.x), a minor version may contain breaking changes, and they are listed under **Changed** with a migration note.

## [Unreleased]

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
