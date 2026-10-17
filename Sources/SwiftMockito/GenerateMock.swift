/// Marks protocols to mock. It expands to nothing: the SwiftMockito build plugin reads it
/// and generates `Mock<Protocol>` into the test target. Attach it to any declaration, usually the
/// suite that uses the mocks. Several suites may mark the same protocol; the target gets one mock.
///
///     @GenerateMock(Client.self)
///     struct UserRepositoryTests { … }
@attached(peer)
public macro GenerateMock(_ protocols: Any.Type...) = #externalMacro(module: "SwiftMockitoMacros", type: "GenerateMockMacro")
