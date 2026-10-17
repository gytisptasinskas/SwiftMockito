import Foundation
@testable import app

extension Post {
    static let fixture = Post(id: 1, userId: 7, title: "First post", body: "Hello")
    static let second = Post(id: 2, userId: 7, title: "Second post", body: "Again")
}

extension User {
    static let fixture = User(id: 7, name: "Ada Lovelace", username: "ada", email: "ada@example.com")
}

extension PostComment {
    static let fixture = PostComment(id: 10, postId: 1, name: "Nice", email: "bob@example.com", body: "Great post")
}

/// The one error every failure test uses.
struct Offline: Error, LocalizedError {
    var errorDescription: String? { "You're offline" }
}
