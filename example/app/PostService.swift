/// Everything the view models need from the network.
///
/// The view models depend on this protocol, not on `URLSession`, so the tests can
/// swap in `MockPostService`, which SwiftMockito generates from this declaration.
protocol PostService: Sendable {
    func posts() async throws -> [Post]
    func user(id: Int) async throws -> User
    func comments(postID: Int) async throws -> [PostComment]

    /// Callback-style on purpose, like many older SDK APIs. The tests use it to show
    /// `thenAnswer` driving a completion handler.
    func likePost(id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void)
}
