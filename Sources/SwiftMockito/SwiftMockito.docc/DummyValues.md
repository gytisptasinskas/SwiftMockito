# Dummies

The placeholder values that mocks return while a call is being recorded.

## Overview

While `when` or `verify` records a call, a non-throwing member must return something.
SwiftMockito returns a dummy value. Dummies exist only while recording and never reach the code
under test.

A dummy comes from, in order:

1. A value you registered with ``provideDummy(_:)``.
2. A built-in: `Void`, `Bool`, integer and floating-point types, `String`, `Character`,
   `Optional` (`nil`), `Array`, `Dictionary`, `Set`, `Data`, `Date`, `URL`, `UUID` and `Result`.
3. A fallback the generator synthesizes from the type's source declaration: a struct from its
   memberwise or accessible initializer, an enum from its first case, a class from an accessible
   initializer, a tuple from the dummies of its elements, and a protocol as a stand-in whose
   members trap if called.

When the generator cannot build a dummy, it reports a build warning at the `@GenerateMock`
declaration. For a protocol with `func size() -> CGSize`:

```
warning: MockP.size(): cannot build a dummy CGSize (not declared in sources); register one with provideDummy(_:) before stubbing or verifying it
```

Register one before you stub or verify that member. The registry is process-wide and holds
immutable values:

```swift
provideDummy(CGSize(width: 1, height: 1))
```

`provideDummy` registers by exact type, and the value must be `Sendable`. For a member that
returns `Base`, register a `Base`; `provideDummy(Sub() as Base)` requires `Base: Sendable`:

```swift
provideDummy(Sub() as Base)
```

If a non-throwing member is recorded and no dummy exists for its return type, SwiftMockito
reports ``MissingDummyError`` (the type and the member, with a hint to call `provideDummy`)
**and then traps, which ends the whole test process**.

Throwing members don't need a dummy for `when` and `verify`, which stop at the first recorded
call. Inside `verifyInOrder`, a throwing member needs one to let the block continue; see
<doc:Verifying#Order>.
