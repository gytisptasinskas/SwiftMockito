import Foundation
import Testing
@testable import SwiftMockito

private final class PlainReference {}
private final class EquatableReference: Equatable {
    let id: Int
    init(id: Int) { self.id = id }
    static func == (lhs: EquatableReference, rhs: EquatableReference) -> Bool { lhs.id == rhs.id }
}
private protocol ClassBound: AnyObject {}
private final class EquatableBound: Equatable, ClassBound {
    let id: Int
    init(id: Int) { self.id = id }
    static func == (lhs: EquatableBound, rhs: EquatableBound) -> Bool { lhs.id == rhs.id }
}
private final class PlainBound: ClassBound {}
private protocol Shape {}
private struct Square: Shape, Equatable {}

@Suite struct ArgumentTests {
    @Test func equatableValuesCompareByValue() {
        #expect(arg("42").matches(arg("42")))
        #expect(!arg("42").matches(arg("7")))
        #expect(arg(Optional<Int>.none).matches(arg(Optional<Int>.none)))
        #expect(arg([1, 2]).matches(arg([1, 2])))
        #expect(arg(["a": 1]).matches(arg(["a": 1])))
    }

    @Test func differentTypesNeverMatch() {
        #expect(!arg(1).matches(arg(Int64(1))))
    }

    @Test func tuplesOfEquatablesCompareByValue() {
        #expect(arg((1, "a")).matches(arg((1, "a"))))
        #expect(!arg((1, "a")).matches(arg((1, "b"))))
    }

    @Test func nonEquatableClassesCompareByIdentity() {
        let a = PlainReference(), b = PlainReference()
        #expect(arg(a).matches(arg(a)))
        #expect(!arg(a).matches(arg(b)))
    }

    @Test func equatableClassesCompareByValue() {
        #expect(arg(EquatableReference(id: 1)).matches(arg(EquatableReference(id: 1))))
    }

    @Test func genericContextFallsBackToRuntimeEquatable() {
        func erased<T>(_ value: T) -> Argument { arg(value) }
        #expect(erased(5).matches(erased(5)))
        #expect(erased(Square()).isSupported)
        let reference = PlainReference()
        #expect(erased(reference).matches(erased(reference)))
    }

    @Test func equatableClassesInClassBoundExistentialsCompareByValue() {
        let a: any ClassBound = EquatableBound(id: 1)
        let b: any ClassBound = EquatableBound(id: 1)
        let other: any ClassBound = EquatableBound(id: 2)
        #expect(arg(a).matches(arg(b)))
        #expect(!arg(a).matches(arg(other)))
        #expect(arg(a).matches(arg(EquatableBound(id: 1))))
        #expect(arg(EquatableBound(id: 1)).matches(arg(b)))
    }

    @Test func equatableClassesInAnyObjectGenericsCompareByValue() {
        func viaAnyObject<T: AnyObject>(_ value: T) -> Argument { arg(value) }
        #expect(viaAnyObject(EquatableBound(id: 1)).matches(viaAnyObject(EquatableBound(id: 1))))
        #expect(!viaAnyObject(EquatableBound(id: 1)).matches(viaAnyObject(EquatableBound(id: 2))))
        #expect(viaAnyObject(EquatableBound(id: 1)).matches(arg(EquatableBound(id: 1))))
        let existential: any ClassBound = EquatableBound(id: 1)
        #expect(viaAnyObject(existential).matches(arg(EquatableBound(id: 1))))
    }

    @Test func nonEquatableClassesCompareByIdentityOnEveryPath() {
        func viaAnyObject<T: AnyObject>(_ value: T) -> Argument { arg(value) }
        let a = PlainBound(), b = PlainBound()
        let existentialA: any ClassBound = a
        let existentialB: any ClassBound = b
        #expect(arg(existentialA).matches(arg(a)))
        #expect(!arg(existentialA).matches(arg(existentialB)))
        #expect(viaAnyObject(a).matches(viaAnyObject(a)))
        #expect(!viaAnyObject(a).matches(viaAnyObject(b)))
    }

    @Test func existentialHoldingEquatableIsSupported() {
        let shape: any Shape = Square()
        #expect(arg(shape).isSupported)
    }

    @Test func otherValuesAreUnsupported() {
        let unsupported = arg(Opaque())
        #expect(!unsupported.isSupported)
        #expect(!unsupported.matches(unsupported))
        #expect(unsupported.typeName.hasSuffix("Opaque"))
    }

    @Test func typeKeysCompareByType() {
        #expect(arg(type: Int.self).matches(arg(type: Int.self)))
        #expect(!arg(type: Int.self).matches(arg(type: String.self)))
    }

    @Test func descriptionUsesReflection() {
        #expect(arg("42").description == "\"42\"")
        #expect(arg(type: Int.self).description == "Swift.Int.self")
    }

    @Test func unsupportedErrorNamesMemberPositionAndType() {
        let error = UnsupportedExactMatchingError(member: "MockClient.render(_:)", position: 0, typeName: "Opaque")
        #expect(error.description == "MockClient.render(_:) argument 0 has type Opaque, which is neither Equatable nor a class; exact matching cannot compare it.")
    }
}
