import Foundation

struct User: Equatable, Sendable {
    let id: String
    let name: String

    static let fixture = User(id: "42", name: "Ada")
}

enum ClientError: Error, Equatable {
    case offline
}

protocol Client {
    var token: String { get set }
    var currentUser: User { get }
    func cached(id: String) -> User?
    func fetch(id: String) async throws -> User
    func save(_ user: User) throws
    func load(id: String, completion: @escaping (Result<User, Error>) -> Void)
}

/// Code under test from the spec's example.
struct UserRepository {
    let client: Client

    func user(id: String) async throws -> User {
        if let cached = client.cached(id: id) { return cached }
        let user = try await client.fetch(id: id)
        try client.save(user)
        return user
    }

    func legacyUser(id: String) async throws -> User {
        try await withCheckedThrowingContinuation { continuation in
            client.load(id: id) { continuation.resume(with: $0) }
        }
    }
}
