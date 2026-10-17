import Foundation
import Testing
@testable import SwiftMockitoGeneratorCore

@Suite struct CLITests {
    @Test func writesMocksAndReturnsZero() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Client.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        let out = dir.appending(path: "out")

        let code = Generator.run(arguments: [
            "generate", "--test-module", "SwiftMockitoTests", "--output", out.path,
            "--marked", marked.path,
            "--source", "SwiftMockitoTests=\(fixtures.appending(path: "Client.swift").path)",
        ])

        #expect(code == 0)
        let written = try String(contentsOf: out.appending(path: "MockClient.swift"), encoding: .utf8)
        let golden = try String(contentsOf: fixtures.appending(path: "MockClient.swift"), encoding: .utf8)
        #expect(written == golden)
    }

    @Test func generationErrorReturnsOne() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marked = dir.appending(path: "Mocks.swift")
        try "@GenerateMock(Missing.self)\nenum Mocks {}\n".write(to: marked, atomically: true, encoding: .utf8)
        #expect(Generator.run(arguments: ["generate", "--test-module", "T", "--output", dir.path, "--marked", marked.path]) == 1)
    }

    @Test func usageErrorReturnsTwo() {
        #expect(Generator.run(arguments: ["bogus"]) == 2)
        #expect(Generator.run(arguments: ["generate", "--output"]) == 2)
    }
}
