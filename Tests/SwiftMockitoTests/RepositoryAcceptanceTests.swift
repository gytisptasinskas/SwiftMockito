import Testing
@testable import SwiftMockito

/// A mock of a protocol with associated types is generic over them.
@Suite struct RepositoryAcceptanceTests {
    let repository = MockRepository<User, String>()

    @Test func stubsAndVerifiesWithConcreteTypes() async throws {
        when(repository.item(id: "42")).thenReturn(.fixture)
        when { try await repository.all() }.thenReturn([.fixture])

        #expect(repository.item(id: "42") == .fixture)
        #expect(try await repository.all() == [.fixture])
        verify(repository.item(id: "42")).called(1)
    }

    @Test func associatedTypeArgumentsMatchByValue() throws {
        try repository.save(User(id: "1", name: "Ada"))

        verify { try repository.save(User(id: "1", name: "Ada")) }.called(1)
        verifyNever { try repository.save(User(id: "2", name: "Ada")) }
    }

    @Test func throwsFromAStub() {
        when { try repository.save(.fixture) }.thenThrow(ClientError.offline)
        #expect(throws: ClientError.offline) { try repository.save(.fixture) }
    }

    @Test func otherConcreteTypesWork() {
        let byNumber = MockRepository<String, Int>()
        when(byNumber.item(id: 7)).thenReturn("seven")
        #expect(byNumber.item(id: 7) == "seven")
        #expect(byNumber.item(id: 7) == "seven")
        verify(byNumber.item(id: 7)).called(2)
    }
}
