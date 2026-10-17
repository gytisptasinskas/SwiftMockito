import Foundation
import Testing
@testable import SwiftMockitoGeneratorCore

private func makeTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite struct CLITests {
    @Test func writesMocksAndReturnsZero() throws {
        let dir = try makeTempDirectory()
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Client.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        let out = dir.appending(path: "out")

        var errors = ""
        let code = Generator.run(arguments: [
            "generate", "--test-module", "SwiftMockitoTests", "--output", out.path,
            "--marked", marked.path,
            "--source", "SwiftMockitoTests=\(fixtures.appending(path: "Client.swift").path)",
        ], stderr: { errors += $0 })

        #expect(code == 0)
        #expect(errors.isEmpty)
        let written = try String(contentsOf: out.appending(path: "MockClient.swift"), encoding: .utf8)
        let golden = try String(contentsOf: fixtures.appending(path: "MockClient.swift"), encoding: .utf8)
        #expect(written == golden)
    }

    @Test func generationErrorReturnsOne() throws {
        let dir = try makeTempDirectory()
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Missing.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        var errors = ""
        let code = Generator.run(arguments: ["generate", "--test-module", "T", "--output", dir.path, "--marked", marked.path],
                                 stderr: { errors += $0 })
        #expect(code == 1)
        #expect(errors.hasPrefix("\(marked.path):1:1: error: Missing: protocol not found"))
    }

    @Test func undeclaredOutputReturnsOneAndStillWritesTheFile() throws {
        let dir = try makeTempDirectory()
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Client.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        let out = dir.appending(path: "out")
        var errors = ""
        let code = Generator.run(arguments: [
            "generate", "--test-module", "SwiftMockitoTests", "--output", out.path, "--marked", marked.path,
            "--source", "SwiftMockitoTests=\(fixtures.appending(path: "Client.swift").path)",
            "--expect", "MockCatalog.swift",
        ], stderr: { errors += $0 })
        #expect(code == 1)
        #expect(errors.contains("error: MockClient.swift was not declared by the build plugin"))
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "MockClient.swift").path))
    }

    @Test func usageErrorReturnsTwo() {
        var errors = ""
        #expect(Generator.run(arguments: ["bogus"], stderr: { errors += $0 }) == 2)
        #expect(errors == Generator.usage)
        #expect(Generator.run(arguments: ["generate", "--output"], stderr: { _ in }) == 2)
    }

    @Test func unreadableInputIsAUsageError() throws {
        let dir = try makeTempDirectory()
        var errors = ""
        let missing = dir.appending(path: "Nope.swift").path
        #expect(Generator.run(arguments: ["generate", "--test-module", "T", "--output", dir.path, "--marked", missing],
                              stderr: { errors += $0 }) == 2)
        #expect(errors == "error: cannot read \(missing)\n")

        errors = ""
        let missingDirectory = dir.appending(path: "NoDir").path
        #expect(Generator.run(arguments: ["generate", "--test-module", "T", "--output", dir.path,
                                          "--source-dir", "M=\(missingDirectory)"], stderr: { errors += $0 }) == 2)
        #expect(errors == "error: cannot read \(missingDirectory)\n")
    }

    @Test func unwritableOutputReturnsOne() throws {
        let dir = try makeTempDirectory()
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Client.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        let blocker = dir.appending(path: "file")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        var errors = ""
        let code = Generator.run(arguments: [
            "generate", "--test-module", "SwiftMockitoTests", "--output", blocker.appending(path: "out").path,
            "--marked", marked.path,
            "--source", "SwiftMockitoTests=\(fixtures.appending(path: "Client.swift").path)",
        ], stderr: { errors += $0 })
        #expect(code == 1)
        #expect(errors.hasPrefix("error: cannot write \(blocker.appending(path: "out").path): "))
    }

    @Test func sourceDirectorySkipsGeneratedAndHiddenFilesButNotMockPrefixedSources() throws {
        let dir = try makeTempDirectory()
        let sources = dir.appending(path: "Sources")
        let nested = sources.appending(path: "Sub")
        let hidden = nested.appending(path: ".build")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        try "protocol Bird { func chirp() }\n".write(to: sources.appending(path: "MockingBird.swift"), atomically: true, encoding: .utf8)
        try "// Generated by SwiftMockito from Old. Do not edit.\nprotocol Bird { func stale() }\n"
            .write(to: nested.appending(path: "MockOld.swift"), atomically: true, encoding: .utf8)
        try "protocol Bird { func junk() }\n".write(to: hidden.appending(path: "Junk.swift"), atomically: true, encoding: .utf8)
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Bird.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        let out = dir.appending(path: "out")

        var errors = ""
        let code = Generator.run(arguments: [
            "generate", "--test-module", "T", "--output", out.path, "--marked", marked.path,
            "--source-dir", "App=\(sources.path)",
        ], stderr: { errors += $0 })

        #expect(code == 0)
        #expect(errors.isEmpty)
        let mock = try String(contentsOf: out.appending(path: "MockBird.swift"), encoding: .utf8)
        #expect(mock.contains("func chirp()"))
        #expect(!mock.contains("stale") && !mock.contains("junk"))
    }
}
