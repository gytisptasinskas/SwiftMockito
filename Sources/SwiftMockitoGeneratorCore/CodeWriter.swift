struct CodeWriter {
    private(set) var output = ""
    private var level = 0

    mutating func line(_ text: String = "") {
        output += text.isEmpty ? "\n" : String(repeating: "    ", count: level) + text + "\n"
    }

    mutating func lines(_ text: String) {
        text.split(separator: "\n", omittingEmptySubsequences: false).forEach { line(String($0)) }
    }

    /// `binding` names the closure parameter: `opener { binding in`.
    mutating func block(_ opener: String, binding: String? = nil, _ body: (inout CodeWriter) -> Void) {
        line(opener + " {" + (binding.map { " \($0) in" } ?? ""))
        level += 1
        body(&self)
        level -= 1
        line("}")
    }
}
