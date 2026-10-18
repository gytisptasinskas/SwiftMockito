# Stubbing

Configure what a mock returns, throws or computes for a call.

## Overview

Members that are synchronous and do not throw are stubbed with a plain expression, using
``when(_:fileID:filePath:line:column:)``. Members that need `try` or `await` use the closure
form, ``when(isolation:fileID:filePath:line:column:_:)``. Neither form needs an `await` in front
of `when`:

```swift
when(client.cached(id: "42")).thenReturn(nil)
when { try await client.fetch(id: "42") }.thenReturn(.fixture)
```

Both return a ``Stub``. Each `when` expression must record exactly one mock call; zero or
several is reported as a misuse at the call site. A `when` closure must evaluate to the member's
own return type: wrapping the call in `try?`, `??` or a conversion is reported at the `when`,
and no stub is installed.

### Return values

``Stub/thenReturn(_:)`` takes one value, or several that are returned in sequence. The last
value repeats:

```swift
when(client.cached(id: "42")).thenReturn(nil, .fixture)
#expect(client.cached(id: "42") == nil)
#expect(client.cached(id: "42") == .fixture)
#expect(client.cached(id: "42") == .fixture)
```

### Throw errors

``Stub/thenThrow(_:)`` is for throwing members. Calling it on a `when(expr)` form of a
non-throwing member is a compile error. In the closure form it is a runtime failure reported at
the call site.

```swift
when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)
```

### Compute the result

`thenAnswer` receives the call's arguments and returns the result. Single-parameter answers
infer their type. When a member takes a callback, annotate the closure's parameters:

```swift
when(client.load(id: "42", completion: { _ in }))
    .thenAnswer { (id: String, completion: @escaping (Result<User, Error>) -> Void) in
        completion(.success(User(id: id, name: "Gytis")))
    }
```

Pass any closure for the callback argument when you stub; closures are not part of matching.

Non-escaping closure parameters, such as `func perform(_ work: () -> Void)`, work the same way.
The answer annotates them `@escaping` and may call them, but must not keep them:

```swift
when(worker.perform({})).thenAnswer { (work: @escaping () -> Void) in work() }
```

An answer for an `async` member may itself be `async`. An answer may throw only when the member
can throw. The answer's parameter types must match the member's, or the misuse is reported at
the `when` and no stub is installed.

### Properties and subscripts

Properties are stubbed by their getter, and subscripts by their arguments:

```swift
when(client.currentUser).thenReturn(.fixture)
when(client.token).thenReturn("t")
when(catalog[1]).thenReturn("one")
```

### Several matching stubs

When several stubs match a call, the newest one wins. Stubs are kept until ``reset(_:)``:

```swift
when(client.cached(id: "42")).thenReturn(nil)
when(client.cached(id: "42")).thenReturn(.fixture)
#expect(client.cached(id: "42") == .fixture)
```

### Unstubbed calls

A call that matches no stub behaves according to the member:

| Member | Result |
|---|---|
| Returns `Void` | Recorded, then returns normally. |
| Throwing, returns a value | Throws ``MissingStubError``. |
| Non-throwing, returns a value | Fails the test (member, actual arguments, configured stubs, location) and returns a dummy value, so the rest of the run continues. It traps only if no dummy exists for the return type. |

```swift
@Test func missingStubOnThrowingMemberThrows() async {
    await #expect(throws: MissingStubError.self) { try await client.fetch(id: "1") }
}

@Test func unstubbedVoidMemberReturns() {
    client.load(id: "1") { _ in Issue.record("completion must not run") }
    verify(client.load(id: "1", completion: { _ in })).called(1)
}
```

A forgotten stub fails only the test it happens in: the call returns a dummy (see
<doc:DummyValues>), so the code under test keeps going and the other tests still run. Expect
odd follow-on results in that test, since the dummy is a placeholder such as `0`, `""` or `nil`.

The same applies while recording: a non-throwing member whose return type has no dummy is
reported as ``MissingDummyError``, then traps. See <doc:DummyValues>.
