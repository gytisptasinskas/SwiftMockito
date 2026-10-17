/// Base class of every generated mock.
///
/// Generated mocks such as `MockClient` subclass it, so you can pass any of them to
/// ``verifyNoMoreInteractions(_:fileID:filePath:line:column:)`` and ``reset(_:)``.
/// Don't subclass `Mock` yourself.
open class Mock: @unchecked Sendable {
    /// Used by generated mocks; don't call it directly.
    ///
    /// Stubs and recorded calls for this instance. Generated members dispatch through it.
    public let runtime: MockRuntime

    /// Used by generated mocks; don't call it directly.
    ///
    /// - Parameters:
    ///   - name: The mock's name, used in failure messages.
    ///   - site: Where the mock was created.
    public init(name: String, site: CallSite) {
        runtime = MockRuntime(mockName: name, site: site)
    }
}
