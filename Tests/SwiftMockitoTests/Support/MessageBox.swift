import Foundation

/// Lock-protected message collector for `Reporter.$sink` in tests.
final class MessageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ message: String) { lock.withLock { storage.append(message) } }
    var messages: [String] { lock.withLock { storage } }
}
