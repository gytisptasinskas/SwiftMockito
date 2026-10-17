import Foundation

/// Registers `value` as the dummy that recording returns for `T`.
///
/// While `when`, `verify` or `verifyInOrder` records a call, a member must return something.
/// SwiftMockito returns a dummy, which never reaches the code under test. Register one for a
/// return type that has no built-in or generated dummy, before you stub or verify the member:
///
/// ```swift
/// provideDummy(CGSize(width: 1, height: 1))
/// when(view.size()).thenReturn(CGSize(width: 320, height: 480))
/// ```
///
/// A registered value overrides built-ins and generated fallbacks. The registry is
/// process-wide, is not cleared by ``reset(_:)``, and holds immutable (`Sendable`) values.
/// It is keyed by exact type, so for a member that returns `Base`, register a `Base`:
///
/// ```swift
/// provideDummy(Sub() as Base)
/// ```
///
/// - Parameter value: The dummy to return for `T` while recording.
public func provideDummy<T: Sendable>(_ value: T) {
    DummyRegistry.shared.set(value, for: T.self)
}

/// Used by generated mocks; don't call it directly.
///
/// Looks up the dummy values that generated members return while recording.
public enum Dummies {
    /// Used by generated mocks; don't call it directly.
    ///
    /// Generated non-throwing members call this while recording. Returns the registered,
    /// built-in or `fallback` dummy for `type`, or reports ``MissingDummyError`` and traps.
    public static func resolve<T>(_ type: T.Type, for member: String, fallback: (() -> T)? = nil) -> T {
        if let value = lookup(type) { return value }
        if let fallback { return fallback() }
        let error = MissingDummyError(typeName: String(reflecting: type), member: member)
        Reporter.trap(error.description, at: Capture.currentSite ?? CallSite())
    }

    /// Used by generated mocks; don't call it directly.
    ///
    /// Non-trapping variant for throwing members recorded inside `verifyInOrder`.
    public static func placeholder<T>(_ type: T.Type, fallback: (() -> T)? = nil) -> T? {
        lookup(type) ?? fallback?()
    }

    static func lookup<T>(_ type: T.Type) -> T? {
        if let registered = DummyRegistry.shared.get(type) { return registered }
        if T.self == Void.self { return (() as! T) }
        if let builtIn = (T.self as? any BuiltInDummy.Type)?.makeDummy() as? T { return builtIn }
        return nil
    }
}

final class DummyRegistry: @unchecked Sendable {
    static let shared = DummyRegistry()
    private let lock = NSLock()
    private var values: [ObjectIdentifier: any Sendable] = [:]

    func set<T: Sendable>(_ value: T, for type: T.Type) {
        lock.withLock { values[ObjectIdentifier(type)] = value }
    }

    func get<T>(_ type: T.Type) -> T? {
        lock.withLock { values[ObjectIdentifier(type)] as? T }
    }
}

protocol BuiltInDummy {
    static func makeDummy() -> Self?
}

extension Bool: BuiltInDummy { static func makeDummy() -> Bool? { false } }
extension String: BuiltInDummy { static func makeDummy() -> String? { "" } }
extension Character: BuiltInDummy { static func makeDummy() -> Character? { " " } }
extension Data: BuiltInDummy { static func makeDummy() -> Data? { Data() } }
extension Date: BuiltInDummy { static func makeDummy() -> Date? { Date(timeIntervalSince1970: 0) } }
extension URL: BuiltInDummy { static func makeDummy() -> URL? { URL(string: "about:blank") } }
extension UUID: BuiltInDummy {
    static func makeDummy() -> UUID? { UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)) }
}
extension Int: BuiltInDummy { static func makeDummy() -> Int? { 0 } }
extension Int8: BuiltInDummy { static func makeDummy() -> Int8? { 0 } }
extension Int16: BuiltInDummy { static func makeDummy() -> Int16? { 0 } }
extension Int32: BuiltInDummy { static func makeDummy() -> Int32? { 0 } }
extension Int64: BuiltInDummy { static func makeDummy() -> Int64? { 0 } }
extension UInt: BuiltInDummy { static func makeDummy() -> UInt? { 0 } }
extension UInt8: BuiltInDummy { static func makeDummy() -> UInt8? { 0 } }
extension UInt16: BuiltInDummy { static func makeDummy() -> UInt16? { 0 } }
extension UInt32: BuiltInDummy { static func makeDummy() -> UInt32? { 0 } }
extension UInt64: BuiltInDummy { static func makeDummy() -> UInt64? { 0 } }
extension Double: BuiltInDummy { static func makeDummy() -> Double? { 0 } }
extension Float: BuiltInDummy { static func makeDummy() -> Float? { 0 } }
extension Optional: BuiltInDummy { static func makeDummy() -> Optional? { .some(nil) } }
extension Array: BuiltInDummy { static func makeDummy() -> Array? { [] } }
extension Dictionary: BuiltInDummy { static func makeDummy() -> Dictionary? { [:] } }
extension Set: BuiltInDummy { static func makeDummy() -> Set? { [] } }
extension Result: BuiltInDummy {
    static func makeDummy() -> Result? { Dummies.lookup(Success.self).map { .success($0) } }
}
