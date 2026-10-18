# Limitations

What SwiftMockito doesn't support, and the rough edges of what it does.

## Overview

SwiftMockito is a proof of concept. The lists below cover what it deliberately leaves out and
the known limitations of the current version.

### Not supported

- Argument matchers: no `any()`, wildcards, predicates or argument captors.
- Default stubs or "nice mock" behavior. An unstubbed call that returns a value fails.
- Static requirements, initializers and `Self` requirements.
- Associated types with a `where` clause. Other associated types make the mock generic:
  `MockRepository<User, String>()`.
- Subscripts with `async` or `throws` getters, and generic subscripts.
- `rethrows` members.
- Objective-C protocols (`@objc`, or `optional` requirements).
- Members named `runtime` or `arg`, which collide with names the generated mock uses.
  Parameters named `arg` are fine.
- `Actor`-constrained protocols (`protocol P: Actor`).
- Protocols that declare no global actor but inherit different ones from their parents.
- Class mocking, and protocols available only in binary frameworks.
- The Objective-C runtime, swizzling and reflection-based dispatch.

### Known limitations

- Mocks of global-actor protocols are stubbed and verified from tests isolated to that actor.
- `thenAnswer` bodies run, and `thenReturn` values are handed over, on whatever thread or actor
  the code under test calls the mock from. Don't touch actor-isolated test state from an answer.
- A `when` closure must evaluate to the member's own return type. Wrapping the call in `try?`,
  `??` or a conversion is reported at the `when`, and no stub is installed.
- The generator looks up protocols, inherited protocols, typealiases and dummy types by name. A
  name declared in more than one dependency module is an error at the marker; rename one of
  them. A declaration in the test module itself shadows the others.
- A `thenAnswer` must not store a non-escaping closure parameter, or anything that captures it,
  for use after it returns. The mock lends the closure through `withoutActuallyEscaping`, so in
  debug builds such an answer traps with `closure argument was escaped in
  withoutActuallyEscaping block`, pointing at the generated mock. Optimized builds do not check,
  and calling the stored closure later is undefined behavior.
- `thenAnswer` closures with callback parameters need annotated parameter types.
- `provideDummy` registers by exact type: use `provideDummy(Sub() as Base)` for a `Base` return.
- Types whose initializers are not reachable from the test module produce a build warning and
  need `provideDummy`.
- In Xcode, the first build asks you to trust the SwiftMockito macro and plugin. On CI, pass
  `-skipMacroValidation -skipPackagePluginValidation` to `xcodebuild`.
- The Xcode plugin derives the test module name from the target's display name, so a customized
  `PRODUCT_MODULE_NAME` is not supported. See the
  [Xcode plugin setup](https://github.com/gytisptasinskas/SwiftMockito/blob/main/docs/xcode-plugin-verification.md).
