import Foundation

struct Observed {
    var count: Int { didSet {} }
    var label: String { willSet {} }
}

struct Pair {
    var a, b: Int
}

struct Defaults {
    let fixed: Int = 1
    var flexible: Int = 2
    var name: String
}

enum Payload {
    case value(Int, String)
    case named(id: Int)
}

class BaseBox {
    let x: Int
    init(x: Int) { self.x = x }
}

final class SubBox: BaseBox {}

protocol Shapes {
    func observed() -> Observed
    func pair() -> Pair
    func defaults() -> Defaults
    func payload() -> Payload
    func subBox() -> SubBox
}
