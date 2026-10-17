/// The caller's source position, captured by every public SwiftMockito function.
public struct CallSite: Sendable, CustomStringConvertible {
    public let fileID: String
    public let filePath: StaticString
    public let line: UInt
    public let column: UInt

    public init(
        fileID: String = #fileID,
        filePath: StaticString = #filePath,
        line: UInt = #line,
        column: UInt = #column
    ) {
        self.fileID = fileID
        self.filePath = filePath
        self.line = line
        self.column = column
    }

    public var description: String { "\(fileID):\(line):\(column)" }
}
