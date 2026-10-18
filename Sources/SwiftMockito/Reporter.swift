import Foundation
import Testing
import XCTest

/// Routes every SwiftMockito failure to the running test framework.
enum Reporter {
    /// Test seam: when set, failures go here instead of to Swift Testing or XCTest.
    @TaskLocal static var sink: (@Sendable (String, CallSite) -> Void)?
    /// Test hook for ``warn(_:at:)``, like `sink` for failures.
    @TaskLocal static var warningSink: (@Sendable (String, CallSite) -> Void)?

    static func fail(_ message: String, at site: CallSite) {
        if let sink {
            sink(message, site)
            return
        }
        if Test.current != nil {
            Issue.record(
                Comment(rawValue: message),
                sourceLocation: Testing.SourceLocation(
                    fileID: site.fileID,
                    filePath: String(describing: site.filePath),
                    line: Int(site.line),
                    column: Int(site.column)
                )
            )
        } else {
            XCTFail(message, file: site.filePath, line: site.line)
        }
    }

    /// Reports the failure, then ends the test process. Used where Swift gives
    /// no way to fail a non-throwing member without returning a value.
    /// Reports something that is likely, but not certainly, a mistake. It doesn't fail the test:
    /// a Swift Testing warning where the toolchain supports one, otherwise a line on standard error.
    static func warn(_ message: String, at site: CallSite) {
        if let warningSink {
            warningSink(message, site)
            return
        }
        #if compiler(>=6.3)
        if Test.current != nil {
            Issue.record(
                Comment(rawValue: message),
                severity: .warning,
                sourceLocation: Testing.SourceLocation(
                    fileID: site.fileID,
                    filePath: String(describing: site.filePath),
                    line: Int(site.line),
                    column: Int(site.column)
                )
            )
            return
        }
        #endif
        FileHandle.standardError.write(Data("\(site): warning: \(message)\n".utf8))
    }

    static func trap(_ message: String, at site: CallSite) -> Never {
        fail(message, at: site)
        fatalError(message, file: site.filePath, line: site.line)
    }
}
