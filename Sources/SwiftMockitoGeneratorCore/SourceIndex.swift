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
}

final class SourceIndex {
    private var trees: [(input: SourceInput, tree: SourceFileSyntax)] = []
    private var protocols: [String: IndexedDecl<ProtocolDeclSyntax>] = [:]
    private var types: [String: IndexedType] = [:]
    private var typealiases: [String: TypeSyntax] = [:]

    init(_ inputs: [SourceInput]) {
        for input in inputs {
            let tree = Parser.parse(source: input.text)
            trees.append((input, tree))
            // Top-level declarations only; nested types are out of scope for v1.
            for item in tree.statements {
                guard let decl = item.item.as(DeclSyntax.self) else { continue }
                if let p = decl.as(ProtocolDeclSyntax.self) {
                    let indexed = IndexedDecl(node: p, input: input)
                    protocols[p.name.text] = indexed
                    types[p.name.text] = .protocolDecl(indexed)
                } else if let s = decl.as(StructDeclSyntax.self) {
                    types[s.name.text] = .structDecl(IndexedDecl(node: s, input: input))
                } else if let e = decl.as(EnumDeclSyntax.self) {
                    types[e.name.text] = .enumDecl(IndexedDecl(node: e, input: input))
                } else if let c = decl.as(ClassDeclSyntax.self) {
                    types[c.name.text] = .classDecl(IndexedDecl(node: c, input: input))
                } else if let t = decl.as(TypeAliasDeclSyntax.self) {
                    typealiases[t.name.text] = t.initializer.value
                }
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

    func protocolDecl(named name: String) -> IndexedDecl<ProtocolDeclSyntax>? { protocols[name] }
    func typeDecl(named name: String) -> IndexedType? { types[name] }
    func typealiasTarget(named name: String) -> TypeSyntax? { typealiases[name] }

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
        if node.attributeName.trimmedDescription == "GenerateMock" { attributes.append(node) }
        return .skipChildren
    }
}
