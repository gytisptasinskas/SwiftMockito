import Foundation
import Testing
@testable import SwiftMockito

@Suite struct EscapesAcceptanceTests {
    let escapes = MockEscapes()

    @Test func answerCallsTheNonEscapingClosure() {
        when(escapes.perform({})).thenAnswer { (work: @escaping () -> Void) in work() }
        var ran = 0
        escapes.perform { ran += 1 }
        #expect(ran == 1)
    }

    @Test func callsVerifyWhateverTheClosure() {
        escapes.perform {}
        escapes.perform {}
        verify(escapes.perform({})).called(2)
        verifyNoMoreInteractions(escapes)
    }

    @Test func unstubbedVoidCallDoesNothing() async {
        escapes.perform { Issue.record("an unstubbed call must not run the closure") }
        await escapes.later { Issue.record("an unstubbed call must not run the closure") }
        verify(escapes.perform({})).called(1)
        await verify { await escapes.later({}) }.called(1)
    }

    @Test func valueArgumentsStillMatchExactly() {
        when(escapes.map(2, { _ in "" })).thenAnswer { (value: Int, transform: @escaping (Int) -> String) in
            transform(value) + "!"
        }
        #expect(escapes.map(2, { "\($0 * 10)" }) == "20!")
        verifyNever(escapes.map(3, { _ in "" }))
    }

    @Test func throwingMemberAnswerCanRethrowTheClosureError() throws {
        when { try escapes.attempt({ 0 }) }.thenAnswer { (work: @escaping () throws -> Int) in try work() + 1 }
        #expect(try escapes.attempt({ 41 }) == 42)
        #expect(throws: ClientError.offline) { try escapes.attempt({ throw ClientError.offline }) }
        verify { try escapes.attempt({ 0 }) }.called(2)
    }

    @Test func asyncMembersAnswerWithEveryClosure() async throws {
        await when { await escapes.later({}) }.thenAnswer { (work: @escaping () -> Void) async in work() }
        await when { try await escapes.load(id: "42", { _ in 0 }, { _ in true }) }
            .thenAnswer { (id: String, parse: @escaping (String) -> Int, validate: @escaping (Int) -> Bool) async throws in
                let value = parse(id)
                guard validate(value) else { throw ClientError.offline }
                return value
            }

        var ran = false
        await escapes.later { ran = true }
        #expect(ran)
        #expect(try await escapes.load(id: "42", { Int($0)! }, { $0 > 0 }) == 42)
        await #expect(throws: ClientError.offline) { try await escapes.load(id: "42", { Int($0)! }, { $0 < 0 }) }
        await verifyInOrder {
            await escapes.later({})
            try await escapes.load(id: "42", { _ in 0 }, { _ in true })
            try await escapes.load(id: "42", { _ in 0 }, { _ in true })
        }
    }

    @MainActor @Test func asyncAnswerRunsOnTheCallersActor() async {
        await when { await escapes.later({}) }.thenAnswer { (work: @escaping () -> Void) async in
            MainActor.assertIsolated()
            work()
        }
        var ran = false
        await escapes.later { ran = true }
        #expect(ran)
    }

    @Test func autoclosureIsEvaluatedOnlyByTheAnswer() {
        var evaluated = 0
        func message() -> String { evaluated += 1; return "hi" }
        escapes.log(message())
        #expect(evaluated == 0)

        var logged: [String] = []
        when(escapes.log("")).thenAnswer { (message: @escaping () -> String) in logged.append(message()) }
        escapes.log(message())
        #expect(logged == ["hi"])
        #expect(evaluated == 1)
    }

    @Test func escapingAndNonEscapingClosuresTogether() {
        when(escapes.subscribe({ _ in }, where: { _ in true }))
            .thenAnswer { (handler: @escaping (Int) -> Void, filter: @escaping (Int) -> Bool) in
                for value in 1...4 where filter(value) { handler(value) }
            }
        var received: [Int] = []
        escapes.subscribe({ received.append($0) }, where: { $0.isMultiple(of: 2) })
        #expect(received == [2, 4])
    }

    @Test func subscriptWithClosureParameter() {
        when(escapes[{ $0 }]).thenAnswer { (transform: @escaping (Int) -> Int) in transform(9) }
        #expect(escapes[{ $0 + 1 }] == 10)
        escapes[{ $0 }] = 3
        verify { escapes[{ $0 }] = 3 }.called(1)
    }

    #if DEBUG
    @Test func answerThatStoresTheClosureTraps() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            let escapes = MockEscapes()
            nonisolated(unsafe) var stored: (() -> Void)?
            when(escapes.perform({})).thenAnswer { (work: @escaping () -> Void) in stored = work }
            escapes.perform {}
            _ = stored
        }
        let stderr = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(stderr.contains("closure argument was escaped in withoutActuallyEscaping block"))
    }
    #endif
}
