import Testing
@testable import SwiftMockito

@Suite struct FeedAcceptanceTests {
    let feed = MockFeed()

    @Test func asyncGetterAndAsyncMethods() async {
        await when { await feed.latest }.thenReturn(3)
        await when { await feed.count() }.thenReturn(9)
        await feed.refresh(force: true)

        #expect(await feed.latest == 3)
        #expect(await feed.count() == 9)
        await verify { await feed.refresh(force: true) }.called(1)
        await verifyNever { await feed.refresh(force: false) }
    }

    @Test func throwingGetterThrowsStubbedError() {
        when { try feed.config }.thenThrow(ClientError.offline)
        #expect(throws: ClientError.offline) { try feed.config }
    }

    @Test func throwingGetterRecordsInsideVerifyInOrder() throws {
        when { try feed.config }.thenReturn("on")
        _ = try feed.config
        verifyInOrder { try feed.config }
    }

    @MainActor @Test func asyncMembersFromMainActor() async {
        await when { await feed.count() }.thenReturn(1)
        #expect(await feed.count() == 1)
    }

    @Test func genericValueReturningMember() {
        when(feed.first(in: [1, 2])).thenReturn(2)
        #expect(feed.first(in: [1, 2]) == 2)
        verify(feed.first(in: [1, 2])).called(1)
        verifyNever(feed.first(in: ["1", "2"]))
    }
}
