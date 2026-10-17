@MainActor
protocol Screen {
    var isVisible: Bool { get }
    func render(title: String)
}
