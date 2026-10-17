import Testing
import SwiftMockito
@testable import app

/// `PostListViewModel` with its only dependency, `PostService`, replaced by the
/// generated `MockPostService`. Each test's comment names the SwiftMockito feature it shows.
@GenerateMock(PostService.self)
@MainActor
struct PostListViewModelTests {
    let service = MockPostService()
    let viewModel: PostListViewModel

    init() { viewModel = PostListViewModel(service: service) }

    /// `verifyNoMoreInteractions`: creating the view model doesn't touch the network.
    @Test func startsLoading() {
        #expect(viewModel.state == .loading)
        verifyNoMoreInteractions(service)
    }

    /// `thenReturn` stubs a value, `verify(…).called(1)` checks the call happened once,
    /// and `verifyNoMoreInteractions` checks nothing else was called.
    @Test func showsPosts() async {
        when { try await service.posts() }.thenReturn([.fixture])

        await viewModel.load()

        #expect(viewModel.state == .loaded([.fixture]))
        verify { try await service.posts() }.called(1)
        verifyNoMoreInteractions(service)
    }

    /// An empty response is its own state, not an endless spinner.
    @Test func showsEmptyStateForNoPosts() async {
        when { try await service.posts() }.thenReturn([])

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    /// `thenThrow` makes the mocked call throw.
    @Test func showsErrorWhenLoadFails() async {
        when { try await service.posts() }.thenThrow(Offline())

        await viewModel.load()

        #expect(viewModel.state == .failed("You're offline"))
    }

    /// `thenReturn(a, b)` returns values in sequence: the first call gets `a`, the next `b`.
    @Test func refreshShowsNewPosts() async {
        when { try await service.posts() }.thenReturn([.fixture], [.fixture, .second])

        await viewModel.load()
        #expect(viewModel.state == .loaded([.fixture]))
        await viewModel.refresh()

        #expect(viewModel.state == .loaded([.fixture, .second]))
        verify { try await service.posts() }.called(2)
    }

    /// The newest stub wins: re-stubbing `posts()` with `thenThrow` replaces the earlier
    /// `thenReturn` for every later call.
    @Test func failedRefreshKeepsPreviousPosts() async {
        when { try await service.posts() }.thenReturn([.fixture])
        await viewModel.load()

        when { try await service.posts() }.thenThrow(Offline())
        await viewModel.refresh()

        #expect(viewModel.state == .loaded([.fixture]))
        #expect(viewModel.refreshError == "You're offline")
    }

    /// `reset` clears the mock's stubs and recorded calls, so the test can start a new phase.
    @Test func successfulRefreshClearsError() async {
        when { try await service.posts() }.thenReturn([.fixture])
        await viewModel.load()
        when { try await service.posts() }.thenThrow(Offline())
        await viewModel.refresh()
        #expect(viewModel.refreshError == "You're offline")

        reset(service)
        when { try await service.posts() }.thenReturn([.second])
        await viewModel.refresh()

        #expect(viewModel.state == .loaded([.second]))
        #expect(viewModel.refreshError == nil)
        verify { try await service.posts() }.called(1)
    }
}
