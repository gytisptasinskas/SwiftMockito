# ``SwiftMockito``

Mockito-style mocks for Swift protocols, generated at build time.

## Overview

Mark a protocol with ``GenerateMock(_:)``, and a build plugin generates its `Mock…` class.
Then **stub** it with ``when(_:fileID:filePath:line:column:)``, run your code, and **verify**
the calls with ``verify(_:fileID:filePath:line:column:)``:

```swift
when(client.cached(id: "42")).thenReturn(.fixture)
// … run the code under test …
verify(client.cached(id: "42")).called(1)
```

Arguments are compared by value, and there are no argument matchers. Every API reports
misuse and failures as test failures at the line that called it, in Swift Testing and XCTest.

> Important: SwiftMockito is a proof of concept. It tests an idea: Mockito-style mock
> generation for Swift, where you mark a protocol and a build plugin generates its mock. It is
> not production-ready yet, and its API may change.

SwiftMockito requires Swift 6.2 or later and iOS 26 or macOS 26, in Swift 6 language mode.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:Matching>
- <doc:Limitations>

### Generating mocks

- <doc:GeneratingMocks>
- ``GenerateMock(_:)``

### Stubbing

- <doc:Stubbing>
- ``when(_:fileID:filePath:line:column:)``
- ``when(isolation:fileID:filePath:line:column:_:)``
- ``Stub``

### Verifying

- <doc:Verifying>
- ``verify(_:fileID:filePath:line:column:)``
- ``verify(isolation:fileID:filePath:line:column:_:)``
- ``Verification``
- ``verifyNever(_:fileID:filePath:line:column:)``
- ``verifyNever(isolation:fileID:filePath:line:column:_:)``
- ``verifyInOrder(isolation:fileID:filePath:line:column:_:)``
- ``verifyInOrder(fileID:filePath:line:column:_:)``
- ``verifyNoMoreInteractions(_:fileID:filePath:line:column:)``
- ``reset(_:)``

### Dummies

- <doc:DummyValues>
- ``provideDummy(_:)``

### Errors

- ``MissingStubError``
- ``MissingDummyError``
- ``UnsupportedExactMatchingError``

### Generated-mock support

Generated mocks use these declarations. Don't call them directly.

- ``Mock``
- ``MockRuntime``
- ``Capture``
- ``CaptureSignal``
- ``Argument``
- ``arg(_:)-9h9t0``
- ``arg(_:)-332c5``
- ``arg(_:)-27m2h``
- ``arg(_:)-2eylf``
- ``arg(_:)-5ylmh``
- ``arg(type:)``
- ``CallSite``
- ``Dummies``
- ``Effects``
- ``VerifyInOrderBuilder``
