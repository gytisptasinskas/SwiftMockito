/// Base class of every generated mock.
open class Mock: @unchecked Sendable {
    /// Stubs and recorded calls for this instance. Generated members dispatch through it.
    public let runtime: MockRuntime

    public init(name: String, site: CallSite) {
        runtime = MockRuntime(mockName: name, site: site)
    }
}
