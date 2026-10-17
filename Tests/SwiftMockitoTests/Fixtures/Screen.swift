@MainActor
protocol Presenting {
    var isVisible: Bool { get }
}

/// Isolated to the main actor only through `Presenting`.
protocol Screen: Presenting {
    func render(title: String)
}
