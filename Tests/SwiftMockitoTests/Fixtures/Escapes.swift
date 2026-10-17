protocol Escapes {
    func perform(_ work: () -> Void)
    func map(_ value: Int, _ transform: (Int) -> String) -> String
    func attempt(_ work: () throws -> Int) throws -> Int
    func later(_ work: () -> Void) async
    func load(id: String, _ parse: (String) -> Int, _ validate: (Int) -> Bool) async throws -> Int
    func log(_ message: @autoclosure () -> String)
    func subscribe(_ handler: @escaping (Int) -> Void, where filter: (Int) -> Bool)
    subscript(transform: (Int) -> Int) -> Int { get set }
}
