# MockitoSwift design

## Intent

Create Swift-native test-double package inspired by Flutter Mockito. It supports handwritten mocks and generated mocks for iOS XCTest. Public stubbing and assertion vocabulary remains `when` and `verify`.

## Goals

- Generate type-safe mocks from marked Swift protocols.
- Support exact-argument stubbing and verification only.
- Support synchronous, `async`, `throws`, `async throws`, properties, subscripts, overloads, generic methods, callbacks, and actor isolation for supported protocol instance requirements.
- Provide `thenReturn`, `thenThrow`, `thenAnswer`, `verifyNever`, exact/at-least/at-most call counts, ordered verification, reset, and no-more-interactions verification.
- Produce diagnostics naming member, expected arguments, actual recorded calls, source location, and configured stubs.

## Explicit exclusions

- No `any()`, named wildcard, predicate matcher, capture matcher, default stub, or nice-mock fallback.
- No automatic return values or default stubs. An unmatched real non-`Void` invocation fails immediately with `MissingStubError`; unstubbed `Void` calls record normally.
- Version one targets protocol instance requirements. Static requirements, initializers, `Self` requirements, and associated types are excluded. Class mocking may be added later only for non-`final`, overridable members.
- No Objective-C runtime swizzling, reflection-based dispatch, or production runtime dependency.

## Public API

```swift
let client = MockClient()

when(client.fetch(id: "42")).thenReturn(.fixture)
when(client.save(.fixture)).thenThrow(TestError.offline)

let user = try await client.fetch(id: "42")

verify(client.fetch(id: "42")).called(once())
verifyNever(client.save(.fixture))
verifyInOrder {
    client.fetch(id: "42")
    client.save(.fixture)
}
verifyNoMoreInteractions(client)
```

Async and throwing members use closure overloads so Swift effects remain explicit:

```swift
when { try await client.fetch(id: "42") }.thenReturn(.fixture)
verify { try await client.fetch(id: "42") }.called(once())
```

`when` and `verify` activate capture mode. Generated methods record invocation shape in capture mode and do not perform normal dispatch. Outside capture mode they record real calls, resolve exact stubs newest-first, and return/throw configured result.

Verified invocations are consumed, matching Flutter Mockito semantics. `verifyNoMoreInteractions` passes only when every recorded invocation has already been verified. `verifyInOrder` consumes matching calls and requires relative order only; unrelated calls may occur between expected calls. `reset(mock)` removes both stubs and recorded invocations.

## Exact matching rule

Direct argument values express equality; there is no matcher API. Stubbed and verified argument types must be `Equatable` (or an `Optional`, collection, or tuple composed of equatable values). Equality uses `==`. Reference-type arguments use their declared `Equatable` conformance; otherwise they are unsupported for exact stubbing/verification. Methods remain generated, but configuration produces a compile-time diagnostic where generator can prove unsupported type, otherwise an actionable runtime error. Closure, opaque, existential, and non-equatable value arguments cannot be configured or verified in v1.

Callback-bearing members still generate and dispatch. `thenAnswer` receives generated, member-specific typed arguments and may invoke callback arguments. Callback values themselves cannot be compared, so calls with callback parameters cannot be configured or verified under v1 exact-only rules.

## Generation

Test source marks desired declarations:

```swift
@GenerateMock(Client.self)
enum ClientMocks {}
```

SPM build-tool plugin scans marked test sources through SwiftSyntax and emits deterministic `MockClient` source into plugin work directory. Generated mock conforms to protocol and subclasses `Mock`. It preserves member signatures and forwards invocation metadata to `MockRuntime`. Source maps diagnostics to marked test declaration. CLI exposes identical generator for Xcode projects not using SPM plugin.

## Package layout

- `MockitoSwift`: runtime and public API.
- `MockitoSwiftMacros`: marker macro declarations.
- `MockitoSwiftGenerator`: SwiftSyntax generator executable.
- `MockitoSwiftPlugin`: SPM build-tool plugin.
- `MockitoSwiftTests`: XCTest runtime tests.
- `GeneratorTests`: fixture-driven snapshot/compile tests.

## Acceptance proof

Test fixtures cover generated source compilation and runtime behavior for every supported member shape. XCTest tests prove exact matching, newest-stub precedence, missing-stub failure, answer/throw behavior, async isolation, call counts, ordered calls, reset, and diagnostics. No matcher symbols exist in public API.
