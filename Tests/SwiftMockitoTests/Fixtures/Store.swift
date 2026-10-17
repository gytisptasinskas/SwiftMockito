import Foundation

struct Profile: Equatable {
    let user: User
    let tags: [String]
    var score: Double
}

enum Status: Equatable {
    case active(since: Date)
    case inactive
}

final class Session {
    let id: UUID
    init(id: UUID) { self.id = id }
}

protocol Logger {
    var level: Int { get }
    func log(_ message: String)
}

protocol Store {
    func profile() -> Profile
    func status() -> Status
    func session() -> Session
    func logger() -> any Logger
    func pair() -> (Int, String)
    func result() -> Result<Profile, Error>
}
