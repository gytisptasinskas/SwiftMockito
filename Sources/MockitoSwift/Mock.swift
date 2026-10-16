import Foundation

/// Base class for generated mocks.
open class Mock {
    /// Stable runtime identity used to distinguish mock instances.
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
