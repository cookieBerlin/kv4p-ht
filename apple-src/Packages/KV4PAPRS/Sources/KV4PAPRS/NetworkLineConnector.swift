#if canImport(Network)
    import Foundation
    import Network
    import Synchronization

    /// TCP lines over Network.framework, ISO-8859-1 like java-aprs. Forwarding only, excluded from coverage
    /// (ADR-0011).
    public struct NetworkLineConnector: LineConnector {
        public init() {}

        public func connect(host: String, port: Int) async throws -> any LineConnection {
            guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
                throw NWError.posix(.EINVAL)
            }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            let queue = DispatchQueue(label: "kv4p.aprs-is")
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    let resumed = Mutex(false)
                    connection.stateUpdateHandler = { state in
                        let result: Result<Void, any Error>? =
                            switch state {
                            case .ready: .success(())
                            case .failed(let error), .waiting(let error): .failure(error)
                            case .cancelled: .failure(CancellationError())
                            default: nil
                            }
                        guard let result,
                            resumed.withLock({ resumed in
                                defer { resumed = true }; return !resumed
                            })
                        else { return }
                        continuation.resume(with: result)
                    }
                    connection.start(queue: queue)
                }
            } onCancel: {
                connection.cancel()
            }
            return NetworkLineConnection(connection)
        }
    }

    final class NetworkLineConnection: LineConnection {
        let lines: AsyncStream<String>
        private let connection: NWConnection

        init(_ connection: NWConnection) {
            self.connection = connection
            let (lines, continuation) = AsyncStream.makeStream(of: String.self)
            self.lines = lines
            connection.stateUpdateHandler = { state in
                if case .failed = state { continuation.finish() }
                if case .cancelled = state { continuation.finish() }
            }
            Self.receive(connection, buffer: [], into: continuation)
        }

        private static func receive(
            _ connection: NWConnection,
            buffer: [UInt8],
            into continuation: AsyncStream<String>.Continuation
        ) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                var buffer = buffer + (data.map { [UInt8]($0) } ?? [])
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline].filter { $0 != 0x0D }
                    continuation.yield(String(String.UnicodeScalarView(line.map { Unicode.Scalar($0) })))
                    buffer.removeSubrange(...newline)
                }
                if isComplete || error != nil {
                    continuation.finish()
                } else {
                    receive(connection, buffer: buffer, into: continuation)
                }
            }
        }

        func send(_ line: String) async throws {
            let bytes = Data((line + "\r\n").unicodeScalars.map { $0.value <= 0xFF ? UInt8($0.value) : 0x3F })
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                connection.send(
                    content: bytes,
                    completion: .contentProcessed { error in
                        continuation.resume(with: error.map { .failure($0) } ?? .success(()))
                    }
                )
            }
        }

        func close() {
            connection.cancel()
        }
    }
#endif
