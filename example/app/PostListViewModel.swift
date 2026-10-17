import Foundation
import Observation

/// Drives the post list screen: loads posts from `PostService`, then lets the user
/// pull to refresh without losing what's on screen if the refresh fails.
@MainActor
@Observable
final class PostListViewModel {
    enum State: Equatable {
        case loading
        case loaded([Post])
        case empty
        case failed(String)
    }

    private(set) var state: State = .loading
    /// Set when a refresh fails while posts are already showing; the old posts stay.
    private(set) var refreshError: String?
    let service: any PostService

    init(service: any PostService) {
        self.service = service
    }

    func load() async {
        state = .loading
        await fetch()
    }

    func refresh() async {
        await fetch()
    }

    private func fetch() async {
        do {
            let posts = try await service.posts()
            state = posts.isEmpty ? .empty : .loaded(posts)
            refreshError = nil
        } catch {
            if case .loaded = state {
                refreshError = error.localizedDescription
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }
}
