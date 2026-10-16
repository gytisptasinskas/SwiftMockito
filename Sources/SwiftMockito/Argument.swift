/// One comparable argument of a mock call's key. Generated code builds these with `arg(_:)`.
public struct Argument: @unchecked Sendable, CustomStringConvertible {
    enum Kind {
        case equatable(value: Any, equals: (Any) -> Bool)
        case identity(AnyObject)
        case type(Any.Type)
        case unsupported
    }

    let kind: Kind
    public let typeName: String
    public let description: String

    init<T: Equatable>(equatable value: T) {
        kind = .equatable(value: value, equals: { ($0 as? T) == value })
        typeName = String(reflecting: T.self)
        description = String(reflecting: value)
    }

    init(identity object: AnyObject) {
        kind = .identity(object)
        typeName = String(reflecting: Swift.type(of: object))
        description = "\(typeName) instance \(ObjectIdentifier(object))"
    }

    init(type: Any.Type) {
        kind = .type(type)
        typeName = "\(String(reflecting: type)).Type"
        description = "\(String(reflecting: type)).self"
    }

    init(unsupported value: Any) {
        kind = .unsupported
        typeName = String(reflecting: Swift.type(of: value))
        description = String(reflecting: value)
    }

    var isSupported: Bool {
        if case .unsupported = kind { return false }
        return true
    }

    func matches(_ other: Argument) -> Bool {
        switch (kind, other.kind) {
        case let (.equatable(_, equals), .equatable(value, _)):
            return equals(value)
        case let (.identity(lhs), .identity(rhs)):
            return lhs === rhs
        case let (.type(lhs), .type(rhs)):
            return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            return false
        }
    }
}

public func arg<T: Equatable>(_ value: T) -> Argument {
    Argument(equatable: value)
}

public func arg<T: AnyObject & Equatable>(_ value: T) -> Argument {
    Argument(equatable: value)
}

public func arg<T: AnyObject>(_ value: T) -> Argument {
    Argument(identity: value)
}

/// Generic and existential contexts. Decided at runtime, because the generator
/// only sees syntax and cannot prove `Equatable` conformance.
@_disfavoredOverload
public func arg<T>(_ value: T) -> Argument {
    if let equatable = value as? any Equatable {
        return Argument(equatable: equatable)
    }
    if type(of: value as Any) is AnyClass {
        return Argument(identity: value as AnyObject)
    }
    return Argument(unsupported: value)
}

public func arg<each T: Equatable>(_ value: (repeat each T)) -> Argument {
    Argument(equatable: TupleBox(repeat each value))
}

public func arg<T>(type: T.Type) -> Argument {
    Argument(type: type)
}

/// Makes a tuple of equatables `Equatable`, so it can take the `.equatable` path.
struct TupleBox<each T: Equatable>: Equatable, CustomDebugStringConvertible {
    let values: (repeat each T)

    init(_ values: repeat each T) { self.values = (repeat each values) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        for (left, right) in repeat (each lhs.values, each rhs.values) {
            guard left == right else { return false }
        }
        return true
    }

    var debugDescription: String { String(reflecting: values) }
}
