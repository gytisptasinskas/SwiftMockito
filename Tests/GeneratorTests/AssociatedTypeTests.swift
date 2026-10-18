import Testing
@testable import SwiftMockitoGeneratorCore

private func generate(_ source: String, marking name: String = "Repository") -> GeneratorResult {
    let marker = SourceInput(path: "/t/M.swift", module: "T", text: "@GenerateMock(\(name).self)\nenum M {}\n")
    let input = SourceInput(path: "/a/R.swift", module: "App", text: source)
    return Generator.generate(GeneratorConfiguration(markedPaths: [marker.path], inputs: [marker, input],
                                                     testModule: "T", outputDirectory: "/x"))
}

/// A protocol with associated types becomes a generic mock: `MockRepository<User, String>()`.
@Suite struct AssociatedTypeTests {
    @Test func associatedTypesBecomeGenericParameters() throws {
        let result = generate("""
            protocol Repository {
                associatedtype Item: Equatable
                associatedtype ID = String
                func save(_ item: Item) throws
                func item(id: ID) -> Item?
                func all() async throws -> [Item]
            }
            """)
        #expect(result.diagnostics.isEmpty)
        let file = try #require(result.files["MockRepository.swift"])
        #expect(file.contains("final class MockRepository<Item: Equatable, ID>: Mock, Repository, @unchecked Sendable {"))
        #expect(file.contains("func save(_ item: Item) throws {"))
        #expect(file.contains("return runtime.invoke(\"item(id:)\", key: [arg(id)], args: id)"))
    }

    @Test func aValueOfAnAssociatedTypeNeedsProvideDummy() {
        let result = generate("protocol Repository { associatedtype Item\n var latest: Item { get } }")
        #expect(result.diagnostics.map(\.message) == [
            "MockRepository.latest: cannot build a dummy for generic return type Item; call provideDummy(_:) for each concrete Item you stub"
        ])
    }

    @Test func inheritedAssociatedTypesAreParametersToo() throws {
        let result = generate("""
            protocol Repository { associatedtype Item; func save(_ item: Item) }
            protocol Store: Repository { associatedtype Key: Hashable; func clear(_ key: Key) }
            """, marking: "Store")
        #expect(result.diagnostics.isEmpty)
        let file = try #require(result.files["MockStore.swift"])
        #expect(file.contains("final class MockStore<Item, Key: Hashable>: Mock, Store, @unchecked Sendable {"))
    }

    @Test func whereClausesAreReported() {
        let result = generate("protocol Repository { associatedtype Item where Item: Equatable\n func save(_ item: Item) }")
        #expect(result.diagnostics.map(\.message) == ["Repository.Item: associated types with where clauses are not supported"])
    }
}
