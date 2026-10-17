import Foundation

/// A post from `GET /posts`.
struct Post: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

/// A user from `GET /users/{id}`. Fields the app doesn't show are ignored.
struct User: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let username: String
    let email: String
}

/// A comment from `GET /posts/{id}/comments`.
struct PostComment: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let postId: Int
    let name: String
    let email: String
    let body: String
}
