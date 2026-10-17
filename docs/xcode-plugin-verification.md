# Verifying the Xcode plugin

`XcodeProjectPlugin` only exists inside Xcode. CI compiles it (`xcodebuild … build`) but cannot run it.

CI compile command (the scheme `SwiftMockito-Package` is auto-generated and confirmed with `xcodebuild -list`; the two `-skip…Validation` flags are required because the package contains a macro and a build-tool plugin, which otherwise prompt for trust):

```
xcodebuild -scheme SwiftMockito-Package -destination 'platform=macOS' -skipMacroValidation -skipPackagePluginValidation build
```

1. Create a new iOS App project "Demo" with a unit-test target "DemoTests".
2. File ▸ Add Package Dependencies ▸ Add Local… ▸ select this repository.
3. Under DemoTests ▸ Build Phases ▸ Run Build Tool Plug-ins, click + and add SwiftMockitoPlugin. Link SwiftMockito to DemoTests.
4. Add `protocol Client { func cached(id: String) -> String? }` to Demo. In DemoTests, add
   `@GenerateMock(Client.self) enum Mocks {}` and a test that uses `MockClient()`.
5. Press ⌘U. Expected: the build log shows "SwiftMockito: generating 1 mock(s) for DemoTests" and the test passes.
6. Rename `cached` to `cache` in Demo and build again. Expected: the mock regenerates and the test's old `cached` call fails to compile.
