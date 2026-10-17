import Testing
import SwiftMockito
@testable import app

/// `PostDetailViewModel` loads the author and comments for one post, and likes it
/// through a completion-handler API. Each test's comment names the SwiftMockito feature it shows.
@MainActor
struct PostDetailViewModelTests {
    let service = MockPostService()
    let viewModel: PostDetailViewModel

    init() { viewModel = PostDetailViewModel(post: .fixture, service: service) }

    /// `verifyInOrder` checks the author is fetched before the comments, and
    /// `verifyNoMoreInteractions` checks nothing else was requested.
    @Test func loadsAuthorThenComments() async {
        when { try await service.user(id: 7) }.thenReturn(.fixture)
        when { try await service.comments(postID: 1) }.thenReturn([.fixture])

        await viewModel.load()

        #expect(viewModel.state == .loaded(author: .fixture, comments: [.fixture]))
        await verifyInOrder {
            try await service.user(id: 7)
            try await service.comments(postID: 1)
        }
        verifyNoMoreInteractions(service)
    }

    /// A post with no comments still loads; the screen shows the author and an empty list.
    @Test func loadsPostWithNoComments() async {
        when { try await service.user(id: 7) }.thenReturn(.fixture)
        when { try await service.comments(postID: 1) }.thenReturn([])

        await viewModel.load()

        #expect(viewModel.state == .loaded(author: .fixture, comments: []))
    }

    /// `verifyNever` checks a call did not happen: no comments request once the author fails.
    @Test func stopsWhenAuthorFails() async {
        when { try await service.user(id: 7) }.thenThrow(Offline())

        await viewModel.load()

        #expect(viewModel.state == .failed("You're offline"))
        verifyNever { try await service.comments(postID: 1) }
    }

    /// `thenAnswer` runs your closure with the call's arguments, here to call the completion
    /// handler. Annotate the closure's parameter types when one of them is a callback.
    @Test func likeMarksPostLiked() async {
        when(service.likePost(id: 1, completion: { _ in }))
            .thenAnswer { (id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) in
                completion(.success(()))
            }

        await viewModel.like()

        #expect(viewModel.isLiked)
        verify(service.likePost(id: 1, completion: { _ in })).called(1)
    }

    /// The answer can report failure through the callback too.
    @Test func likeFailureLeavesPostUnliked() async {
        when(service.likePost(id: 1, completion: { _ in }))
            .thenAnswer { (id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) in
                completion(.failure(Offline()))
            }

        await viewModel.like()

        #expect(!viewModel.isLiked)
        #expect(viewModel.likeError == "You're offline")
    }

    /// `.called(1)` after two taps: the second like doesn't hit the network.
    @Test func secondLikeIsIgnored() async {
        when(service.likePost(id: 1, completion: { _ in }))
            .thenAnswer { (id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) in
                completion(.success(()))
            }

        await viewModel.like()
        await viewModel.like()

        verify(service.likePost(id: 1, completion: { _ in })).called(1)
    }
}
