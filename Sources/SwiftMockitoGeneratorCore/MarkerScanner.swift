import Foundation

/// Finds `@GenerateMock(A.self, B.self)` names with a text scan. The plugin uses it to
/// declare outputs before the generator runs; the generator re-parses with SwiftSyntax.
public enum MarkerScanner {
    public static func protocolNames(in text: String) -> [String] {
        var names: [String] = []
        var rest = text[...]
        while let start = rest.range(of: "@GenerateMock(") {
            guard let end = rest[start.upperBound...].firstIndex(of: ")") else { break }
            for part in rest[start.upperBound..<end].split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasSuffix(".self") { names.append(String(trimmed.dropLast(5))) }
            }
            rest = rest[end...]
        }
        return names
    }
}
