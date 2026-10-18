import Testing
import SwiftMockito
@testable import App

@Suite struct UserRepositoryTests {
    let client = MockClient()
    var sut: UserRepository { UserRepository(client: client) }

    @Test func returnsCachedUserWithoutNetwork() async throws {
        when(client.cached(id: "42")).thenReturn(.fixture)

        let user = try await sut.user(id: "42")

        #expect(user == .fixture)
        verify(client.cached(id: "42")).called(1)
        verifyNoMoreInteractions(client)
    }

    @Test func doesNotSaveWhenFetchFails() async {
        when(client.cached(id: "42")).thenReturn(nil)
        await when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)

        await #expect(throws: ClientError.offline) { try await sut.user(id: "42") }
        verifyNever { try client.save(.fixture) }
    }

    @Test func legacyLoadDeliversUser() async throws {
        when(client.load(id: "42", completion: { _ in }))
            .thenAnswer { (id: String, completion: @escaping (Result<User, Error>) -> Void) in
                completion(.success(User(id: id, name: "Gytis")))
            }

        let user = try await sut.legacyUser(id: "42")

        #expect(user.id == "42")
    }

    @Test func fetchesAndSavesInOrder() async throws {
        when(client.cached(id: "42")).thenReturn(nil)
        await when { try await client.fetch(id: "42") }.thenReturn(.fixture)

        _ = try await sut.user(id: "42")

        await verifyInOrder {
            client.cached(id: "42")
            try await client.fetch(id: "42")
            try client.save(.fixture)
        }
    }
}
