public struct GeneratorDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable { case warning, error }

    public let severity: Severity
    public let message: String
    public let path: String
    public let line: Int
    public let column: Int

    public init(severity: Severity, message: String, path: String, line: Int, column: Int) {
        self.severity = severity
        self.message = message
        self.path = path
        self.line = line
        self.column = column
    }

    public var description: String { "\(path):\(line):\(column): \(severity.rawValue): \(message)" }

    static func error(_ message: String, at marker: Marker) -> Self {
        .init(severity: .error, message: message, path: marker.path, line: marker.line, column: marker.column)
    }

    static func warning(_ message: String, at marker: Marker) -> Self {
        .init(severity: .warning, message: message, path: marker.path, line: marker.line, column: marker.column)
    }
}

// `Result<_, [GeneratorDiagnostic]>` (and `Result.get()`) needs the failure type to be an `Error`.
extension Array: @retroactive Error where Element == GeneratorDiagnostic {}
