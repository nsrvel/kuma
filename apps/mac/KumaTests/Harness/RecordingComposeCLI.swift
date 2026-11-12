import Foundation
import os
@testable import Kuma

/// Records compose CLI invocations for container runner tests.
public final class RecordingComposeCLI: ComposeCLIExecuting, @unchecked Sendable {
    public struct Invocation: Sendable {
        public let context: ComposeStackContext
        public let arguments: [String]
    }

    private let state = OSAllocatedUnfairLock<Invocation?>(initialState: nil)

    public nonisolated init() {}

    public nonisolated var lastInvocation: Invocation? {
        state.withLock { $0 }
    }

    public nonisolated func run(
        context: ComposeStackContext,
        arguments: [String],
        timeout: TimeInterval?
    ) async throws -> Int32 {
        state.withLock { $0 = Invocation(context: context, arguments: arguments) }
        return 0
    }
}
