import Foundation
import SwiftSyntax

struct ProtocolResolver {
    let index: SourceIndex

    /// Names of `Mock` members that a protocol requirement must not reuse.
    static let reservedNames: Set<String> = ["runtime"]
    /// Inherited protocols that add no requirements for the mock to implement.
    static let markerProtocols: Set<String> = ["Sendable", "AnyObject", "SendableMetatype"]

    func resolve(_ marker: Marker, testModule: String) -> Result<MockModel, GeneratorFailure> {
        guard let root = index.protocolDecl(named: marker.protocolName) else {
            return .failure(GeneratorFailure(diagnostics: [.error("\(marker.protocolName): protocol not found in the test target or its dependencies (protocols from binary frameworks are not supported)", at: marker)]))
        }
        var files: [String] = []
        let members: [Member]
        switch collect(root, marker: marker, files: &files) {
        case .success(let collected): members = collected
        case .failure(let failure): return .failure(failure)
        }

        let access = accessPrefix(of: root.node)
        var plain = Set(files.flatMap { index.imports(inFile: $0) }.filter { !$0.hasSuffix("SwiftMockito") })
        plain.insert("import SwiftMockito")
        var imports = plain.sorted()
        if root.input.module != testModule {
            imports.append(access.isEmpty ? "@testable import \(root.input.module)" : "import \(root.input.module)")
        }
        return .success(MockModel(
            protocolName: marker.protocolName,
            mockName: "Mock\(marker.protocolName)",
            access: access,
            globalActor: globalActor(of: root.node),
            module: root.input.module,
            imports: imports,
            members: disambiguateOverloads(members),
            marker: marker
        ))
    }

    /// The requirements of `decl` and its inherited protocols, inherited ones first.
    func members(of decl: IndexedDecl<ProtocolDeclSyntax>, marker: Marker) -> Result<[Member], GeneratorFailure> {
        var files: [String] = []
        return collect(decl, marker: marker, files: &files).map(disambiguateOverloads)
    }

    private func collect(_ root: IndexedDecl<ProtocolDeclSyntax>, marker: Marker, files: inout [String]) -> Result<[Member], GeneratorFailure> {
        var members: [Member] = []
        var diagnostics: [GeneratorDiagnostic] = []
        var visited: Set<String> = []

        func visit(_ decl: IndexedDecl<ProtocolDeclSyntax>) {
            let name = decl.node.name.text
            guard visited.insert(name).inserted else { return }
            files.append(decl.input.path)
            for inherited in decl.node.inheritanceClause?.inheritedTypes ?? [] {
                let parent = inherited.type.trimmedDescription
                if parent == "Actor" {
                    diagnostics.append(.error("\(name): Actor-constrained protocols are not supported", at: marker))
                } else if Self.markerProtocols.contains(parent) {
                    continue
                } else if let parentDecl = index.protocolDecl(named: parent) {
                    visit(parentDecl)
                } else {
                    diagnostics.append(.error("\(name): inherited protocol \(parent) not found in sources", at: marker))
                }
            }
            for item in decl.node.memberBlock.members {
                switch convert(item.decl, protocolName: name, marker: marker) {
                case .success(let member): members.append(member)
                case .failure(let diagnostic): diagnostics.append(diagnostic)
                }
            }
        }

        visit(root)
        return diagnostics.isEmpty ? .success(members) : .failure(GeneratorFailure(diagnostics: diagnostics))
    }

    private func convert(_ decl: DeclSyntax, protocolName: String, marker: Marker) -> Result<Member, GeneratorDiagnostic> {
        func unsupported(_ what: String) -> Result<Member, GeneratorDiagnostic> {
            .failure(.error("\(protocolName): \(what) are not supported", at: marker))
        }
        if let modifiers = decl.asProtocol(WithModifiersSyntax.self)?.modifiers,
           modifiers.contains(where: { $0.name.text == "static" || $0.name.text == "class" }) {
            return unsupported("static requirements")
        }
        if decl.is(InitializerDeclSyntax.self) { return unsupported("initializers") }
        if decl.is(AssociatedTypeDeclSyntax.self) { return unsupported("associated types") }
        if decl.trimmedDescription.range(of: #"\bSelf\b"#, options: .regularExpression) != nil {
            return unsupported("Self requirements")
        }

        if let function = decl.as(FunctionDeclSyntax.self) {
            let name = function.name.text
            let effects = function.signature.effectSpecifiers
            if effects?.throwsClause?.type != nil {
                return .failure(.error("\(protocolName).\(name): typed throws is not supported", at: marker))
            }
            if effects?.throwsClause?.throwsSpecifier.text == "rethrows" {
                return .failure(.error("\(protocolName).\(name): rethrows is not supported", at: marker))
            }
            if Self.reservedNames.contains(name) { return collision(protocolName, name, marker) }
            let returnType = function.signature.returnClause?.type.trimmedDescription
            return .success(.method(Method(
                name: name,
                identity: "",
                genericParameters: function.genericParameterClause?.parameters.map {
                    GenericParameter(name: $0.name.text, constraint: $0.inheritedType?.trimmedDescription)
                } ?? [],
                parameters: function.signature.parameterClause.parameters.enumerated().map { position, p in
                    parameter(label: p.firstName.text, secondName: p.secondName?.text, type: p.type, position: position)
                },
                returnType: (returnType == "Void" || returnType == "()") ? nil : returnType,
                isAsync: effects?.asyncSpecifier != nil,
                isThrowing: effects?.throwsClause != nil,
                genericWhereClause: function.genericWhereClause?.trimmedDescription
            )))
        }

        if let variable = decl.as(VariableDeclSyntax.self), let binding = variable.bindings.first,
           let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
           let type = binding.typeAnnotation?.type {
            if Self.reservedNames.contains(name) { return collision(protocolName, name, marker) }
            let accessors = accessorList(binding.accessorBlock)
            let getter = accessors.first { $0.accessorSpecifier.text == "get" }
            return .success(.property(Property(
                name: name,
                type: type.trimmedDescription,
                hasSetter: accessors.contains { $0.accessorSpecifier.text == "set" },
                getterAsync: getter?.effectSpecifiers?.asyncSpecifier != nil,
                getterThrows: getter?.effectSpecifiers?.throwsClause != nil
            )))
        }

        if let sub = decl.as(SubscriptDeclSyntax.self) {
            return .success(.subscriptMember(Subscript(
                // Subscript parameters have no external label unless the name is written twice.
                parameters: sub.parameterClause.parameters.enumerated().map { position, p in
                    parameter(label: p.secondName == nil ? "_" : p.firstName.text,
                              secondName: p.secondName?.text ?? p.firstName.text, type: p.type, position: position)
                },
                returnType: sub.returnClause.type.trimmedDescription,
                hasSetter: accessorList(sub.accessorBlock).contains { $0.accessorSpecifier.text == "set" }
            )))
        }

        return .failure(.error("\(protocolName): unsupported requirement `\(decl.trimmedDescription)`", at: marker))
    }

    private func accessorList(_ block: AccessorBlockSyntax?) -> AccessorDeclListSyntax {
        if case .accessors(let list)? = block?.accessors { return list }
        return []
    }

    private func collision(_ protocolName: String, _ member: String, _ marker: Marker) -> Result<Member, GeneratorDiagnostic> {
        .failure(.error("\(protocolName).\(member) collides with SwiftMockito's Mock.\(member)", at: marker))
    }

    private func parameter(label: String, secondName: String?, type: TypeSyntax, position: Int) -> Parameter {
        let internalName = secondName ?? label
        let resolved = resolveTypealias(type)
        return Parameter(
            label: label == "_" ? nil : label,
            name: internalName == "_" ? "arg\(position)" : internalName,
            type: type.trimmedDescription,
            isClosure: isClosure(resolved),
            isMetatype: resolved.is(MetatypeTypeSyntax.self),
            isTuple: (resolved.as(TupleTypeSyntax.self)?.elements.count ?? 0) > 1
        )
    }

    /// Follows typealiases declared in the sources, and strips attributes such as `@escaping`.
    private func resolveTypealias(_ type: TypeSyntax) -> TypeSyntax {
        var current = type
        for _ in 0..<8 {
            if let attributed = current.as(AttributedTypeSyntax.self) { current = attributed.baseType; continue }
            if let identifier = current.as(IdentifierTypeSyntax.self), identifier.genericArgumentClause == nil,
               let target = index.typealiasTarget(named: identifier.name.text) { current = target; continue }
            break
        }
        return current
    }

    private func isClosure(_ type: TypeSyntax) -> Bool {
        let base = resolveTypealias(type)
        if base.is(FunctionTypeSyntax.self) { return true }
        if let optional = base.as(OptionalTypeSyntax.self) { return isClosure(optional.wrappedType) }
        if let iuo = base.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return isClosure(iuo.wrappedType) }
        if let tuple = base.as(TupleTypeSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
            return isClosure(only.type)   // `(() -> Void)?` parses as Optional(Tuple(Function))
        }
        return false
    }

    /// `"public "` or `"package "` when the protocol is declared so, otherwise `""`.
    private func accessPrefix(of decl: ProtocolDeclSyntax) -> String {
        for modifier in decl.modifiers where ["public", "package"].contains(modifier.name.text) {
            return "\(modifier.name.text) "
        }
        return ""
    }

    private func globalActor(of decl: ProtocolDeclSyntax) -> String? {
        for case .attribute(let attribute) in decl.attributes {
            let name = attribute.attributeName.trimmedDescription
            if name.hasSuffix("Actor") { return name }
        }
        return nil
    }

    private func disambiguateOverloads(_ members: [Member]) -> [Member] {
        var counts: [String: Int] = [:]
        for case .method(let m) in members { counts[m.baseIdentity, default: 0] += 1 }
        return members.map { member in
            guard case .method(var m) = member else { return member }
            m.identity = counts[m.baseIdentity, default: 0] > 1 ? "\(m.baseIdentity) \(m.signature)" : m.baseIdentity
            return .method(m)
        }
    }
}
