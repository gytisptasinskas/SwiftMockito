import Testing
@testable import SwiftMockito

@Suite struct VerifyInOrderTests {
    let mock = SampleMock()
    let other = SampleMock()

    init() {
        // Unstubbed non-Void members trap (spec), so stub every `cached(id:)` the tests call.
        for m in [mock, other] {
            for id in ["1", "2", "4", "noise"] { when(m.cached(id: id)).thenReturn(nil) }
        }
    }

    func failures(_ body: () -> Void) -> [String] {
        let box = MessageBox()
        Reporter.$sink.withValue({ message, _ in box.append(message) }, operation: body)
        return box.messages
    }

    nonisolated(nonsending) func failures(_ body: nonisolated(nonsending) () async -> Void) async -> [String] {
        let box = MessageBox()
        await Reporter.$sink.withValue({ message, _ in box.append(message) }, operation: body)
        return box.messages
    }

    @Test func passesWithUnrelatedCallsBetween() async {
        _ = mock.cached(id: "1")
        _ = mock.cached(id: "noise")
        _ = try? await mock.fetch(id: "2")
        try? mock.save("3")
        let messages = await failures {
            await verifyInOrder {
                mock.cached(id: "1")
                try await mock.fetch(id: "2")
                try mock.save("3")
            }
        }
        #expect(messages.isEmpty)
    }

    @Test func syncOverloadInSyncContext() {
        _ = mock.cached(id: "1")
        try? mock.save("2")
        #expect(failures {
            verifyInOrder {
                mock.cached(id: "1")
                try mock.save("2")
            }
        }.isEmpty)
    }

    @Test func failsWhenOrderIsReversed() {
        try? mock.save("2")
        _ = mock.cached(id: "1")
        #expect(failures {
            verifyInOrder {
                mock.cached(id: "1")
                try mock.save("2")
            }
        } == ["verifyInOrder: SampleMock.save(_:) with (\"2\") was not called after SampleMock.cached(id:) with (\"1\").\nRecorded calls to save(_:): (\"2\")"])
    }

    @Test func orderSpansMocks() {
        _ = mock.cached(id: "1")
        _ = other.cached(id: "2")
        #expect(failures {
            verifyInOrder {
                mock.cached(id: "1")
                other.cached(id: "2")
            }
        }.isEmpty)
    }

    @Test func orderAcrossMocksIsGlobal() {
        _ = other.cached(id: "2")
        _ = mock.cached(id: "1")
        #expect(failures {
            verifyInOrder {
                mock.cached(id: "1")
                other.cached(id: "2")
            }
        }.count == 1)
    }

    @Test func matchedCallsAreConsumed() {
        _ = mock.cached(id: "1")
        verifyInOrder { mock.cached(id: "1") }
        #expect(failures { verifyNoMoreInteractions(mock) }.isEmpty)
    }

    @Test func emptyBlockIsMisuse() {
        #expect(failures { verifyInOrder { } } == ["verifyInOrder: expected at least one mock call, recorded 0."])
    }

    @Test func memberWithoutPlaceholderIsMisuse() {
        #expect(failures {
            verifyInOrder {
                try mock.decode(Int.self)
                mock.cached(id: "1")
            }
        } == ["verifyInOrder: SampleMock.decode(_:) has no placeholder return value, so the calls after it could not be recorded. Call provideDummy(_:) for its return type."])
    }

    @MainActor @Test func syncOverloadOnMainActorRecordsAsyncLines() {
        _ = mock.cached(id: "1")
        #expect(failures {
            verifyInOrder {
                mock.cached(id: "1")
                try await mock.fetch(id: "2")
            }
        } == ["verifyInOrder: SampleMock.fetch(id:) with (\"2\") was not called after SampleMock.cached(id:) with (\"1\").\nNo calls to fetch(id:) were recorded."])
    }

    @MainActor @Test func asyncOverloadOnMainActorPasses() async {
        _ = mock.cached(id: "1")
        _ = try? await mock.fetch(id: "2")
        let messages = await failures {
            await verifyInOrder {
                mock.cached(id: "1")
                try await mock.fetch(id: "2")
            }
        }
        #expect(messages.isEmpty)
    }

    @MainActor @Test func asyncOverloadOnMainActorReportsMissingCall() async {
        _ = mock.cached(id: "1")
        let messages = await failures {
            await verifyInOrder {
                mock.cached(id: "1")
                try await mock.fetch(id: "2")
            }
        }
        #expect(messages == ["verifyInOrder: SampleMock.fetch(id:) with (\"2\") was not called after SampleMock.cached(id:) with (\"1\").\nNo calls to fetch(id:) were recorded."])
    }

    @MainActor @Test func asyncOverloadOnMainActorReportsReversedOrder() async {
        _ = try? await mock.fetch(id: "2")
        _ = mock.cached(id: "1")
        let messages = await failures {
            await verifyInOrder {
                mock.cached(id: "1")
                try await mock.fetch(id: "2")
            }
        }
        #expect(messages.count == 1)
    }
}
