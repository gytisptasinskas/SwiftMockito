# Verifying the Xcode plugin

`XcodeProjectPlugin` only exists inside Xcode. CI compiles it with the command below but cannot run it.

CI compile command (the scheme `SwiftMockito-Package` is auto-generated and confirmed with `xcodebuild -list`; the two `-skip…Validation` flags are required because the package contains a macro and a build-tool plugin, which otherwise prompt for trust):

```
xcodebuild -scheme SwiftMockito-Package -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation build
```

## Manual check

1. Create a new iOS App project "Demo" with a unit-test target "DemoTests".
2. File ▸ Add Package Dependencies ▸ Add Local… ▸ select this repository.
3. Under DemoTests ▸ Build Phases ▸ Run Build Tool Plug-ins, click + and add SwiftMockitoPlugin. Link SwiftMockito to DemoTests.
4. Add `protocol Client { func cached(id: String) -> String? }` to Demo. In DemoTests, add `import SwiftMockito` and `@testable import Demo`, then
   `@GenerateMock(Client.self) enum Mocks {}` and a test that uses `MockClient()`.
5. Press ⌘U. On the first build Xcode asks to trust the SwiftMockito plugin and the `SwiftMockitoMacros` macro; choose Trust & Enable.
   Expected: the build log shows "SwiftMockito: generating 1 mock(s) for DemoTests" and the test passes.
   Open the generated `MockClient.swift` from the build log and check that it contains `@testable import Demo`.
6. Rename `cached` to `cache` in Demo and build again. Expected: the mock regenerates and the test's old `cached` call fails to compile.

## Headless / CI

`xcodebuild test` on a consumer project needs `-skipMacroValidation -skipPackagePluginValidation`, for the same trust reason as above.

## Limitations

- The plugin cannot read a module name from Xcode. It derives the test module from the target's display name (characters outside `[A-Za-z0-9_]` become `_`, and a leading digit gets a `_` prefix). A customised `PRODUCT_MODULE_NAME` is not supported.
- Protocols are searched in the test target's transitive target dependencies. If the test target declares none, every other target in the project is searched.
