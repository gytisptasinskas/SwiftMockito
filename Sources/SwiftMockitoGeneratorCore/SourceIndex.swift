import SwiftParser
import SwiftSyntax

struct IndexedDecl<Node: SyntaxProtocol> {
    let node: Node
    let input: SourceInput
}

enum IndexedType {
    case structDecl(IndexedDecl<StructDeclSyntax>)
    case enumDecl(IndexedDecl<EnumDeclSyntax>)
    case classDecl(IndexedDecl<ClassDeclSyntax>)
    case protocolDecl(IndexedDecl<ProtocolDeclSyntax>)
    case typealiasDecl(IndexedDecl<TypeAliasDeclSyntax>)
}

/// The declaration a top-level name refers to.
enum Lookup<Value> {
    case missing
    case found(Value)
    /// Declared in several modules, none of them the test module (whose own declarations shadow imported ones).
    case ambiguous(modules: [String])

    var value: Value? {
        if case .found(let value) = self { return value }
        return nil
    }

    /// The error message for an ambiguous lookup of `name`, or nil.
    func ambiguity(_ name: String) -> String? {
        guard case .ambiguous(let modules) = self else { return nil }
        return "\(name) is declared in more than one module (\(modules.joined(separator: ", "))); rename one of them"
    }
}

final class SourceIndex {
    private var trees: [(input: SourceInput, tree: SourceFileSyntax)] = []
    /// Every top-level declaration of a name, keyed by module. Within one module the last one wins.
    private var declarations: [String: [String: IndexedType]] = [:]
    private let testModule: String?

    init(_ inputs: [SourceInput], testModule: String? = nil) {
        self.testModule = testModule
        for input in inputs {
            let tree = Parser.parse(source: input.text)
            trees.append((input, tree))
            // Top-level declarations only; nested types are out of scope for v1.
            for item in tree.statements {
                guard let decl = item.item.as(DeclSyntax.self) else { continue }
                let entry: (name: String, type: IndexedType)? =
                    if let p = decl.as(ProtocolDeclSyntax.self) {
                        (p.name.text, .protocolDecl(IndexedDecl(node: p, input: input)))
                    } else if let s = decl.as(StructDeclSyntax.self) {
                        (s.name.text, .structDecl(IndexedDecl(node: s, input: input)))
                    } else if let e = decl.as(EnumDeclSyntax.self) {
                        (e.name.text, .enumDecl(IndexedDecl(node: e, input: input)))
                    } else if let c = decl.as(ClassDeclSyntax.self) {
                        (c.name.text, .classDecl(IndexedDecl(node: c, input: input)))
                    } else if let t = decl.as(TypeAliasDeclSyntax.self) {
                        (t.name.text, .typealiasDecl(IndexedDecl(node: t, input: input)))
                    } else {
                        nil
                    }
                if let entry { declarations[entry.name, default: [:]][input.module] = entry.type }
            }
        }
    }

    func markers(in paths: Set<String>) -> [Marker] {
        var result: [Marker] = []
        for (input, tree) in trees where paths.contains(input.path) {
            let converter = SourceLocationConverter(fileName: input.path, tree: tree)
            let visitor = MarkerVisitor(viewMode: .sourceAccurate)
            visitor.walk(tree)
            for attribute in visitor.attributes {
                let location = attribute.startLocation(converter: converter)
                for name in markedTypeNames(attribute) {
                    result.append(Marker(protocolName: name, path: input.path, line: location.line, column: location.column))
                }
            }
        }
        return result
    }

    /// The declaration of `name`, preferring the test module's own.
    func typeDecl(named name: String) -> Lookup<IndexedType> {
        lookup(name) { $0 }
    }

    /// Like `typeDecl(named:)`, but only protocols count.
    func protocolDecl(named name: String) -> Lookup<IndexedDecl<ProtocolDeclSyntax>> {
        lookup(name) { if case .protocolDecl(let decl) = $0 { decl } else { nil } }
    }

    /// Like `typeDecl(named:)`, but only typealiases count, and the result is the aliased type.
    func typealiasTarget(named name: String) -> Lookup<TypeSyntax> {
        lookup(name) { if case .typealiasDecl(let decl) = $0 { decl.node.initializer.value } else { nil } }
    }

    /// The test module's declaration of `name` when it has one, since it shadows imported ones;
    /// otherwise the only module's declaration that `match` accepts.
    private func lookup<Value>(_ name: String, _ match: (IndexedType) -> Value?) -> Lookup<Value> {
        guard let byModule = declarations[name] else { return .missing }
        if let testModule, let own = byModule[testModule] { return match(own).map { .found($0) } ?? .missing }
        let matching = byModule.compactMap { module, type in match(type).map { (module, $0) } }
        switch matching.count {
        case 0: return .missing
        case 1: return .found(matching[0].1)
        default: return .ambiguous(modules: matching.map(\.0).sorted())
        }
    }

    func imports(inFile path: String) -> [String] {
        guard let tree = trees.first(where: { $0.input.path == path })?.tree else { return [] }
        return tree.statements.compactMap { $0.item.as(ImportDeclSyntax.self)?.trimmedDescription }
    }

    private func markedTypeNames(_ attribute: AttributeSyntax) -> [String] {
        guard case .argumentList(let arguments)? = attribute.arguments else { return [] }
        return arguments.compactMap { argument in
            guard let access = argument.expression.as(MemberAccessExprSyntax.self),
                  access.declName.baseName.text == "self",
                  let base = access.base else { return nil }
            return base.trimmedDescription
        }
    }
}

private final class MarkerVisitor: SyntaxVisitor {
    var attributes: [AttributeSyntax] = []

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        if ["GenerateMock", "SwiftMockito.GenerateMock"].contains(node.attributeName.trimmedDescription) {
            attributes.append(node)
        }
        return .skipChildren
    }
}
