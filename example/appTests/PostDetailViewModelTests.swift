import Testing
import SwiftMockito
@testable import app

/// `PostDetailViewModel` loads the author and comments for one post, and likes it
/// through a completion-handler API. Each test's comment names the SwiftMockito feature it shows.
@GenerateMock(PostService.self)
@MainActor
struct PostDetailViewModelTests {
    let service = MockPostService()
    let viewModel: PostDetailViewModel

    init() { viewModel = PostDetailViewModel(post: .fixture, service: service) }

    /// `verifyInOrder` checks the author is fetched before the comments, and
    /// `verifyNoMoreInteractions` checks nothing else was requested.
    @Test func loadsAuthorThenComments() async {
        await when { try await service.user(id: 7) }.thenReturn(.fixture)
        await when { try await service.comments(postID: 1) }.thenReturn([.fixture])

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
        await when { try await service.user(id: 7) }.thenReturn(.fixture)
        await when { try await service.comments(postID: 1) }.thenReturn([])

        await viewModel.load()

        #expect(viewModel.state == .loaded(author: .fixture, comments: []))
    }

    /// `verifyNever` checks a call did not happen: no comments request once the author fails.
    @Test func stopsWhenAuthorFails() async {
        await when { try await service.user(id: 7) }.thenThrow(Offline())

        await viewModel.load()

        #expect(viewModel.state == .failed("You're offline"))
        await verifyNever { try await service.comments(postID: 1) }
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

    /// An answer can hold on to the callback and call it later, to test what happens while
    /// a request is still in flight: a second tap then doesn't send another request.
    @Test(.timeLimit(.minutes(1))) func likeWhileLikingIsIgnored() async {
        let pending = PendingCompletion()
        when(service.likePost(id: 1, completion: { _ in }))
            .thenAnswer { (id: Int, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) in
                if pending.completion == nil {
                    pending.completion = completion
                } else {
                    completion(.success(()))
                }
            }

        let firstTap = Task.immediate { @MainActor in await viewModel.like() }
        await viewModel.like()
        pending.completion?(.success(()))
        await firstTap.value

        #expect(viewModel.isLiked)
        verify(service.likePost(id: 1, completion: { _ in })).called(1)
    }
}

/// Holds a completion handler that a test calls later.
private final class PendingCompletion {
    var completion: (@Sendable (Result<Void, any Error>) -> Void)?
}
