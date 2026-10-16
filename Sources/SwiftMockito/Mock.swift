import Foundation

/// Base class for generated mocks.
open class Mock {
    /// Stable runtime identity used to distinguish mock instances.
    public let id: UUID

    /// Per-instance runtime used by generated mock members.
    public let runtime: MockRuntime

    public init(id: UUID = UUID()) {
        self.id = id
        self.runtime = MockRuntime()
    }
}
