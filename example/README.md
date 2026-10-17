# SwiftMockito example app

A small SwiftUI app that reads posts from the free [JSONPlaceholder](https://jsonplaceholder.typicode.com) API. It is plain MVVM: two screens, each with a view model that talks straight to a `PostService` protocol. The view models are unit-tested against a `MockPostService` that SwiftMockito generates at build time. No mock file is checked in, and the tests never touch the network.

```
app/
  Models.swift               Post, User, PostComment
  PostService.swift          the protocol the view models depend on
  LivePostService.swift      URLSession implementation (used when you run the app)
  PostListViewModel.swift    list screen: load, empty, error, pull to refresh
  PostDetailViewModel.swift  detail screen: author, comments, like
  PostListView.swift, PostDetailView.swift, appApp.swift
appTests/
  Fixtures.swift             sample models and an Offline error
  PostListViewModelTests.swift
  PostDetailViewModelTests.swift
  ModelDecodingTests.swift
```

## Running it

1. Open `example/app.xcodeproj` in Xcode 27 or later (the project was created with Xcode 27).
2. Press ⌘U to run the tests, or ⌘R to run the app in an iOS 26 simulator.
3. The first build asks you to trust the SwiftMockito macro and the SwiftMockitoPlugin build plugin. Choose **Trust & Enable** for both.

⌘U launches the app to host the tests. `appApp` checks for `XCTestConfigurationFilePath` and shows nothing in that case, so a test run sends no requests.

The project uses the package from the repository root (`..`) as a local package, so it always builds against the code in this checkout.

From the command line:

```bash
cd example
xcodebuild test -project app.xcodeproj -scheme app \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipMacroValidation -skipPackagePluginValidation
```

## Where the mock comes from

Each test suite names the protocol it mocks, on the suite itself. This is the whole setup:

```swift
import SwiftMockito
@testable import app

@GenerateMock(PostService.self)
@MainActor
struct PostListViewModelTests {
    let service = MockPostService()
    // …
}
```

`PostDetailViewModelTests` carries the same marker. Mocks belong to the whole test target, so both suites share one generated `MockPostService`.

The `appTests` target links `SwiftMockito` and runs `SwiftMockitoPlugin` (Build Phases > Run Build Tool Plug-ins). On each build, the plugin finds `PostService` in the `app` target's sources and writes `MockPostService` into DerivedData. Add a method to `PostService` and the mock picks it up on the next build.

The `app` target itself does not depend on SwiftMockito.

## What each test shows

| SwiftMockito feature | Test |
| --- | --- |
| `when { … }.thenReturn(…)` for an `async throws` call | `PostListViewModelTests.showsPosts` |
| `thenThrow` | `PostListViewModelTests.showsErrorWhenLoadFails` |
| Sequential returns: `thenReturn(a, b)` | `PostListViewModelTests.refreshShowsNewPosts` |
| Re-stubbing: the newest stub wins | `PostListViewModelTests.failedRefreshKeepsPreviousPosts` |
| `reset(mock)` | `PostListViewModelTests.successfulRefreshClearsError` |
| `verify { … }.called(n)` | `PostListViewModelTests.showsPosts`, `PostDetailViewModelTests.secondLikeIsIgnored` |
| `verifyNoMoreInteractions` | `PostListViewModelTests.startsLoading`, `PostDetailViewModelTests.loadsAuthorThenComments` |
| `verifyInOrder` | `PostDetailViewModelTests.loadsAuthorThenComments` |
| `verifyNever` | `PostDetailViewModelTests.stopsWhenAuthorFails` |
| `thenAnswer` driving a completion handler | `PostDetailViewModelTests.likeMarksPostLiked`, `likeFailureLeavesPostUnliked` |
| `thenAnswer` holding the callback to test a request in flight | `PostDetailViewModelTests.likeWhileLikingIsIgnored` |

Every test stubs what it calls, and arguments are matched by value: `service.user(id: 7)` only matches a call with `id` 7.

## Things to know if you copy this setup

- **Default actor isolation.** New Xcode app projects set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which silently makes every protocol `@MainActor`. The generator reads source, not build settings, so it can't see that, and the generated mock doesn't match. This project sets the `app` target's **Default Actor Isolation** to `nonisolated`, and marks the view models `@MainActor` explicitly. Do the same, or write `@MainActor` on the protocol yourself so the generator sees it.
- **Callback answers need annotated parameter types.** For a member that takes a completion handler, spell out the closure's parameter types in `thenAnswer`:

  ```swift
  when(service.likePost(id: 1, completion: { _ in }))
      .thenAnswer { (id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) in
          completion(.success(()))
      }
  ```

  The closure passed to `likePost` inside `when` and `verify` is a placeholder. Closures can't be compared, so only `id` is matched.
- **Module name.** The plugin derives the module name from the target name, so keep `PRODUCT_MODULE_NAME` at its default.
