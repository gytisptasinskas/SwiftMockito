public protocol Feed {
    var latest: Int { get async }
    var config: String { get throws }
    func refresh(force: Bool) async
    func count() async -> Int
    func first<T: Equatable>(in items: [T]) -> T?
}
