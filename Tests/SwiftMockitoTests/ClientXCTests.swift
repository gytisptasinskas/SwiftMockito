import XCTest
@testable import SwiftMockito

/// The Swift Testing acceptance tour, run from `XCTestCase`. Failures must surface as XCTest
/// failures at the test's line, and closures may capture `self`.
final class ClientXCTests: XCTestCase {
    let client = MockClient()
    var sut: UserRepository { UserRepository(client: client) }

    func testReturnsCachedUserWithoutNetwork() async throws {
        when(client.cached(id: "42")).thenReturn(.fixture)

        let user = try await sut.user(id: "42")

        XCTAssertEqual(user, .fixture)
        verify(client.cached(id: "42")).called(1)
        verifyNoMoreInteractions(client)
    }

    func testDoesNotSaveWhenFetchFails() async {
        when(client.cached(id: "42")).thenReturn(nil)
        await when { try await self.client.fetch(id: "42") }.thenThrow(ClientError.offline)

        do {
            _ = try await sut.user(id: "42")
            XCTFail("expected ClientError.offline")
        } catch {
            XCTAssertEqual(error as? ClientError, .offline)
        }
        verifyNever { try self.client.save(.fixture) }
    }

    func testLegacyLoadDeliversUser() async throws {
        when(client.load(id: "42", completion: { _ in }))
            .thenAnswer { (id: String, completion: @escaping (Result<User, Error>) -> Void) in
                completion(.success(User(id: id, name: "Gytis")))
            }

        let user = try await sut.legacyUser(id: "42")

        XCTAssertEqual(user.id, "42")
    }

    func testFetchesAndSavesInOrder() async throws {
        when(client.cached(id: "42")).thenReturn(nil)
        await when { try await self.client.fetch(id: "42") }.thenReturn(.fixture)

        _ = try await sut.user(id: "42")

        await verifyInOrder {
            self.client.cached(id: "42")
            try await self.client.fetch(id: "42")
            try self.client.save(.fixture)
        }
    }

    func testSequentialReturnsAndReset() {
        when(client.cached(id: "1")).thenReturn(nil, .fixture)
        XCTAssertNil(client.cached(id: "1"))
        XCTAssertEqual(client.cached(id: "1"), .fixture)

        reset(client)
        when(client.cached(id: "1")).thenReturn(nil)
        XCTAssertNil(client.cached(id: "1"))
        verify(client.cached(id: "1")).called(1)
    }

    func testMissingStubOnThrowingMemberThrows() async {
        do {
            _ = try await client.fetch(id: "1")
            XCTFail("expected MissingStubError")
        } catch {
            XCTAssertTrue(error is MissingStubError)
        }
    }

    func testFailedVerificationIsAnXCTestFailure() {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.compactDescription.contains("MockClient.cached(id:)")
                && issue.sourceCodeContext.location?.fileURL.lastPathComponent == "ClientXCTests.swift"
        }
        XCTExpectFailure("verify reports through XCTFail", options: options) {
            verify(client.cached(id: "1")).called(1)
        }
    }
}

/// A mock of a `@MainActor` protocol, used from a main-actor `XCTestCase`.
@MainActor
final class ScreenXCTests: XCTestCase {
    func testGlobalActorMockWorks() {
        let screen = MockScreen()
        when(screen.isVisible).thenReturn(true)

        screen.render(title: "Home")

        XCTAssertTrue(screen.isVisible)
        verify(screen.render(title: "Home")).called(1)
    }
}
