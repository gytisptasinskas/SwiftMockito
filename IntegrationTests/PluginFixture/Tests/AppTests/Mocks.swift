import SwiftMockito
@testable import App

// The module-qualified spelling and a trailing comma, which the plugin's scanner must accept too.
@SwiftMockito.GenerateMock(Client.self, )
enum Mocks {}
