import Foundation
import Observation

/// Drives the post detail screen: loads the post's author, then its comments,
/// and lets the user like the post.
@MainActor
@Observable
final class PostDetailViewModel {
    enum State: Equatable {
        case loading
        case loaded(author: User, comments: [PostComment])
        case failed(String)
    }

    let post: Post
    private(set) var state: State = .loading
    private(set) var isLiked = false
    private(set) var likeError: String?
    private let service: any PostService

    init(post: Post, service: any PostService) {
        self.post = post
        self.service = service
    }

    func load() async {
        state = .loading
        do {
            let author = try await service.user(id: post.userId)
            let comments = try await service.comments(postID: post.id)
            state = .loaded(author: author, comments: comments)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func like() async {
        guard !isLiked else { return }
        do {
            // `likePost` reports through a completion handler; the continuation turns it into `await`.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                service.likePost(id: post.id) { result in
                    continuation.resume(with: result)
                }
            }
            isLiked = true
            likeError = nil
        } catch {
            likeError = error.localizedDescription
        }
    }
}
