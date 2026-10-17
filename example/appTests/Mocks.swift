import SwiftMockito
@testable import app

/// The SwiftMockito build plugin reads this marker and generates `MockPostService`
/// at build time. There is no checked-in mock file.
@GenerateMock(PostService.self)
enum Mocks {}
