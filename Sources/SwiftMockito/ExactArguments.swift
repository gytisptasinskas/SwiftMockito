import Foundation

/// An immutable, exact-only encoding of generated member arguments.
public struct ExactArguments: @unchecked Sendable, Equatable {
    private let encodedValues: [EquatableValue]

    /// Encodes arguments using their concrete `Equatable` conformance.
    ///
    /// Generated code can call this dynamically so unsupported values produce a
    /// member-specific error when a caller configures or verifies the member.
    public init(_ values: [Any], for invocation: Invocation) throws {
        encodedValues = try values.enumerated().map { index, value in
            guard let equatableValue = value as? any Equatable else {
                throw UnsupportedExactMatchingError(
                    member: invocation.member,
                    position: index,
                    typeName: String(reflecting: type(of: value))
                )
            }

            return _openExistential(equatableValue, do: makeEquatableValue)
        }
    }

    static func values(from arguments: ExactArguments?) -> [Any] {
        arguments?.encodedValues.map(\.value) ?? []
    }

    public static func == (lhs: ExactArguments, rhs: ExactArguments) -> Bool {
        guard lhs.encodedValues.count == rhs.encodedValues.count else {
            return false
        }

        return zip(lhs.encodedValues, rhs.encodedValues).allSatisfy { $0.isEqual(to: $1) }
    }
}

private struct EquatableValue: @unchecked Sendable {
    let value: Any
    private let compare: (Any) -> Bool

    init<Value: Equatable>(_ value: Value) {
        self.value = value
        compare = { other in
            guard let other = other as? Value else {
                return false
            }
            return value == other
        }
    }

    func isEqual(to other: EquatableValue) -> Bool {
        compare(other.value)
    }
}

private func makeEquatableValue<Value: Equatable>(_ value: Value) -> EquatableValue {
    EquatableValue(value)
}
