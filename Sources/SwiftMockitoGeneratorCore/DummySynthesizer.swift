import SwiftParser
import SwiftSyntax

final class DummySynthesizer {
    let index: SourceIndex
    let model: MockModel
    let testModule: String
    private(set) var helpers: [String] = []
    private(set) var warnings: [GeneratorDiagnostic] = []

    /// Why a type has no dummy. Stored with cached results so a type built silently for a
    /// throwing member still warns when a non-throwing member asks for it later.
    private struct Issue: Hashable {
        let type: String
        let reason: String?   // nil: the type is a generic parameter of the member
    }

    /// The outcome of building one type's dummy: the `fallback:` expression and what is missing.
    private struct Built {
        var reference: String?
        var issues: [Issue] = []
    }

    private var cache: [String: Built] = [:]
    private var inProgress: [String] = []
    private var sawRecursion = false

    init(index: SourceIndex, model: MockModel, testModule: String) {
        self.index = index
        self.model = model
        self.testModule = testModule
    }

    /// The `fallback:` argument for a type the runtime has no built-in for, or nil.
    /// `warn: false` is used for throwing members' placeholders: no dummy there only
    /// matters inside `verifyInOrder`, which reports it at runtime.
    func fallback(for type: String, member: String, genericNames: Set<String>, warn: Bool = true) -> String? {
        let t = type.trimmingCharacters(in: .whitespaces)
        let built = build(t, genericNames: genericNames, key: member)
        if warn {
            for issue in built.issues {
                let diagnostic = GeneratorDiagnostic.warning(message(for: issue, member: member), at: model.marker)
                if !warnings.contains(diagnostic) { warnings.append(diagnostic) }
            }
        }
        return built.reference
    }

    private func message(for issue: Issue, member: String) -> String {
        guard let reason = issue.reason else {
            return "\(member): cannot build a dummy for generic return type \(issue.type); call provideDummy(_:) for each concrete \(issue.type) you stub"
        }
        return "\(member): cannot build a dummy \(issue.type) (\(reason)); call provideDummy(_:) with a \(issue.type) before stubbing or verifying it"
    }

    private func build(_ t: String, genericNames: Set<String>, key: String) -> Built {
        if BuiltIns.covers(t) { return Built() }
        let probe = parseType(t)
        if let probe, let function = functionType(probe) {
            let parameters = Array(repeating: "_", count: function.parameters.count).joined(separator: ", ")
            let signature = parameters.isEmpty ? "" : "\(parameters) in "
            return Built(reference: "{ { \(signature)fatalError(\"SwiftMockito: dummy closure must not be called\") } }")
        }
        if genericNames.contains(t) { return Built(issues: [Issue(type: t, reason: nil)]) }
        if let probe {
            if let tuple = probe.as(TupleTypeSyntax.self), tuple.elements.count > 1 {
                return buildTuple(tuple, genericNames: genericNames, key: key)
            }
            if let identifier = probe.as(IdentifierTypeSyntax.self), identifier.name.text == "Result",
               let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 2,
               let success = arguments.first {
                return buildResult(success: success.with(\.trailingComma, nil).trimmedDescription,
                                   genericNames: genericNames, key: key)
            }
        }
        return buildDeclared(t)
    }

    // MARK: Tuples and Result

    /// `{ (e0, e1, …) }`, with each element resolved as its own member `<key>.<i>`.
    private func buildTuple(_ tuple: TupleTypeSyntax, genericNames: Set<String>, key: String) -> Built {
        var issues: [Issue] = []
        var elements: [String] = []
        for (position, element) in tuple.elements.enumerated() {
            let type = element.type.trimmedDescription
            let built = build(type, genericNames: genericNames, key: key)
            issues += built.issues
            elements.append(resolveExpression(type, key: "\(key).\(position)", fallback: built.reference))
        }
        return Built(reference: "{ (\(elements.joined(separator: ", "))) }", issues: issues)
    }

    /// `{ .success(<s>) }`: the success type's dummy, called directly when a helper builds it.
    private func buildResult(success: String, genericNames: Set<String>, key: String) -> Built {
        let built = build(success, genericNames: genericNames, key: key)
        let value = if let reference = built.reference, reference.hasPrefix("Self._dummy") {
            "\(reference)()"
        } else {
            resolveExpression(success, key: "\(key).success", fallback: built.reference)
        }
        return Built(reference: "{ .success(\(value)) }", issues: built.issues)
    }

    // MARK: Declared types

    private func buildDeclared(_ t: String) -> Built {
        let name = t.hasPrefix("any ") ? String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces) : t
        guard let declaration = index.typeDecl(named: name), t == name || isProtocol(declaration) else {
            return missing(t, "not declared in sources")
        }
        if let cached = cache[name] { return cached }
        if inProgress.contains(name) {
            sawRecursion = true
            return Built()
        }

        let outermost = inProgress.isEmpty
        let snapshot = (helpers: helpers.count, cache: cache)
        sawRecursion = outermost ? false : sawRecursion
        inProgress.append(name)
        var built = buildDeclaration(declaration, name: name)
        inProgress.removeLast()

        if outermost && sawRecursion {
            // Nothing built for this request is usable; forget it all.
            sawRecursion = false
            helpers.removeSubrange(snapshot.helpers...)
            cache = snapshot.cache
            built = missing(t, "recursive type")
        }
        cache[name] = built
        return built
    }

    private func isProtocol(_ declaration: IndexedType) -> Bool {
        if case .protocolDecl = declaration { return true }
        return false
    }

    private func missing(_ type: String, _ reason: String) -> Built {
        Built(issues: [Issue(type: type, reason: reason)])
    }

    private func buildDeclaration(_ declaration: IndexedType, name: String) -> Built {
        switch declaration {
        case .protocolDecl(let decl): buildProtocol(decl, name: name)
        case .structDecl(let decl): buildStruct(decl, name: name)
        case .enumDecl(let decl): buildEnum(decl.node, name: name)
        case .classDecl(let decl): buildClass(decl, name: name)
        }
    }

    /// Reserves the helper's place in `helpers` now, so helpers appear in the order they were
    /// requested even though the ones it needs finish first. Returns the fill-in function.
    private func reserveHelper() -> (String) -> Void {
        let slot = helpers.count
        helpers.append("")
        return { [self] text in helpers[slot] = text }
    }

    private func helperName(_ name: String) -> String { "_dummy\(name)" }

    private func buildStruct(_ declaration: IndexedDecl<StructDeclSyntax>, name: String) -> Built {
        let decl = declaration.node
        let reach = reach(of: declaration.input.module)
        let initializers = decl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        if initializers.isEmpty {
            // The memberwise initializer is internal, and private when a private property needs a value.
            if !reach.internal { return missing(name, reach.reason) }
            if decl.memberBlock.members.contains(where: { hasInaccessibleStoredProperty($0.decl) }) {
                return missing(name, "no accessible initializer")
            }
            return construct(name, arguments: storedProperties(decl).map {
                (label: $0.name, type: $0.type, key: "\(name).\($0.name)")
            })
        }
        guard let chosen = accessibleInitializer(initializers, reach: reach) else {
            return missing(name, reach.internal ? "no accessible initializer" : reach.reason)
        }
        return construct(name, arguments: initializerArguments(chosen, name: name))
    }

    private enum InitializerChoice {
        case arguments([(label: String?, type: String, key: String)])
        case failure(String)
    }

    private func buildClass(_ declaration: IndexedDecl<ClassDeclSyntax>, name: String) -> Built {
        switch classInitializer(declaration, name: name, depth: 0) {
        case .arguments(let arguments): construct(name, arguments: arguments)
        case .failure(let reason): missing(name, reason)
        }
    }

    /// The initializer call for `name`, a class or a subclass of it. A class that declares no
    /// initializer inherits its superclass's designated ones, so the choice recurses up the chain.
    private func classInitializer(_ declaration: IndexedDecl<ClassDeclSyntax>, name: String, depth: Int) -> InitializerChoice {
        let decl = declaration.node
        let reach = reach(of: declaration.input.module)
        let initializers = decl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        if !initializers.isEmpty {
            guard let chosen = accessibleInitializer(initializers, reach: reach) else {
                return .failure(reach.internal ? "no accessible initializer" : reach.reason)
            }
            return .arguments(initializerArguments(chosen, name: name))
        }
        let needsValue = decl.memberBlock.members.contains { item in
            guard let variable = item.decl.as(VariableDeclSyntax.self),
                  !variable.modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" })
            else { return false }
            return variable.bindings.contains { binding in
                guard isStored(binding), binding.initializer == nil else { return false }
                let isOptionalVar = variable.bindingSpecifier.text == "var"
                    && binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true
                return !isOptionalVar
            }
        }
        if needsValue { return .failure("no accessible initializer") }
        if let first = decl.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription,
           !Self.protocolsNeverSuperclass.contains(first) {
            switch index.typeDecl(named: first) {
            case .classDecl(let superclass)?:
                // A superclass chain this deep is a cycle.
                return depth < 16 ? classInitializer(superclass, name: name, depth: depth + 1) : .failure("no accessible initializer")
            case .protocolDecl?:
                break
            default:
                return .failure("superclass \(first) not declared in sources")
            }
        }
        // The implicit `init()` is internal.
        return reach.internal ? .arguments([]) : .failure(reach.reason)
    }

    /// Standard protocols a class may list first; none of them can be a superclass.
    private static let protocolsNeverSuperclass: Set<String> = [
        "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable", "Sendable", "Identifiable",
        "CustomStringConvertible", "CustomDebugStringConvertible", "Error", "ObservableObject", "AnyObject",
        "RawRepresentable", "CaseIterable",
    ]

    /// Whether the generated mock can call a module's `internal` initializers. That holds for the test
    /// module and for modules the mock imports with `@testable` (the resolver does that for non-public
    /// protocols, and keeps a protocol file's own `@testable` imports). Otherwise only `public` ones
    /// (`package` ones when the protocol is `package`) work.
    private func reach(of module: String) -> (internal: Bool, allowed: [String], reason: String) {
        let canTestable = module == testModule
            || model.imports.contains { $0.contains("@testable") && $0.hasSuffix("import \(module)") }
        return (canTestable, model.access == "package " ? ["public", "open", "package"] : ["public", "open"],
                "no initializer accessible from \(testModule)")
    }

    private func buildEnum(_ decl: EnumDeclSyntax, name: String) -> Built {
        let first = decl.memberBlock.members.lazy
            .compactMap { $0.decl.as(EnumCaseDeclSyntax.self)?.elements.first }.first
        guard let first else { return missing(name, "enum has no cases") }
        let caseName = first.name.trimmedDescription
        let parameters = first.parameterClause?.parameters ?? []
        var arguments: [(label: String?, type: String, key: String)] = []
        for (position, parameter) in parameters.enumerated() {
            let label = parameter.firstName.map { $0.text == "_" ? nil : $0.text } ?? nil
            arguments.append((label, parameter.type.trimmedDescription, "\(name).\(first.name.text).\(label ?? String(position))"))
        }
        return construct(name, arguments: arguments) { rendered in
            rendered.isEmpty ? ".\(caseName)" : ".\(caseName)(\(rendered.joined(separator: ", ")))"
        }
    }

    /// `private static func _dummyT() -> T { T(<arguments>) }`, or the `call` built from the rendered arguments.
    private func construct(_ name: String, arguments: [(label: String?, type: String, key: String)],
                           call: (([String]) -> String)? = nil) -> Built {
        let setter = reserveHelper()
        var issues: [Issue] = []
        let rendered = arguments.map { argument -> String in
            let expression = argumentExpression(argument.type, key: argument.key, issues: &issues)
            return argument.label.map { "\($0): \(expression)" } ?? expression
        }
        let body = call?(rendered) ?? "\(name)(\(rendered.joined(separator: ", ")))"
        setter("private static func \(helperName(name))() -> \(name) {\n    \(body)\n}")
        return Built(reference: "Self.\(helperName(name))", issues: issues)
    }

    /// `Dummies.resolve(T.self, for: "key"[, fallback: …])` for one initializer argument.
    private func argumentExpression(_ type: String, key: String, issues: inout [Issue]) -> String {
        let built = build(type, genericNames: [], key: key)
        issues += built.issues
        return resolveExpression(type, key: key, fallback: built.reference)
    }

    private func resolveExpression(_ type: String, key: String, fallback: String?) -> String {
        "Dummies.resolve(\(metatype(type)), for: \"\(key)\"\(fallback.map { ", fallback: \($0)" } ?? ""))"
    }

    // MARK: Initializers

    /// The non-failable, non-throwing, non-private initializer with the fewest parameters. Where the
    /// module's internals are out of reach, only explicitly public ones qualify.
    private func accessibleInitializer(_ initializers: [InitializerDeclSyntax],
                                       reach: (internal: Bool, allowed: [String], reason: String)) -> InitializerDeclSyntax? {
        initializers.filter { initializer in
            let access = initializer.modifiers.filter { $0.detail == nil }.map(\.name.text)
            return initializer.optionalMark == nil
                && initializer.signature.effectSpecifiers == nil
                && !access.contains { $0 == "private" || $0 == "fileprivate" }
                && (reach.internal || access.contains { reach.allowed.contains($0) })
        }.min { $0.signature.parameterClause.parameters.count < $1.signature.parameterClause.parameters.count }
    }

    /// The arguments to call `initializer` with. Variadic parameters are left out.
    private func initializerArguments(_ initializer: InitializerDeclSyntax, name: String) -> [(label: String?, type: String, key: String)] {
        var arguments: [(label: String?, type: String, key: String)] = []
        for (position, parameter) in initializer.signature.parameterClause.parameters.enumerated() where parameter.ellipsis == nil {
            let label = parameter.firstName.text == "_" ? nil : parameter.firstName.text
            var type = parameter.type.trimmedDescription
            if type.hasPrefix("@escaping ") { type = String(type.dropFirst("@escaping ".count)) }
            arguments.append((label, type, "\(name).init.\(label ?? parameter.secondName?.text ?? String(position))"))
        }
        return arguments
    }

    /// A private stored property with no default makes the memberwise initializer private.
    private func hasInaccessibleStoredProperty(_ declaration: DeclSyntax) -> Bool {
        guard let variable = declaration.as(VariableDeclSyntax.self),
              !variable.modifiers.contains(where: { $0.name.text == "static" }),
              variable.modifiers.contains(where: { ["private", "fileprivate"].contains($0.name.text) && $0.detail == nil })
        else { return false }
        return variable.bindings.contains { binding in
            guard isStored(binding), binding.initializer == nil else { return false }
            let isOptionalVar = variable.bindingSpecifier.text == "var"
                && binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) == true
            return !isOptionalVar
        }
    }

    /// A binding with no getter: observers (`willSet`, `didSet`) keep a property stored.
    private func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let block = binding.accessorBlock else { return true }
        guard case .accessors(let accessors) = block.accessors else { return false }
        return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
    }

    // MARK: Protocols

    /// `_dummyP()` plus a nested `_DummyP` class that traps on every requirement.
    private func buildProtocol(_ decl: IndexedDecl<ProtocolDeclSyntax>, name: String) -> Built {
        let members: [Member]
        switch ProtocolResolver(index: index).members(of: decl, marker: model.marker) {
        case .success(let resolved): members = resolved
        case .failure: return missing("any \(name)", "protocol has unsupported requirements")
        }
        func trap(_ identity: String) -> String {
            "fatalError(\"SwiftMockito: dummy \(name).\(identity) must not be called\")"
        }
        var lines: [String] = []
        for member in members {
            switch member {
            case .method(let m):
                lines.append("    func \(methodSignature(m)) { \(trap(m.identity)) }")
            case .property(let p):
                let effects = (p.getterAsync ? " async" : "") + (p.getterThrows ? " throws" : "")
                let accessors = p.hasSetter || !effects.isEmpty
                    ? "get\(effects) { \(trap(p.name)) }" + (p.hasSetter ? " set { \(trap(p.name)) }" : "")
                    : trap(p.name)
                lines.append("    var \(p.name): \(p.type) { \(accessors) }")
            case .subscriptMember(let s):
                let params = s.parameters.map { declaration($0, subscriptStyle: true) }.joined(separator: ", ")
                let accessors = s.hasSetter ? "get { \(trap(s.identity)) } set { \(trap(s.identity)) }" : trap(s.identity)
                lines.append("    subscript(\(params)) -> \(s.returnType) { \(accessors) }")
            }
        }
        let className = "_Dummy\(name)"
        helpers.append("private static func \(helperName(name))() -> any \(name) {\n    \(className)()\n}")
        helpers.append(("private final class \(className): \(name), @unchecked Sendable {" + (lines.isEmpty ? "" : "\n" + lines.joined(separator: "\n")) + "\n}"))
        return Built(reference: "Self.\(helperName(name))")
    }

    // MARK: Parsing

    /// The type `type` spells. Parsed as a typealias, because SwiftSyntaxBuilder is not a dependency.
    private func parseType(_ type: String) -> TypeSyntax? {
        let tree = Parser.parse(source: "typealias Probe = \(type)")
        return tree.statements.first?.item.as(TypeAliasDeclSyntax.self)?.initializer.value
    }

    /// The function type `type` spells, ignoring parentheses and attributes, or nil.
    private func functionType(_ type: TypeSyntax) -> FunctionTypeSyntax? {
        var current = type
        for _ in 0..<8 {
            if let attributed = current.as(AttributedTypeSyntax.self) {
                current = attributed.baseType
            } else if let tuple = current.as(TupleTypeSyntax.self), tuple.elements.count == 1,
                      let only = tuple.elements.first, only.firstName == nil {
                current = only.type
            } else {
                break
            }
        }
        return current.as(FunctionTypeSyntax.self)
    }

    /// Stored properties that the memberwise initializer takes, in declaration order. Properties with
    /// observers are stored; ones with a default are optional arguments and left out. In `var a, b: Int`
    /// a binding without a type takes the type of the next binding that has one.
    func storedProperties(_ decl: StructDeclSyntax) -> [(name: String, type: String)] {
        var result: [(name: String, type: String)] = []
        for variable in decl.memberBlock.members.compactMap({ $0.decl.as(VariableDeclSyntax.self) })
        where !variable.modifiers.contains(where: { $0.name.text == "static" }) {
            var nextType: String?
            var entries: [(name: String, type: String)] = []
            for binding in variable.bindings.reversed() {
                if let type = binding.typeAnnotation?.type.trimmedDescription { nextType = type }
                guard isStored(binding), binding.initializer == nil,
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let type = nextType else { continue }
                entries.append((name, type))
            }
            result += entries.reversed()
        }
        return result
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
