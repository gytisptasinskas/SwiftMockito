public struct SourceInput: Sendable {
    public let path: String
    public let module: String
    public let text: String

    public init(path: String, module: String, text: String) {
        self.path = path
        self.module = module
        self.text = text
    }
}

struct Marker: Equatable {
    let protocolName: String
    let path: String
    let line: Int
    let column: Int
}

struct GenericParameter: Equatable {
    let name: String
    let constraint: String?
}

struct Parameter: Equatable {
    let label: String?        // external label; nil means `_` (or no label, for subscripts)
    let name: String          // internal name used in the body
    let type: String          // as written in the protocol
    let isClosure: Bool
    let isMetatype: Bool
    let isTuple: Bool
    let isVariadic: Bool
}

struct Method: Equatable {
    let name: String
    var identity: String
    let genericParameters: [GenericParameter]
    let parameters: [Parameter]
    let returnType: String?   // nil means Void
    let isAsync: Bool
    let isThrowing: Bool
    let genericWhereClause: String?

    var baseIdentity: String { "\(name)(\(parameters.map { "\($0.label ?? "_"):" }.joined()))" }
    var signature: String { "(\(parameters.map(\.type).joined(separator: ", "))) -> \(returnType ?? "Void")" }
}

struct Property: Equatable {
    let name: String
    let type: String
    let hasSetter: Bool
    let getterAsync: Bool
    let getterThrows: Bool
}

struct Subscript: Equatable {
    let parameters: [Parameter]
    let returnType: String
    let hasSetter: Bool

    var identity: String { "subscript(\(parameters.map { "\($0.label ?? "_"):" }.joined()))" }
}

enum Member: Equatable {
    case method(Method)
    case property(Property)
    case subscriptMember(Subscript)
}

struct MockModel {
    let protocolName: String
    let mockName: String
    let access: String        // "public ", "package " or "" (matches the protocol)
    let globalActor: String?
    let module: String
    let imports: [String]
    let members: [Member]
    let marker: Marker
}
