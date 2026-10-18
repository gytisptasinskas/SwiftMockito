import Foundation

/// Associated types: the mock is generic over them, `MockRepository<User, String>`.
protocol Repository {
    associatedtype Item: Equatable
    associatedtype ID = String
    func save(_ item: Item) throws
    func item(id: ID) -> Item?
    func all() async throws -> [Item]
}
