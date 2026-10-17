protocol Edge {
    func log(_ message: String, _ extra: Int...)
    func find(for: String) -> Int
    func reserved(runtime: Int, capture: Int)
    func handler() -> (Int) -> Void
    var transform: ((String) -> String)? { get }
    func legacy() -> String!
}
