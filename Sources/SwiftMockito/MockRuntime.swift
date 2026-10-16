import Foundation

/// Lock-protected stubs and call history for one mock instance.
public final class MockRuntime: @unchecked Sendable {
    public let mockName: String
    public let site: CallSite

    private let lock = NSLock()
    private var stubs: [StubRecord] = []
    private var calls: [CallRecord] = []

    init(mockName: String, site: CallSite) {
        self.mockName = mockName
        self.site = site
    }

    // MARK: Dispatch used by generated code

    public func invoke<each A, R>(_ member: String, key: [Argument], args: repeat each A) -> R {
        switch resolve(member, key: key, R.self) {
        case .value(let value):
            return value
        case .answer(let answer):
            guard let sync = answer.sync else { trap("\(qualified(member)) is synchronous but has an async answer.") }
            do { return try sync((repeat each args)) as! R } catch { trapUnexpected(error, member) }
        case .error(let error):
            trapUnexpected(error, member)
        case .missing(let missing):
            Reporter.trap(missing.description, at: site)
        }
    }

    public func invoke<each A, R>(_ member: String, key: [Argument], args: repeat each A) async -> R {
        switch resolve(member, key: key, R.self) {
        case .value(let value):
            return value
        case .answer(let answer):
            do { return try await run(answer, (repeat each args)) } catch { trapUnexpected(error, member) }
        case .error(let error):
            trapUnexpected(error, member)
        case .missing(let missing):
            Reporter.trap(missing.description, at: site)
        }
    }

    public func invokeThrowing<each A, R>(_ member: String, key: [Argument], args: repeat each A) throws -> R {
        switch resolve(member, key: key, R.self) {
        case .value(let value):
            return value
        case .answer(let answer):
            guard let sync = answer.sync else { trap("\(qualified(member)) is synchronous but has an async answer.") }
            return try sync((repeat each args)) as! R
        case .error(let error):
            throw error
        case .missing(let missing):
            throw missing
        }
    }

    public func invokeThrowing<each A, R>(_ member: String, key: [Argument], args: repeat each A) async throws -> R {
        switch resolve(member, key: key, R.self) {
        case .value(let value): return value
        case .answer(let answer): return try await run(answer, (repeat each args))
        case .error(let error): throw error
        case .missing(let missing): throw missing
        }
    }

    // MARK: Storage used by stubbing and verification

    func install(_ stub: StubRecord) {
        lock.withLock { stubs.append(stub) }
    }

    func callsSnapshot() -> [CallRecord] {
        lock.withLock { calls }
    }

    func stubsSnapshot(member: String) -> [StubRecord] {
        lock.withLock { stubs.filter { $0.member == member } }
    }

    func markVerified(_ ids: Set<Int>) {
        lock.withLock {
            for index in calls.indices where ids.contains(calls[index].id) {
                calls[index].verified = true
            }
        }
    }

    func reset() {
        lock.withLock {
            stubs.removeAll()
            calls.removeAll()
        }
    }

    // MARK: Resolution

    private enum Resolution<R> {
        case value(R)
        case answer(StoredAnswer)
        case error(any Error)
        case missing(MissingStubError)
    }

    private func resolve<R>(_ member: String, key: [Argument], _: R.Type) -> Resolution<R> {
        // User `==` runs inside `matches`, so it must not run under the lock.
        let candidates: [StubRecord] = lock.withLock {
            calls.append(CallRecord(id: CallClock.next(), member: member, key: key, verified: false))
            return stubs
        }
        let found: (StubRecord, Int)? = candidates.last(where: { $0.matches(member: member, key: key) }).map { stub in
            lock.withLock {
                defer { stub.nextIndex += 1 }
                return (stub, stub.nextIndex)
            }
        }
        guard let (stub, index) = found else {
            if R.self == Void.self { return .value(() as! R) }
            return .missing(missingStubError(member, key: key))
        }
        switch stub.response {
        case .values(let values): return .value(values[min(index, values.count - 1)] as! R)
        case .error(let error): return .error(error)
        case .answer(let answer): return .answer(answer)
        }
    }

    private func run<R>(_ answer: StoredAnswer, _ packed: Any) async throws -> R {
        if let async = answer.async { return try await async(packed) as! R }
        return try answer.sync!(packed) as! R
    }

    private func missingStubError(_ member: String, key: [Argument]) -> MissingStubError {
        MissingStubError(
            mock: mockName,
            member: member,
            arguments: key.map(\.description),
            configuredStubs: stubsSnapshot(member: member).map { stub in
                "(\(stub.key.map(\.description).joined(separator: ", "))) at \(stub.site)"
            },
            site: site
        )
    }

    private func qualified(_ member: String) -> String { "\(mockName).\(member)" }

    private func trap(_ message: String) -> Never { Reporter.trap(message, at: site) }

    private func trapUnexpected(_ error: any Error, _ member: String) -> Never {
        trap("\(qualified(member)) cannot throw, but its stub produced \(error).")
    }
}

/// Process-wide call order, so `verifyInOrder` can order calls across mocks.
enum CallClock {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value = 0

    static func next() -> Int {
        lock.withLock {
            defer { value += 1 }
            return value
        }
    }
}

struct CallRecord {
    let id: Int
    let member: String
    let key: [Argument]
    var verified: Bool

    func matches(member: String, key: [Argument]) -> Bool {
        self.member == member && keysMatch(self.key, key)
    }
}

final class StubRecord: @unchecked Sendable {
    let member: String
    let key: [Argument]
    let site: CallSite
    let response: StoredResponse
    /// Guarded by the owning runtime's lock.
    var nextIndex = 0

    init(target: StubTarget, response: StoredResponse) {
        member = target.member
        key = target.key
        site = target.site
        self.response = response
    }

    func matches(member: String, key: [Argument]) -> Bool {
        self.member == member && keysMatch(self.key, key)
    }
}

func keysMatch(_ lhs: [Argument], _ rhs: [Argument]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.matches($1) }
}
