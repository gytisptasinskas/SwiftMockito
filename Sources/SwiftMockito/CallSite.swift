/// Used by generated mocks; don't call it directly.
///
/// The caller's source position, captured by every public SwiftMockito function.
/// ``MissingStubError/site`` holds one.
public struct CallSite: Sendable, CustomStringConvertible {
    /// The file, as `#fileID` gives it: `Module/File.swift`.
    public let fileID: String
    /// The full path of the file.
    public let filePath: StaticString
    /// The line number.
    public let line: UInt
    /// The column number.
    public let column: UInt

    /// Used by generated mocks; don't call it directly.
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

    /// `fileID:line:column`.
    public var description: String { "\(fileID):\(line):\(column)" }
}
