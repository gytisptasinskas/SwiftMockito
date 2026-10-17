import Foundation
import SwiftUI

@main
struct appApp: App {
    var body: some Scene {
        WindowGroup {
            // ⌘U launches the app to host the unit tests. Skip the live screen then, so
            // running the tests never sends a request to JSONPlaceholder.
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                NavigationStack {
                    PostListView(viewModel: PostListViewModel(service: LivePostService()))
                }
            }
        }
    }
}
