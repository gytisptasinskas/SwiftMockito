import Foundation

/// The real `PostService`, talking to https://jsonplaceholder.typicode.com.
struct LivePostService: PostService {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = URL(string: "https://jsonplaceholder.typicode.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    func posts() async throws -> [Post] {
        try await get("posts")
    }

    func user(id: Int) async throws -> User {
        try await get("users/\(id)")
    }

    func comments(postID: Int) async throws -> [PostComment] {
        try await get("posts/\(postID)/comments")
    }

    func likePost(id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        var request = URLRequest(url: baseURL.appending(path: "posts/\(id)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"liked": true}"#.utf8)
        session.dataTask(with: request) { _, response, error in
            if let error {
                completion(.failure(error))
            } else if Self.isSuccess(response) {
                completion(.success(()))
            } else {
                completion(.failure(URLError(.badServerResponse)))
            }
        }.resume()
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appending(path: path))
        guard Self.isSuccess(response) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func isSuccess(_ response: URLResponse?) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}
