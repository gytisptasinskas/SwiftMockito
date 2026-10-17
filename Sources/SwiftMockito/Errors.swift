import Foundation

/// A throwing member was called with arguments that no stub matches.
///
/// An unstubbed throwing member that returns a value throws this error to the code under
/// test. (A member that returns `Void` returns normally instead, and an unstubbed non-throwing
/// member that returns a value reports the same message and then traps.)
///
/// ```swift
/// @Test func missingStubOnThrowingMemberThrows() async {
///     await #expect(throws: MissingStubError.self) { try await client.fetch(id: "1") }
/// }
/// ```
public struct MissingStubError: Error, Sendable, CustomStringConvertible {
    /// The mock's name, such as `MockClient`.
    public let mock: String
    /// The member that was called, such as `fetch(id:)`.
    public let member: String
    /// The call's arguments, described with `String(reflecting:)`. Closure arguments are left out.
    public let arguments: [String]
    /// The arguments and location of each stub configured for this member.
    public let configuredStubs: [String]
    /// Where the mock was created.
    public let site: CallSite

    /// A multi-line message: the call, the configured stubs, and where the mock was created.
    public var description: String {
        var lines = ["No stub for \(mock).\(member) with arguments (\(arguments.joined(separator: ", ")))."]
        if configuredStubs.isEmpty {
            lines.append("No stubs configured for \(member).")
        } else {
            lines.append("Configured stubs for \(member):")
            lines += configuredStubs.map { "  \($0)" }
        }
        lines.append("Mock created at \(site).")
        return lines.joined(separator: "\n")
    }
}

/// A stub or verification used an argument that exact matching cannot compare.
///
/// Arguments must be `Equatable` or class instances. Stubbing or verifying a call with any
/// other argument type reports this error's ``description`` as a test failure at the `when` or
/// `verify` line, and installs or checks nothing. Real calls with such arguments still work.
///
/// ```swift
/// struct Point { let x: Int }   // not Equatable
/// verify(canvas.draw(Point(x: 1)))
/// // MockCanvas.draw(_:) argument 0 has type App.Point, which is neither Equatable nor a class; …
/// ```
public struct UnsupportedExactMatchingError: Error, Sendable, CustomStringConvertible {
    /// The qualified member, such as `MockCanvas.draw(_:)`.
    public let member: String
    /// The zero-based position of the argument among the matched arguments.
    public let position: Int
    /// The argument's type name.
    public let typeName: String

    /// Creates the error for argument `position` of `member`.
    ///
    /// - Parameters:
    ///   - member: The qualified member, such as `MockCanvas.draw(_:)`.
    ///   - position: The zero-based position of the argument.
    ///   - typeName: The argument's type name.
    public init(member: String, position: Int, typeName: String) {
        self.member = member
        self.position = position
        self.typeName = typeName
    }

    /// The failure message: the member, the argument position and its type.
    public var description: String {
        "\(member) argument \(position) has type \(typeName), which is neither Equatable nor a class; exact matching cannot compare it."
    }
}

/// Recording a non-throwing member needed a placeholder value that SwiftMockito cannot build.
///
/// While `when` or `verify` records a non-throwing member, the member returns a dummy of its
/// return type. If there is none, SwiftMockito reports this error's ``description`` as a test
/// failure **and then traps, which ends the whole test process**. Register a dummy first:
///
/// ```swift
/// provideDummy(CGSize(width: 1, height: 1))
/// when(view.size()).thenReturn(CGSize(width: 320, height: 480))
/// ```
public struct MissingDummyError: Error, Sendable, CustomStringConvertible {
    /// The return type that has no dummy.
    public let typeName: String
    /// The member being recorded, such as `MockView.size()`.
    public let member: String

    /// Creates the error for `member`, whose return type `typeName` has no dummy.
    ///
    /// - Parameters:
    ///   - typeName: The return type that has no dummy.
    ///   - member: The member being recorded.
    public init(typeName: String, member: String) {
        self.typeName = typeName
        self.member = member
    }

    /// The failure message, with a hint to call ``provideDummy(_:)``.
    public var description: String {
        "No dummy value for \(typeName), needed while recording \(member). Call provideDummy(_:) with a \(typeName) value before stubbing or verifying this member."
    }
}
