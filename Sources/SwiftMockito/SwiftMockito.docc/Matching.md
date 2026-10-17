# Exact matching

How SwiftMockito decides that a call matches a stub or a verification.

## Overview

There are no argument matchers: no `any()`, wildcards, predicates or captors. A call is
identified by its member and its arguments, compared by value.

- `Equatable` values compare with `==`. That includes optionals, collections and tuples of
  equatable values.
- Class instances compare by identity (`===`), unless the class is `Equatable`, in which case
  `==` is used.
- Closure parameters are left out of the key, so `verify(catalog.notify({}))` matches any closure.
- Generic methods include the concrete generic types (`T.self`) in the key.
- Overloads are separate members.
- Variadic arguments match as an array.
- Any other non-`Equatable` value is unsupported. Stubbing or verifying such a call reports
  ``UnsupportedExactMatchingError``, naming the member, the argument position and the type.
  Real calls still work.

These examples use a `MockCatalog` named `catalog`:

```swift
// Class arguments match by identity
let a = Reference(), b = Reference()
when(catalog.describe(a)).thenReturn("a")
verifyNever(catalog.describe(b))

// Tuples match by value
catalog.tag((1, "x"))
verify(catalog.tag((1, "x"))).called(1)

// The generic type is part of the key
when { try catalog.decode(Data(), as: Int.self) }.thenReturn(7)
when { try catalog.decode(Data(), as: String.self) }.thenReturn("seven")
```
