import Foundation

/// Finds `@GenerateMock(A.self, B.self)` names, also spelled `@SwiftMockito.GenerateMock(…)`, with a
/// text scan. The plugin uses it to declare outputs before the generator runs; the generator re-parses
/// with SwiftSyntax. A match whose arguments are not all `Name.self` (prose such as "@GenerateMock( and a
/// list") is not a marker; scanning resumes right after the opening parenthesis. A trailing comma is fine.
public enum MarkerScanner {
    public static func protocolNames(in text: String) -> [String] {
        var names: [String] = []
        var rest = text[...]
        while let start = rest.range(of: "GenerateMock(") {
            let head = text[..<start.lowerBound]
            guard head.hasSuffix("@") || head.hasSuffix("@SwiftMockito."),
                  let end = rest[start.upperBound...].firstIndex(of: ")") else {
                rest = rest[start.upperBound...]
                continue
            }
            var parts = rest[start.upperBound..<end].split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count > 1, parts.last == "" { parts.removeLast() }
            let parsed = parts.map(typeName(fromSelfExpression:))
            if !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) {
                names += parsed.compactMap { $0 }
                rest = rest[end...]
            } else {
                rest = rest[start.upperBound...]
            }
        }
        return names
    }

    /// `Client.self` -> `Client`; nil unless the text is an identifier path followed by `.self`.
    private static func typeName(fromSelfExpression part: String) -> String? {
        guard part.hasSuffix(".self") else { return nil }
        let name = part.dropLast(5)
        guard let first = name.first, first == "_" || (first.isASCII && first.isLetter) else { return nil }
        let allowed = name.allSatisfy { $0 == "_" || $0 == "." || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return allowed ? String(name) : nil
    }
}
