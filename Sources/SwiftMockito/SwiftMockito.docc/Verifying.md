# Verifying

Check which calls a mock received, how often, and in what order.

## Overview

``verify(_:fileID:filePath:line:column:)`` asserts that at least one matching, not yet verified
call happened, and marks the matching calls as verified. The returned ``Verification`` tightens
the count with ``Verification/called(_:fileID:filePath:line:column:)``,
``Verification/called(atLeast:fileID:filePath:line:column:)`` and
``Verification/called(atMost:fileID:filePath:line:column:)``.

```swift
verify(client.cached(id: "42")).called(1)
await verify { try await client.fetch(id: "42") }.called(atLeast: 1)
verifyNever { try client.save(.fixture) }
verifyNoMoreInteractions(client)
```

Like `when`, the plain form is for synchronous, non-throwing members, and the closure form is
for members that need `try` or `await`. `verify`, `verifyNever` and `verifyInOrder` take `await`
in front exactly when a call inside them needs `await`. Each `verify` or `verifyNever` expression must record exactly one mock call;
zero or several is reported as a misuse at the call site.

### Properties

A property setter is verified with an assignment inside the closure form:

```swift
client.token = "new"
verify { client.token = "new" }.called(1)
verify(client.token).called(1)   // the getter
```

### Calls that must not happen

``verifyNever(_:fileID:filePath:line:column:)`` and
``verifyNever(fileID:filePath:line:column:_:)-1nkaa`` fail if any call matches, including a
call that an earlier `verify` already verified.

### Order

``verifyInOrder(fileID:filePath:line:column:_:)-6njpq`` checks relative order only; unrelated
calls may happen in between, and the lines may call different mocks. When a line needs `await`,
use the `await` form, ``verifyInOrder(fileID:filePath:line:column:_:)-vpyp``. Every line is recorded, including `try`
and `await` lines, and the function itself does not throw:

```swift
await verifyInOrder {
    client.cached(id: "42")
    try await client.fetch(id: "42")
    try client.save(.fixture)
}
```

A throwing line is recorded and the block continues. A throwing member with no placeholder,
meaning any return type that has no built-in or synthesized dummy and not only a generic one,
cannot continue the block, so register a dummy with ``provideDummy(_:)`` for that type first.
Throwing members get no build warning for this.

### No more interactions

``verifyNoMoreInteractions(_:fileID:filePath:line:column:)`` fails if the mock recorded any call
that `verify` or `verifyInOrder` has not verified.

### Starting over

``reset(_:)`` clears the mock's stubs and recorded calls.
