import Foundation
import PackagePlugin

@main
struct SwiftMockitoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let dependencies = target.recursiveTargetDependencies.compactMap { $0 as? SourceModuleTarget }
        // SwiftMockito and everything it depends on (macros, swift-syntax) hold no user protocols.
        let runtime = dependencies.first { $0.moduleName == "SwiftMockito" }
        let excluded = Set(([runtime].compactMap { $0 } + (runtime?.recursiveTargetDependencies ?? [])).map(\.id))
        let sources = dependencies
            .filter { !excluded.contains($0.id) }
            .flatMap { dependency in dependency.sourceFiles(withSuffix: "swift").map { (dependency.moduleName, $0.url) } }
        return try commands(
            tool: context.tool(named: "SwiftMockitoGenerator").url,
            workDirectory: context.pluginWorkDirectoryURL,
            testModule: target.moduleName,
            marked: target.sourceFiles(withSuffix: "swift").map(\.url),
            sources: sources
        )
    }
}

func commands(tool: URL, workDirectory: URL, testModule: String, marked: [URL],
              sources: [(module: String, url: URL)]) throws -> [Command] {
    let names = Set(try marked.flatMap { MarkerScanner.protocolNames(in: try String(contentsOf: $0, encoding: .utf8)) }).sorted()
    guard !names.isEmpty else { return [] }
    let output = workDirectory.appending(path: "GeneratedMocks")
    var arguments = ["generate", "--test-module", testModule, "--output", output.path]
    for url in marked { arguments += ["--marked", url.path] }
    for (module, url) in sources { arguments += ["--source", "\(module)=\(url.path)"] }
    for name in names { arguments += ["--expect", "Mock\(name).swift"] }
    return [.buildCommand(
        displayName: "SwiftMockito: generating \(names.count) mock(s) for \(testModule)",
        executable: tool,
        arguments: arguments,
        inputFiles: marked + sources.map(\.url),
        outputFiles: names.map { output.appending(path: "Mock\($0).swift") }
    )]
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftMockitoPlugin: XcodeBuildToolPlugin {
    /// The plugin searches the Swift files of the test target's transitive target dependencies for
    /// the protocol and its types. When the target declares no target dependencies (for example
    /// when it relies on a host application), it falls back to every other target in the project.
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        var searched = dependencyClosure(of: target)
        if searched.isEmpty {
            searched = context.xcodeProject.targets.filter { $0.id != target.id }
        }
        let sources = searched.flatMap { other in
            other.inputFiles.filter { $0.url.pathExtension == "swift" }.map { (moduleName(other), $0.url) }
        }
        return try commands(
            tool: context.tool(named: "SwiftMockitoGenerator").url,
            workDirectory: context.pluginWorkDirectoryURL,
            testModule: moduleName(target),
            marked: target.inputFiles.filter { $0.url.pathExtension == "swift" }.map(\.url),
            sources: sources
        )
    }

    /// Targets reachable through `.target` dependencies, excluding `target` itself and tolerating cycles.
    private func dependencyClosure(of target: XcodeTarget) -> [XcodeTarget] {
        var visited: Set<XcodeTarget.ID> = [target.id]
        var result: [XcodeTarget] = []
        var pending = [target]
        while let current = pending.popLast() {
            for dependency in current.dependencies {
                guard case .target(let next) = dependency, visited.insert(next.id).inserted else { continue }
                result.append(next)
                pending.append(next)
            }
        }
        return result
    }

    /// Xcode exposes no module name, so this mirrors the default `PRODUCT_MODULE_NAME` derived from the target name.
    private func moduleName(_ target: XcodeTarget) -> String {
        let name = String(target.displayName.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") ? $0 : "_" })
        return name.first?.isNumber == true ? "_" + name : name
    }
}
#endif
