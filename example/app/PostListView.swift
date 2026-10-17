import SwiftUI

struct PostListView: View {
    @State var viewModel: PostListViewModel

    var body: some View {
        content
            .navigationTitle("Posts")
            .navigationDestination(for: Post.self) { post in
                PostDetailView(viewModel: PostDetailViewModel(post: post, service: viewModel.service))
            }
            .task {
                // Coming back from a detail screen re-runs `.task`; only load the first time.
                if viewModel.state == .loading { await viewModel.load() }
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .loaded(let posts):
            List {
                if let refreshError = viewModel.refreshError {
                    Label(refreshError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
                ForEach(posts) { post in
                    NavigationLink(value: post) {
                        Text(post.title)
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
        case .empty:
            ContentUnavailableView {
                Label("No posts", systemImage: "tray")
            } actions: {
                Button("Reload") { Task { await viewModel.load() } }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load posts", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await viewModel.load() } }
            }
        }
    }
}
