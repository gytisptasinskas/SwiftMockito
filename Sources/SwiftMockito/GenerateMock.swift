/// Marks protocols to mock.
///
/// It expands to nothing: the SwiftMockito build plugin reads it and generates `Mock<Protocol>`
/// into the test target. Attach it to any declaration, usually the suite that uses the mocks:
///
/// ```swift
/// import SwiftMockito
/// @testable import App
///
/// @GenerateMock(Client.self)
/// struct UserRepositoryTests {
///     let client = MockClient()
/// }
/// ```
///
/// Several suites may mark the same protocol; the target gets one mock. One marker can list
/// several protocols: `@GenerateMock(Client.self, Store.self)`. The plugin looks up each
/// protocol in the test target's dependencies and generates a class with the same signatures,
/// effects and access level. Protocols declared `internal` need `@testable import` of their
/// module. See <doc:GettingStarted> for setting up the plugin.
///
/// - Parameter protocols: The protocols to mock, written as `P.self`.
@attached(peer)
public macro GenerateMock(_ protocols: Any.Type...) = #externalMacro(module: "SwiftMockitoMacros", type: "GenerateMockMacro")
