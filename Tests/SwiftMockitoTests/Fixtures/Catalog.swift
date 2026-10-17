import Foundation

final class Reference {}

protocol Catalog {
    subscript(index: Int) -> String { get set }
    func item(id: Int) -> String
    func item(id: String) -> String
    func decode<T: Decodable>(_ data: Data, as type: T.Type) throws -> T
    func store<T: Equatable>(_ value: T)
    func describe(_ reference: Reference) -> String
    func tag(_ pair: (Int, String))
    func notify(_ handler: (() -> Void)?)
}
