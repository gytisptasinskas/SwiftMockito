import Foundation
import Testing
@testable import SwiftMockito

private struct Token: Equatable, Sendable { let raw: String }
private struct Unbuildable {}

/// Serialized because the dummy registry is process-wide.
@Suite(.serialized) struct DummyTests {
    @Test func builtIns() {
        #expect(Dummies.resolve(Bool.self, for: "m") == false)
        #expect(Dummies.resolve(Int.self, for: "m") == 0)
        #expect(Dummies.resolve(UInt8.self, for: "m") == 0)
        #expect(Dummies.resolve(Double.self, for: "m") == 0)
        #expect(Dummies.resolve(Float.self, for: "m") == 0)
        #expect(Dummies.resolve(String.self, for: "m") == "")
        #expect(Dummies.resolve(Character.self, for: "m") == " ")
        #expect(Dummies.resolve(Int?.self, for: "m") == nil)
        #expect(Dummies.resolve([String].self, for: "m") == [])
        #expect(Dummies.resolve([String: Int].self, for: "m") == [:])
        #expect(Dummies.resolve(Set<Int>.self, for: "m") == [])
        #expect(Dummies.resolve(Data.self, for: "m") == Data())
        #expect(Dummies.resolve(Date.self, for: "m") == Date(timeIntervalSince1970: 0))
        #expect(Dummies.resolve(URL.self, for: "m") == URL(string: "about:blank"))
        #expect(Dummies.resolve(UUID.self, for: "m") == UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        Dummies.resolve(Void.self, for: "m")
    }

    @Test func resultUsesSuccessDummy() throws {
        let result = Dummies.resolve(Result<String, any Error>.self, for: "m")
        #expect(try result.get() == "")
    }

    @Test func providedDummyWinsOverFallbackAndBuiltIn() {
        provideDummy(Token(raw: "provided"))
        #expect(Dummies.resolve(Token.self, for: "m", fallback: { Token(raw: "fallback") }) == Token(raw: "provided"))
        provideDummy(42)
        #expect(Dummies.resolve(Int.self, for: "m") == 42)
        provideDummy(0)
    }

    @Test func fallbackUsedWhenNothingElse() {
        #expect(Dummies.resolve(Unbuildable?.self, for: "m") == nil)
        #expect(Dummies.resolve([Unbuildable].self, for: "m").isEmpty)
        _ = Dummies.resolve(Unbuildable.self, for: "m", fallback: { Unbuildable() })   // must not trap
    }

    @Test func placeholderNeverTraps() {
        #expect(Dummies.placeholder(Unbuildable.self) == nil)
        #expect(Dummies.placeholder(String.self) == "")
        #expect(Dummies.placeholder(Unbuildable.self, fallback: { Unbuildable() }) != nil)
    }

    @Test func missingDummyTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = Dummies.resolve(Unbuildable.self, for: "MockStore.thing()")
        }
    }

    @Test func missingDummyErrorSuggestsProvideDummy() {
        let error = MissingDummyError(typeName: "Unbuildable", member: "MockStore.thing()")
        #expect(error.description == "No dummy value for Unbuildable, needed while recording MockStore.thing(). Call provideDummy(_:) with a Unbuildable value before stubbing or verifying this member.")
    }
}
