@testable import SwiftMockito

struct SampleError: Error, Equatable {}
struct Opaque {}

final class SampleMock: Mock, @unchecked Sendable {
    init(fileID: String = #fileID, filePath: StaticString = #filePath, line: UInt = #line, column: UInt = #column) {
        super.init(name: "SampleMock", site: CallSite(fileID: fileID, filePath: filePath, line: line, column: column))
    }

    func cached(id: String) -> String? {
        if let capture = Capture.current {
            capture.record(runtime, "cached(id:)", key: [arg(id)], args: id, returns: String?.self)
            return nil
        }
        return runtime.invoke("cached(id:)", key: [arg(id)], args: id)
    }

    nonisolated(nonsending) func fetch(id: String) async throws -> String {
        if let capture = Capture.current {
            capture.record(runtime, "fetch(id:)", key: [arg(id)], args: id, effects: [.async, .throwing], returns: String.self)
            if Capture.continuesAfterRecord { return "" }
            throw CaptureSignal()
        }
        return try await runtime.invokeThrowing("fetch(id:)", key: [arg(id)], args: id)
    }

    func save(_ value: String) throws {
        if let capture = Capture.current {
            capture.record(runtime, "save(_:)", key: [arg(value)], args: value, effects: .throwing)
            if Capture.continuesAfterRecord { return }
            throw CaptureSignal()
        }
        return try runtime.invokeThrowing("save(_:)", key: [arg(value)], args: value)
    }

    /// Generic return with no placeholder: always signals while recording.
    func decode<T>(_ type: T.Type) throws -> T {
        if let capture = Capture.current {
            capture.record(runtime, "decode(_:)", key: [arg(type: T.self), arg(type: type)], args: type, effects: .throwing, returns: T.self)
            throw CaptureSignal()
        }
        return try runtime.invokeThrowing("decode(_:)", key: [arg(type: T.self), arg(type: type)], args: type)
    }

    var token: String {
        get {
            if let capture = Capture.current {
                capture.record(runtime, "token", key: [], returns: String.self)
                return ""
            }
            return runtime.invoke("token", key: [])
        }
        set {
            if let capture = Capture.current {
                capture.record(runtime, "token=", key: [arg(newValue)], args: newValue)
                return
            }
            return runtime.invoke("token=", key: [arg(newValue)], args: newValue)
        }
    }

    func render(_ value: Opaque) {
        if let capture = Capture.current {
            capture.record(runtime, "render(_:)", key: [arg(value)], args: value)
            return
        }
        return runtime.invoke("render(_:)", key: [arg(value)], args: value)
    }
}
