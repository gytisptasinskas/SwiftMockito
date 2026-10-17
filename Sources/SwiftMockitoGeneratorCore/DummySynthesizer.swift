import SwiftSyntax

final class DummySynthesizer {
    let index: SourceIndex
    let model: MockModel
    private(set) var helpers: [String] = []
    private(set) var warnings: [GeneratorDiagnostic] = []
    private var built: Set<String> = []

    init(index: SourceIndex, model: MockModel) {
        self.index = index
        self.model = model
    }

    /// The `fallback:` argument for a type the runtime has no built-in for, or nil.
    /// `warn: false` is used for throwing members' placeholders: no dummy there only
    /// matters inside `verifyInOrder`, which reports it at runtime.
    func fallback(for type: String, member: String, genericNames: Set<String>, warn: Bool = true) -> String? {
        let t = type.trimmingCharacters(in: .whitespaces)
        if BuiltIns.covers(t) { return nil }
        guard case .structDecl(let decl)? = index.typeDecl(named: t) else { return nil }
        let name = "_dummy\(t)"
        if built.insert(name).inserted {
            let arguments = storedProperties(decl.node).map {
                "\($0.name): Dummies.resolve(\(metatype($0.type)), for: \"\(t).\($0.name)\")"
            }
            helpers.append("private static func \(name)() -> \(t) {\n    \(t)(\(arguments.joined(separator: ", ")))\n}")
        }
        return "Self.\(name)"
    }

    /// Stored properties that the memberwise initializer takes, in declaration order.
    func storedProperties(_ decl: StructDeclSyntax) -> [(name: String, type: String)] {
        decl.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }
            .filter { variable in !variable.modifiers.contains { $0.name.text == "static" } }
            .flatMap { variable in
                variable.bindings.compactMap { binding -> (name: String, type: String)? in
                    guard binding.accessorBlock == nil,
                          !(variable.bindingSpecifier.text == "let" && binding.initializer != nil),
                          let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                          let type = binding.typeAnnotation?.type.trimmedDescription else { return nil }
                    return (name, type)
                }
            }
    }
}

enum BuiltIns {
    static let names: Set<String> = [
        "Void", "()", "Bool", "String", "Character", "Data", "Date", "URL", "UUID",
        "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float",
    ]

    /// Types the runtime's `Dummies.lookup` builds. `Result` is excluded on purpose:
    /// its dummy needs the success type's dummy, which the synthesizer handles.
    static func covers(_ type: String) -> Bool {
        if names.contains(type) || type.hasSuffix("?") || type.hasSuffix("!") { return true }
        return ["[", "Array<", "Set<", "Dictionary<", "Optional<"].contains { type.hasPrefix($0) }
    }
}
