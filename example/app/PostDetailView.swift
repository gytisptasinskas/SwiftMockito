import SwiftUI

struct PostDetailView: View {
    @State var viewModel: PostDetailViewModel

    var body: some View {
        List {
            Section {
                Text(viewModel.post.title)
                    .font(.headline)
                Text(viewModel.post.body)
                if case .loaded(let author, _) = viewModel.state {
                    Label(author.name, systemImage: "person")
                        .foregroundStyle(.secondary)
                }
            }
            if let likeError = viewModel.likeError {
                Label(likeError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            comments
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await viewModel.like() }
                } label: {
                    Image(systemName: viewModel.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(viewModel.isLiked ? .red : .primary)
                }
                .accessibilityLabel(viewModel.isLiked ? "Liked" : "Like")
            }
        }
        .task {
            if viewModel.state == .loading { await viewModel.load() }
        }
    }

    @ViewBuilder private var comments: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
        case .loaded(_, let comments):
            Section("Comments") {
                if comments.isEmpty {
                    Text("No comments")
                        .foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(comment.name)
                            .font(.subheadline.bold())
                        Text(comment.body)
                    }
                }
            }
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load details", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await viewModel.load() } }
            }
        }
    }
}
