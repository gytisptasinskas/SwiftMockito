# MockitoSwift Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Swift Package providing exact-only `when`/`verify` mocks plus protocol mock generation for XCTest.

**Architecture:** Generated protocol conformers forward each real call to a thread-safe `MockRuntime`. Capture-mode calls create typed invocation patterns for `when` and `verify`; normal calls select newest exact stub and record interaction. SwiftSyntax generator emits source; SPM build-tool plugin runs it for annotated test declarations.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, SwiftSyntax, CompilerPluginSupport.

**Spec:** `docs/superpowers/specs/2026-10-16-mockito-swift-design.md`

## Global Constraints

- Public stubbing and verification names are `when` and `verify`.
- No `any()`, wildcard, predicate, capture, default-stub, or nice-mock public API.
- Exact configuration requires `Equatable` arguments; unsupported exact configurations fail diagnostically.
- Unmatched non-`Void` call throws `MissingStubError`; unmatched `Void` call records and succeeds.
- V1 generates protocol instance requirements only; no static requirements, initializers, `Self`, associated types, classes, Objective-C swizzling, or reflection dispatch.
- Generated mocks preserve supported signatures, including effects and actor isolation.
- Verified calls are consumed; ordered verification permits unrelated calls between matched calls; reset removes stubs and interactions.
- Callback members generate and dispatch, but callback values cannot be configured or verified; typed `thenAnswer` may invoke them.

## Review Focus

- Concurrent calls while a stub is added or verification reads history must not corrupt runtime state; Task 2 adds parallel invocation test.
- Two same-name overloads must remain separate invocation identities; Task 4 adds overload fixture.
- `async throws` capture must never perform real dispatch; Task 3 adds a capture-mode test.
- Unmatched `Void` member must record once without failure; Task 2 adds explicit test.
- Verified interaction must not be verifiable twice; Task 3 adds consumption test.

---

### Task 1: Package skeleton and invocation model

**Files:**
- Create: `Package.swift`
- Create: `Sources/MockitoSwift/Mock.swift`
- Create: `Sources/MockitoSwift/Invocation.swift`
- Create: `Sources/MockitoSwift/Errors.swift`
- Create: `Tests/MockitoSwiftTests/InvocationTests.swift`

**Interfaces:**
- Produces: `public class Mock`, `public struct Invocation`, `public enum InvocationPhase`, and `public struct MissingStubError: Error`.

- [ ] **Step 1: Write failing XCTest cases for member identity, argument labels, source location, and `MissingStubError` description.**
- [ ] **Step 2: Run `swift test --filter InvocationTests`; expect compile failure because runtime module is absent.**
- [ ] **Step 3: Create SPM package products and implement immutable invocation metadata in `Sources/MockitoSwift/Invocation.swift`.**
- [ ] **Step 4: Add `Mock` ownership of runtime identity and typed diagnostic errors in `Mock.swift` and `Errors.swift`.**
- [ ] **Step 5: Run `swift test --filter InvocationTests`; expect PASS.**
- [ ] **Step 6: Commit `feat: scaffold mock runtime`.**

### Task 2: Exact stubs and normal dispatch

**Files:**
- Create: `Sources/MockitoSwift/MockRuntime.swift`
- Create: `Sources/MockitoSwift/ExactArguments.swift`
- Create: `Sources/MockitoSwift/Stubbing.swift`
- Create: `Tests/MockitoSwiftTests/StubbingTests.swift`

**Interfaces:**
- Consumes: `Mock`, `Invocation`, `MissingStubError`.
- Produces: `MockRuntime.record`, `MockRuntime.resolve`, `Stub`, `thenReturn`, `thenThrow`, `thenAnswer`, and exact-argument comparison API used only by generated source.

- [ ] **Step 1: Write failing tests for exact values, newest matching stub, return, throw, typed answer, unstubbed failure, unstubbed `Void`, and concurrent invocation recording.**
- [ ] **Step 2: Run `swift test --filter StubbingTests`; expect compile failure for `MockRuntime`.**
- [ ] **Step 3: Implement lock-protected stub and invocation stores in `MockRuntime.swift`.**
- [ ] **Step 4: Implement `Equatable` argument encoding and diagnostic `UnsupportedExactMatchingError` in `ExactArguments.swift`.**
- [ ] **Step 5: Implement fluent post-stub APIs in `Stubbing.swift`; ensure each response preserves member effects through generated wrappers.**
- [ ] **Step 6: Run `swift test --filter StubbingTests`; expect PASS.**
- [ ] **Step 7: Commit `feat: add exact stub dispatch`.**

### Task 3: Capture mode and verification

**Files:**
- Create: `Sources/MockitoSwift/CaptureContext.swift`
- Create: `Sources/MockitoSwift/Verification.swift`
- Create: `Tests/MockitoSwiftTests/VerificationTests.swift`

**Interfaces:**
- Consumes: `MockRuntime`, `Invocation`, exact argument encoding.
- Produces: `when`, `verify`, `verifyNever`, `verifyInOrder`, `verifyNoMoreInteractions`, `reset`, `once`, `atLeast`, and `atMost`.

- [ ] **Step 1: Write failing tests for capture without normal dispatch, counts, never, consumption, flexible order, no-more-interactions, reset, and `async throws` closure capture.**
- [ ] **Step 2: Run `swift test --filter VerificationTests`; expect compile failure for `when` and `verify`.**
- [ ] **Step 3: Implement task-local capture state in `CaptureContext.swift` so concurrent tests do not share mode.**
- [ ] **Step 4: Implement sync and effect-preserving closure overloads for `when`/`verify` in `Verification.swift`.**
- [ ] **Step 5: Implement consumption and relative-order matching against runtime interaction history.**
- [ ] **Step 6: Run `swift test --filter VerificationTests`; expect PASS.**
- [ ] **Step 7: Commit `feat: add when and verify APIs`.**

### Task 4: SwiftSyntax generator for protocol fixtures

**Files:**
- Create: `Sources/MockitoSwiftGenerator/main.swift`
- Create: `Sources/MockitoSwiftGenerator/ProtocolParser.swift`
- Create: `Sources/MockitoSwiftGenerator/MockEmitter.swift`
- Create: `Tests/GeneratorTests/Fixtures/Service.swift`
- Create: `Tests/GeneratorTests/Fixtures/Expected/MockService.swift`
- Create: `Tests/GeneratorTests/GeneratorTests.swift`

**Interfaces:**
- Consumes: annotated declaration file path and module name.
- Produces: deterministic generated `Mock<Type>` source and clear unsupported-requirement diagnostics.

- [ ] **Step 1: Write fixture snapshot tests for sync return, `Void`, property, overload, generic method, `async throws`, `@MainActor`, and callback member emission.**
- [ ] **Step 2: Run `swift test --filter GeneratorTests`; expect target missing.**
- [ ] **Step 3: Parse `@GenerateMock(Type.self)` declarations and resolve protocol instance members with SwiftSyntax.**
- [ ] **Step 4: Emit conforming mock methods that capture or dispatch through `MockRuntime`; emit diagnostic for excluded requirements and non-equatable configuration boundary.**
- [ ] **Step 5: Compile generated fixture sources as test target input.**
- [ ] **Step 6: Run `swift test --filter GeneratorTests`; expect PASS.**
- [ ] **Step 7: Commit `feat: generate protocol mocks`.**

### Task 5: Macro declaration, SPM plugin, and integration test

**Files:**
- Create: `Sources/MockitoSwiftMacros/GenerateMock.swift`
- Create: `Plugins/MockitoSwiftPlugin/plugin.swift`
- Create: `Tests/PluginIntegrationTests/Package.swift`
- Create: `Tests/PluginIntegrationTests/Tests/AppTests/ClientTests.swift`
- Create: `Tests/PluginIntegrationTests/Tests/AppTests/Client.swift`
- Create: `Tests/PluginIntegrationTests/Tests/AppTests/GeneratedMockBehaviorTests.swift`

**Interfaces:**
- Consumes: marker macro annotations and generator executable.
- Produces: plugin-generated Swift sources available to XCTest target compilation.

- [ ] **Step 1: Write fixture package test that imports macro, annotates `Client`, compiles generated `MockClient`, and executes `when`/`verify`.**
- [ ] **Step 2: Run fixture `swift test`; expect failure because plugin product is absent.**
- [ ] **Step 3: Define no-output `@GenerateMock` peer marker macro and register it in package manifest.**
- [ ] **Step 4: Implement build-tool plugin input discovery, generator invocation, output declaration, and incremental input list.**
- [ ] **Step 5: Run root `swift test` and fixture `swift test`; expect PASS.**
- [ ] **Step 6: Commit `feat: add SPM mock generation plugin`.**

### Task 6: Documentation and release gate

**Files:**
- Create: `README.md`
- Create: `Examples/ClientExampleTests.swift`
- Modify: `Package.swift`
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: public runtime, macro, generator, and plugin products.
- Produces: installable SPM package with documented generation and exact-only limitations.

- [ ] **Step 1: Write README examples for package dependency, plugin attachment, `@GenerateMock`, sync/async `when`, `verify`, missing-stub behavior, and excluded matcher API.**
- [ ] **Step 2: Add runnable example test and test that public module has no `any` symbol.**
- [ ] **Step 3: Configure Swift 6 CI matrix on supported macOS/Xcode runner.**
- [ ] **Step 4: Run `swift test`; expect all runtime, generator, integration, and example tests PASS.**
- [ ] **Step 5: Run `swift package describe`; expect four library/executable/plugin products resolve.**
- [ ] **Step 6: Commit `docs: document MockitoSwift usage`.**

## Self-review

- Spec coverage: Tasks 1–3 implement runtime, matching, errors, verification, reset, and exact-only limits; Tasks 4–5 implement annotation-based generated protocol mocks; Task 6 documents and gates release.
- Type consistency: generated source calls only `MockRuntime` and public capture APIs defined by Tasks 1–3; plugin invokes Task 4 executable.
- Review focus coverage: Task 2 covers concurrent recording and `Void`; Task 3 covers capture and consumption; Task 4 covers overload identity.
- Proportion: plan names interfaces, files, tests, and checks without prescribing source bodies.
