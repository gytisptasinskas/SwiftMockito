import Testing
@testable import SwiftMockitoGeneratorCore

let markerFile = SourceInput(path: "/t/Mocks.swift", module: "AppTests", text: """
    import SwiftMockito
    @testable import App

    @GenerateMock(Client.self, Catalog.self)
    enum Mocks {}
    """)

func resolve(_ source: String, marker index: Int = 0) -> Result<MockModel, GeneratorFailure> {
    let idx = SourceIndex([markerFile, SourceInput(path: "/a/C.swift", module: "App", text: source)])
    return ProtocolResolver(index: idx).resolve(idx.markers(in: ["/t/Mocks.swift"])[index], testModule: "AppTests")
}

func methods(_ model: MockModel) -> [Method] {
    model.members.compactMap { if case .method(let m) = $0 { m } else { nil } }
}

@Suite struct ResolverTests {
    @Test func findsMarkersWithLocation() {
        let markers = SourceIndex([markerFile]).markers(in: ["/t/Mocks.swift"])
        #expect(markers.map(\.protocolName) == ["Client", "Catalog"])
        #expect(markers[0].line == 4)
        #expect(markers[0].column == 1)
    }

    @Test func modelsMethodsPropertiesAndEffects() throws {
        let model = try resolve("""
            import Foundation
            typealias Completion = (Result<User, Error>) -> Void
            protocol Client {
                var token: String { get set }
                var currentUser: User { get }
                func fetch(id: String) async throws -> User
                func load(id: String, completion: @escaping Completion)
            }
            struct User { let id: String }
            """).get()
        #expect(model.mockName == "MockClient")
        #expect(model.imports == ["import Foundation", "import SwiftMockito", "@testable import App"])
        guard case .property(let token) = model.members[0] else { Issue.record("token"); return }
        #expect(token.hasSetter)
        let fetch = methods(model)[0]
        #expect(fetch.isAsync && fetch.isThrowing && fetch.identity == "fetch(id:)")
        let load = methods(model)[1]
        #expect(load.parameters[1].isClosure)   // seen through the typealias
    }

    @Test func inheritedProtocolMembersComeFirst() throws {
        let model = try resolve("""
            protocol Base { func ping() }
            protocol Client: Base, Sendable { func pong() }
            """).get()
        #expect(methods(model).map(\.name) == ["ping", "pong"])
    }

    @Test func overloadsGetSignatureIdentities() throws {
        let model = try resolve("protocol Catalog { func item(id: Int) -> String; func item(id: String) -> String }", marker: 1).get()
        #expect(methods(model).map(\.identity) == ["item(id:) (Int) -> String", "item(id:) (String) -> String"])
    }

    @Test func parameterKinds() throws {
        let model = try resolve("protocol Client { func f<T>(_ a: T.Type, b: (Int, String), c: (() -> Void)?, _: Int) }").get()
        let p = methods(model)[0].parameters
        #expect(p[0].isMetatype && p[0].label == nil && p[0].name == "a")
        #expect(p[1].isTuple && p[1].label == "b")
        #expect(p[2].isClosure)
        #expect(p[3].name == "arg3")
    }

    @Test func subscriptsHaveNoExternalLabel() throws {
        let model = try resolve("protocol Client { subscript(index: Int) -> String { get set } }").get()
        guard case .subscriptMember(let s) = model.members[0] else { Issue.record("subscript"); return }
        #expect(s.identity == "subscript(_:)")
        #expect(s.parameters[0].label == nil && s.parameters[0].name == "index")
        #expect(s.hasSetter)
    }

    @Test(arguments: [
        ("static func make() -> Int", "Client: static requirements are not supported"),
        ("init()", "Client: initializers are not supported"),
        ("associatedtype Item", "Client: associated types are not supported"),
        ("func copy() -> Self", "Client: Self requirements are not supported"),
        ("func f() throws(MyError)", "Client.f: typed throws is not supported"),
        ("func f(_ x: () throws -> Void) rethrows", "Client.f: rethrows is not supported"),
    ])
    func unsupportedRequirementsAreErrorsAtTheMarker(requirement: String, message: String) {
        guard case .failure(let failure) = resolve("protocol Client { \(requirement) }") else {
            Issue.record("expected failure"); return
        }
        #expect(failure.diagnostics == [GeneratorDiagnostic(severity: .error, message: message, path: "/t/Mocks.swift", line: 4, column: 1)])
    }

    @Test func variadicAndKeywordNamedParameters() throws {
        let model = try resolve("""
            protocol Client {
                func log(_ message: String, _ extra: Int...)
                func find(for: String, runtime: Int, _ in: Int, newValue value: Int)
            }
            """).get()
        let log = methods(model)[0].parameters
        #expect(!log[0].isVariadic && log[1].isVariadic && log[1].type == "Int")
        let find = methods(model)[1].parameters
        #expect(find.map(\.label) == ["for", "runtime", nil, "newValue"])
        #expect(find.map(\.name) == ["arg0", "arg1", "arg2", "value"])
    }

    @Test func nonEscapingClosureParameterIsAnError() {
        guard case .failure(let failure) = resolve("protocol Client { func run(_ body: () -> Void) }") else {
            Issue.record("expected failure"); return
        }
        #expect(failure.diagnostics.map(\.message) == ["Client.run: non-escaping closure parameter 'body' is not supported; mark it @escaping"])
    }

    @Test func nonEscapingClosureThroughTypealiasIsAnError() {
        guard case .failure(let failure) = resolve("typealias Done = () -> Void\nprotocol Client { func run(done: Done) }") else {
            Issue.record("expected failure"); return
        }
        #expect(failure.diagnostics.map(\.message) == ["Client.run: non-escaping closure parameter 'done' is not supported; mark it @escaping"])
    }

    @Test func escapingOptionalAndAliasedClosuresAreAccepted() throws {
        let model = try resolve("""
            typealias Done = () -> Void
            protocol Client {
                func a(_ body: @escaping () -> Void)
                func b(_ body: (() -> Void)?)
                func c(_ body: @escaping Done)
                func d(_ body: Done?)
            }
            """).get()
        #expect(methods(model).count == 4)
    }

    @Test func actorProtocolIsUnsupported() {
        guard case .failure(let failure) = resolve("protocol Client: Actor {}") else { Issue.record("expected failure"); return }
        #expect(failure.diagnostics.map(\.message) == ["Client: Actor-constrained protocols are not supported"])
    }

    @Test func missingProtocolIsAnError() {
        guard case .failure(let failure) = resolve("") else { Issue.record("expected failure"); return }
        #expect(failure.diagnostics.map(\.message) == ["Client: protocol not found in the test target or its dependencies (protocols from binary frameworks are not supported)"])
    }

    @Test func unknownInheritedProtocolIsAnError() {
        guard case .failure(let failure) = resolve("protocol Client: CustomStringConvertible {}") else { Issue.record("expected failure"); return }
        #expect(failure.diagnostics.map(\.message) == ["Client: inherited protocol CustomStringConvertible not found in sources"])
    }

    @Test func memberNamedLikeMockInternalsCollides() {
        guard case .failure(let failure) = resolve("protocol Client { var runtime: Int { get } }") else { Issue.record("expected failure"); return }
        #expect(failure.diagnostics.map(\.message) == ["Client.runtime collides with SwiftMockito's Mock.runtime"])
    }

    @Test(arguments: ["func arg(_ x: Int)", "var arg: Int { get }"])
    func memberNamedArgCollides(requirement: String) {
        guard case .failure(let failure) = resolve("protocol Client { \(requirement) }") else { Issue.record("expected failure"); return }
        #expect(failure.diagnostics.map(\.message) == ["Client.arg collides with SwiftMockito's arg(_:)"])
    }

    @Test func parameterNamedArgGetsAPositionalInternalName() throws {
        let model = try resolve("protocol Client { func process(arg: Int, other: Int) }").get()
        let parameters = methods(model)[0].parameters
        #expect(parameters.map(\.label) == ["arg", "other"])
        #expect(parameters.map(\.name) == ["arg0", "other"])
    }

    @Test func globalActorAndAccessAreCarried() throws {
        let model = try resolve("@MainActor public protocol Client { func f() }").get()
        #expect(model.globalActor == "MainActor")
        #expect(model.access == "public ")
        #expect(model.imports == ["import SwiftMockito", "import App"])
    }

    @Test func getterEffectsOnProperties() throws {
        let model = try resolve("protocol Client { var latest: Int { get async }; var config: String { get throws } }").get()
        guard case .property(let latest) = model.members[0], case .property(let config) = model.members[1] else {
            Issue.record("properties"); return
        }
        #expect(latest.getterAsync && !latest.getterThrows && !latest.hasSetter)
        #expect(config.getterThrows && !config.getterAsync && !config.hasSetter)
    }

    @Test func packageProtocolKeepsPackageAccess() throws {
        let model = try resolve("package protocol Client { func f() }").get()
        #expect(model.access == "package ")
        #expect(model.imports.last == "import App")
    }

    @Test func diagnosticFormat() {
        let d = GeneratorDiagnostic(severity: .warning, message: "m", path: "/t/M.swift", line: 4, column: 1)
        #expect(d.description == "/t/M.swift:4:1: warning: m")
    }
}
