# Generating mocks

Mark the protocols to mock, and let the build plugin or the command-line generator write the mocks.

## Overview

Mark the protocols a test suite mocks with ``GenerateMock(_:)``, on the suite itself:

```swift
import SwiftMockito
@testable import App

@GenerateMock(Client.self)
struct UserRepositoryTests {
    let client = MockClient()
    // …
}
```

`@SwiftMockito.GenerateMock(…)` works too. The marker can sit on any declaration in the test
target, such as a suite or an empty `enum Mocks {}`, and can list several protocols. Mocks belong
to the whole test target, so several suites can mark the same protocol and still share one
`MockClient`.

The build plugin finds `Client` in your test target's dependencies and generates a `MockClient`
class with the same signatures, effects and access level. Protocols declared `internal` need
`@testable import` of their module, as above.

A mock of a `@MainActor` protocol, or of a protocol that inherits from one, is isolated to the
main actor too. Stub and verify it from a `@MainActor` test:

```swift
@MainActor
@Suite struct ScreenTests {
    let screen = MockScreen()

    @Test func rendersTitle() {
        when(screen.isVisible).thenReturn(true)
        screen.render(title: "Home")
        #expect(screen.isVisible)
        verify(screen.render(title: "Home")).called(1)
    }
}
```

### Checked-in mocks

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

Exit codes: 0 on success, 1 for generation or write errors, 2 for a usage error or an unreadable
input.
