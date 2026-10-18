import Testing
@testable import SwiftMockitoGeneratorCore

private func generateP(_ source: String) -> GeneratorResult {
    let marker = SourceInput(path: "/t/M.swift", module: "T", text: "@GenerateMock(P.self)\nenum M {}\n")
    let input = SourceInput(path: "/a/P.swift", module: "App", text: source)
    return Generator.generate(GeneratorConfiguration(markedPaths: [marker.path], inputs: [marker, input],
                                                     testModule: "T", outputDirectory: "/x"))
}

@Suite struct DummySynthesisTests {
    @Test func sdkTypeWithoutBuiltInWarnsAtMarker() {
        let result = generateP("import CoreGraphics\nprotocol P { func size() -> CGSize }")
        #expect(result.diagnostics == [GeneratorDiagnostic(severity: .warning,
            message: "MockP.size(): cannot build a dummy CGSize (not declared in sources); register one with provideDummy(_:) before stubbing or verifying it",
            path: "/t/M.swift", line: 1, column: 1)])
        #expect(result.files["MockP.swift"]?.contains("Dummies.resolve(CGSize.self, for: \"MockP.size()\")") == true)
    }

    /// A missing stub fails the test and returns this dummy, so the dispatch call carries it too.
    @Test func dispatchPassesTheSynthesizedDummy() throws {
        let result = generateP("""
            struct S { let a: Int }
            protocol P {
                func s() -> S
                func n() -> Int
                func make<T>() -> T
                func load() async -> S
            }
            """)
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("return runtime.invoke(\"s()\", key: [], dummy: Self._dummyS)"))
        #expect(file.contains("return await runtime.invoke(\"load()\", key: [], dummy: Self._dummyS)"))
        #expect(file.contains("return runtime.invoke(\"n()\", key: [])"))
        #expect(file.contains("return runtime.invoke(\"make()\", key: [arg(type: T.self)])"))
        #expect(result.diagnostics.count == 1)   // only the generic return, not one per use
    }

    /// An unstubbed `Void` member never calls its escaping callbacks, so the runtime is told their names to warn.
    @Test func dispatchNamesEscapingCallbacksOfVoidMembers() throws {
        let result = generateP("""
            protocol P {
                func load(id: Int, completion: @escaping (Int) -> Void)
                func send(done: @escaping () -> Void) async throws
                func each(_ body: (Int) -> Void)
                func value(then: @escaping () -> Void) -> Int
                func notify(_ handler: (() -> Void)?)
                func both(first: (() -> Void)?, second: @escaping () -> Void)
            }
            """)
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("return runtime.invoke(\"load(id:completion:)\", key: [arg(id)], args: id, completion, callbacks: [\"completion\"])"))
        #expect(file.contains("return try await runtime.invokeThrowing(\"send(done:)\", key: [], args: done, callbacks: [\"done\"])"))
        #expect(!file.contains("callbacks: [\"body\"]"))   // non-escaping: called during the call, if at all
        #expect(!file.contains("callbacks: [\"then\"]"))   // returns a value: a missing stub already fails
        // An optional callback only counts when one was passed.
        #expect(file.contains("args: handler, callbacks: handler == nil ? [] : [\"handler\"])"))
        #expect(file.contains("args: first, second, callbacks: [first == nil ? nil : \"first\", \"second\"].compactMap { $0 })"))
    }

    @Test func genericReturnWarns() {
        #expect(generateP("protocol P { func make<T>() -> T }").diagnostics.map(\.message) == [
            "MockP.make(): cannot build a dummy for generic return type T; call provideDummy(_:) for each concrete T you stub"
        ])
    }

    @Test func genericThrowingReturnNeedsNoDummy() {
        #expect(generateP("protocol P { func decode<T>() throws -> T }").diagnostics.isEmpty)
    }

    @Test func privateInitOnlyWarns() {
        #expect(generateP("struct S { private init() {} }\nprotocol P { func s() -> S }").diagnostics.map(\.message) == [
            "MockP.s(): cannot build a dummy S (no accessible initializer); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func explicitInitWithFewestParametersIsPreferred() throws {
        let result = generateP("""
            struct S {
                let a: Int
                let b: Int
                init(a: Int, b: Int) { self.a = a; self.b = b }
                init(a: Int) { self.a = a; b = 0 }
            }
            protocol P { func s() -> S }
            """)
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("S(a: Dummies.resolve(Int.self, for: \"S.init.a\"))"))
    }

    @Test func enumWithoutCasesWarns() {
        #expect(generateP("enum Empty {}\nprotocol P { func e() -> Empty }").diagnostics.map(\.message) == [
            "MockP.e(): cannot build a dummy Empty (enum has no cases); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func recursiveTypeWarns() {
        let result = generateP("struct A { let b: B }\nstruct B { let a: A }\nprotocol P { func a() -> A }")
        #expect(result.diagnostics.map(\.message) == [
            "MockP.a(): cannot build a dummy A (recursive type); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func optionalRecursionIsFine() {
        #expect(generateP("struct Node { let next: Node? }\nprotocol P { func n() -> Node }").diagnostics.isEmpty)
    }

    @Test func placeholderForThrowingMemberIsSilentButCachedIssuesStillWarnLater() {
        let types = "import CoreGraphics\nstruct S { let size: CGSize }\n"
        #expect(generateP(types + "protocol P { func s() throws -> S }").diagnostics.isEmpty)
        #expect(generateP(types + "protocol P { func a() throws -> S\n func b() -> S }").diagnostics.map(\.message) == [
            "MockP.b(): cannot build a dummy CGSize (not declared in sources); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func tupleInsideStructUsesTheStructKey() throws {
        let result = generateP("struct S { let pair: (Int, String) }\nprotocol P { func s() -> S }")
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("Dummies.resolve(Int.self, for: \"S.pair.0\")"))
    }

    @Test func protocolDummyDeclaresEveryRequirementKind() throws {
        let result = generateP("""
            protocol L { var level: Int { get set }\n subscript(i: Int) -> String { get }\n func make<T>(_ x: T) async throws -> [T] }
            protocol P { func l() -> any L }
            """)
        let file = try #require(result.files["MockP.swift"])
        #expect(result.diagnostics.isEmpty)
        #expect(file.contains("private final class _DummyL: L, @unchecked Sendable {"))
        #expect(file.contains("var level: Int { get { fatalError(\"SwiftMockito: dummy L.level must not be called\") } set { fatalError(\"SwiftMockito: dummy L.level must not be called\") } }"))
        #expect(file.contains("subscript(i: Int) -> String { fatalError("))
        #expect(file.contains("func make<T>(_ x: T) async throws -> [T] { fatalError("))
    }

    @Test func sdkSuperclassWarns() {
        #expect(generateP("import AppKit\nfinal class V: NSView {}\nprotocol P { func v() -> V }").diagnostics.map(\.message) == [
            "MockP.v(): cannot build a dummy V (superclass NSView not declared in sources); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func subclassWithoutInitUsesTheSuperclassInitializer() throws {
        let result = generateP("class B { init(x: Int) {} }\nfinal class C: B {}\nprotocol P { func c() -> C }")
        #expect(result.diagnostics.isEmpty)
        #expect(try #require(result.files["MockP.swift"]).contains("C(x: Dummies.resolve(Int.self, for: \"C.init.x\"))"))
    }

    @Test func classConformingToStandardProtocolFirstIsNotASubclass() {
        #expect(generateP("final class C: Equatable { static func == (a: C, b: C) -> Bool { true } }\nprotocol P { func c() -> C }").diagnostics.isEmpty)
    }

    @Test func publicProtocolNeedsPublicInitializerFromOtherModule() {
        let source = "public struct S { public let id: Int }\npublic protocol P { func s() -> S }"
        #expect(generateP(source).diagnostics.map(\.message) == [
            "MockP.s(): cannot build a dummy S (no initializer accessible from T); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func publicInitializerIsUsableFromOtherModule() throws {
        let result = generateP("public struct S { public init(id: Int) {} }\npublic protocol P { func s() -> S }")
        #expect(result.diagnostics.isEmpty)
        #expect(try #require(result.files["MockP.swift"]).contains("S(id: Dummies.resolve(Int.self, for: \"S.init.id\"))"))
    }

    @Test func observersAndMultiBindingsAreMemberwiseArguments() throws {
        let result = generateP("struct S { var a, b: Int; var c: String { didSet {} }; var d: Int = 1 }\nprotocol P { func s() -> S }")
        #expect(try #require(result.files["MockP.swift"]).contains("S(a: Dummies.resolve(Int.self, for: \"S.a\"), b: Dummies.resolve(Int.self, for: \"S.b\"), c: Dummies.resolve(String.self, for: \"S.c\"))"))
    }

    @Test func privateStoredPropertyWithoutDefaultHidesTheMemberwiseInitializer() throws {
        let result = generateP("struct S4 { var a: Int; private var d: Int }\nprotocol P { func s() -> S4 }")
        #expect(result.diagnostics.map(\.message) == [
            "MockP.s(): cannot build a dummy S4 (no accessible initializer); register one with provideDummy(_:) before stubbing or verifying it"
        ])
        #expect(try #require(result.files["MockP.swift"]).contains("_dummyS4") == false)
    }

    @Test func privateStoredPropertyWithDefaultIsLeftOutOfTheMemberwiseCall() throws {
        let result = generateP("struct S2 { var a: Int; private var d: Int?; private var e = 1 }\nprotocol P { func s() -> S2 }")
        #expect(result.diagnostics.isEmpty)
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("S2(a: Dummies.resolve(Int.self, for: \"S2.a\"))"))
    }

    @Test func explicitInitializerWorksDespiteAPrivateStoredProperty() throws {
        let result = generateP("struct S2 { var a: Int; private var d: Int?; init(a: Int) { self.a = a } }\nprotocol P { func s() -> S2 }")
        #expect(result.diagnostics.isEmpty)
        #expect(try #require(result.files["MockP.swift"]).contains("S2(a: Dummies.resolve(Int.self, for: \"S2.init.a\"))"))
    }

    @Test func privateSetterDoesNotHideTheMemberwiseInitializer() throws {
        let result = generateP("struct S3 { var a: Int; private(set) var b: Int }\nprotocol P { func s() -> S3 }")
        #expect(result.diagnostics.isEmpty)
        #expect(try #require(result.files["MockP.swift"]).contains("S3(a: Dummies.resolve(Int.self, for: \"S3.a\"), b: Dummies.resolve(Int.self, for: \"S3.b\"))"))
    }

    @Test func protocolDummyWarningNamesTheUnsupportedRequirement() {
        #expect(generateP("protocol L { static func make() -> Int }\nprotocol P { func l() -> any L }").diagnostics.map(\.message) == [
            "MockP.l(): cannot build a dummy any L (protocol has unsupported requirements: L: static requirements are not supported); register one with provideDummy(_:) before stubbing or verifying it"
        ])
    }

    @Test func typealiasReturnTypeUsesTheAliasedTypesDummy() throws {
        let result = generateP("typealias Handler = (Int) -> Void\ntypealias Box = S\nstruct S { let id: Int }\nprotocol P { func h() -> Handler; func b() -> Box }")
        #expect(result.diagnostics.isEmpty)
        let file = try #require(result.files["MockP.swift"])
        #expect(file.contains("return Dummies.resolve(Handler.self, for: \"MockP.h()\", fallback: { { _ in fatalError("))
        #expect(file.contains("return Dummies.resolve(Box.self, for: \"MockP.b()\", fallback: Self._dummyS)"))
    }

    @Test(arguments: [
        ("struct S { let id: Int }", "MockP.s(): cannot build a dummy S: S is declared in more than one module (App, Other); rename one of them"),
        ("class B { init() {} }\nfinal class S: B {}", "MockP.s(): cannot build a dummy S: superclass B is declared in more than one module (App, Other); rename one of them"),
    ])
    func typeDeclaredInTwoModulesIsAnAmbiguityError(app: String, message: String) {
        let other = app.hasPrefix("class") ? "class B { init(x: Int) {} }" : "struct S { let name: String }"
        let marker = SourceInput(path: "/t/M.swift", module: "T", text: "@GenerateMock(P.self)\nenum M {}\n")
        let result = Generator.generate(GeneratorConfiguration(markedPaths: [marker.path], inputs: [
            marker,
            SourceInput(path: "/a/P.swift", module: "App", text: app + "\nprotocol P { func s() throws -> S }"),
            SourceInput(path: "/o/S.swift", module: "Other", text: other),
        ], testModule: "T", outputDirectory: "/x"))
        #expect(result.diagnostics == [GeneratorDiagnostic(severity: .error, message: message, path: "/t/M.swift", line: 1, column: 1)])
        #expect(result.files["MockP.swift"]?.contains("#error(") == true)
    }
}
