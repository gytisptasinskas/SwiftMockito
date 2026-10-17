/// Marks protocols to mock. It expands to nothing: the SwiftMockito build plugin reads it
/// and generates `Mock<Protocol>` into the test target.
///
///     @GenerateMock(Client.self)
///     enum Mocks {}
@attached(peer)
public macro GenerateMock(_ protocols: Any.Type...) = #externalMacro(module: "SwiftMockitoMacros", type: "GenerateMockMacro")
