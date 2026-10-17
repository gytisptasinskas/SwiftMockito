import Testing
@testable import SwiftMockito

@GenerateMock(Client.self, Catalog.self, Screen.self, Feed.self, Edge.self, Store.self, Shapes.self, Escapes.self)
enum Mocks {}

@Suite struct ClientAcceptanceTests {
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
        when { try await client.fetch(id: "42") }.thenThrow(ClientError.offline)

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
        when { try await client.fetch(id: "42") }.thenReturn(.fixture)

        _ = try await sut.user(id: "42")

        await verifyInOrder {
            client.cached(id: "42")
            try await client.fetch(id: "42")
            try client.save(.fixture)
        }
        verifyNoMoreInteractions(client)
    }

    @Test func sequentialReturns() {
        when(client.cached(id: "42")).thenReturn(nil, .fixture)
        #expect(client.cached(id: "42") == nil)
        #expect(client.cached(id: "42") == .fixture)
        #expect(client.cached(id: "42") == .fixture)
    }

    @Test func propertyGetterAndSetter() {
        when(client.currentUser).thenReturn(.fixture)
        when(client.token).thenReturn("t")
        client.token = "new"
        #expect(client.currentUser == .fixture)
        #expect(client.token == "t")
        verify { client.token = "new" }.called(1)
        verify(client.token).called(1)
    }

    @Test func missingStubOnThrowingMemberThrows() async {
        await #expect(throws: MissingStubError.self) { try await client.fetch(id: "1") }
    }

    @Test func unstubbedVoidMemberReturns() {
        client.load(id: "1") { _ in Issue.record("completion must not run") }
        verify(client.load(id: "1", completion: { _ in })).called(1)
    }

    @Test func resetForgetsEverything() {
        when(client.cached(id: "1")).thenReturn(.fixture)
        _ = client.cached(id: "1")
        reset(client)
        verifyNever(client.cached(id: "1"))
    }

    @Test func dummiesNeverReachCodeUnderTest() {
        // Recording `currentUser` builds a dummy User; the real call returns the stub.
        when(client.currentUser).thenReturn(User(id: "real", name: "Real"))
        #expect(client.currentUser.id == "real")
    }

    @Test func unstubbedNonThrowingValueTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = MockClient().cached(id: "1")
        }
    }

    @Test func sentinelDummyNeverReachesRepository() async throws {
        // Process-wide, but dummies are only produced while recording, so this cannot
        // change other tests' real results.
        provideDummy(User(id: "DUMMY", name: "Dummy"))
        when(client.cached(id: "42")).thenReturn(nil)
        when { try await client.fetch(id: "42") }.thenReturn(.fixture)

        let user = try await sut.user(id: "42")

        #expect(user == .fixture)
        // verifyInOrder records `fetch` through its placeholder path, which now yields the sentinel.
        await verifyInOrder {
            client.cached(id: "42")
            try await client.fetch(id: "42")
            try client.save(.fixture)
        }
        verifyNoMoreInteractions(client)
    }
}
