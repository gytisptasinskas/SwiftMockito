import Foundation
import Testing
@testable import app

/// The models decode the JSON that jsonplaceholder.typicode.com actually returns.
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func decodesPost() throws {
        let post = try decode(Post.self, #"{"userId": 1, "id": 3, "title": "Title", "body": "Body"}"#)
        #expect(post == Post(id: 3, userId: 1, title: "Title", body: "Body"))
    }

    @Test func decodesUser() throws {
        let user = try decode(User.self, #"""
            {
              "id": 7, "name": "Kurtis Weissnat", "username": "Elwyn.Skiles", "email": "Telly.Hoeger@billy.biz",
              "address": {"street": "Rex Trail", "city": "Howemouth", "geo": {"lat": "24.8918", "lng": "21.8984"}},
              "phone": "210.067.6132", "website": "elvis.io",
              "company": {"name": "Johns Group", "catchPhrase": "Configurable multimedia task-force", "bs": "generate"}
            }
            """#)
        #expect(user == User(id: 7, name: "Kurtis Weissnat", username: "Elwyn.Skiles", email: "Telly.Hoeger@billy.biz"))
    }

    @Test func decodesComment() throws {
        let comment = try decode(PostComment.self, #"{"postId": 1, "id": 2, "name": "Name", "email": "a@b.c", "body": "Nice"}"#)
        #expect(comment == PostComment(id: 2, postId: 1, name: "Name", email: "a@b.c", body: "Nice"))
    }
}
