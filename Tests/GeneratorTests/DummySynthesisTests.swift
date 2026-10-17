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
            message: "MockP.size(): cannot build a dummy CGSize (not declared in sources); call provideDummy(_:) with a CGSize before stubbing or verifying it",
            path: "/t/M.swift", line: 1, column: 1)])
        #expect(result.files["MockP.swift"]?.contains("Dummies.resolve(CGSize.self, for: \"MockP.size()\")") == true)
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
            "MockP.s(): cannot build a dummy S (no accessible initializer); call provideDummy(_:) with a S before stubbing or verifying it"
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
            "MockP.e(): cannot build a dummy Empty (enum has no cases); call provideDummy(_:) with a Empty before stubbing or verifying it"
        ])
    }

    @Test func recursiveTypeWarns() {
        let result = generateP("struct A { let b: B }\nstruct B { let a: A }\nprotocol P { func a() -> A }")
        #expect(result.diagnostics.map(\.message) == [
            "MockP.a(): cannot build a dummy A (recursive type); call provideDummy(_:) with a A before stubbing or verifying it"
        ])
    }

    @Test func optionalRecursionIsFine() {
        #expect(generateP("struct Node { let next: Node? }\nprotocol P { func n() -> Node }").diagnostics.isEmpty)
    }

    @Test func placeholderForThrowingMemberIsSilentButCachedIssuesStillWarnLater() {
        let types = "import CoreGraphics\nstruct S { let size: CGSize }\n"
        #expect(generateP(types + "protocol P { func s() throws -> S }").diagnostics.isEmpty)
        #expect(generateP(types + "protocol P { func a() throws -> S\n func b() -> S }").diagnostics.map(\.message) == [
            "MockP.b(): cannot build a dummy CGSize (not declared in sources); call provideDummy(_:) with a CGSize before stubbing or verifying it"
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
            "MockP.v(): cannot build a dummy V (superclass NSView not declared in sources); call provideDummy(_:) with a V before stubbing or verifying it"
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
            "MockP.s(): cannot build a dummy S (no initializer accessible from T); call provideDummy(_:) with a S before stubbing or verifying it"
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
}
