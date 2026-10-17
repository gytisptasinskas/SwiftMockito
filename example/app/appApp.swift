import SwiftUI

@main
struct appApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PostListView(viewModel: PostListViewModel(service: LivePostService()))
            }
        }
    }
}
