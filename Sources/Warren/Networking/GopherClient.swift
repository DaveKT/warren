import Foundation
import Network

enum GopherError: LocalizedError {
    case invalidAddress
    case connectionFailed(String)
    case timedOut
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "That doesn't look like a valid Gopher address."
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .timedOut: return "The server did not respond in time."
        case .responseTooLarge: return "The response was too large to load."
        }
    }
}

/// A one-shot RFC 1436 transaction: open a TCP connection, send the
/// selector (plus TAB-separated search query for type 7) terminated by
/// CRLF, then read until the server closes the connection.
enum GopherClient {
    static let maxResponseSize = 64 * 1024 * 1024 // 64 MB safety cap
    static let idleTimeout: TimeInterval = 30

    static func fetch(_ address: GopherAddress) async throws -> Data {
        let session = Session(address: address)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                session.start(continuation: continuation)
            }
        } onCancel: {
            session.cancel()
        }
    }
}

/// Owns one NWConnection for the duration of a fetch. All state is
/// confined to `queue`; the continuation is resumed exactly once.
private final class Session: @unchecked Sendable {
    private let address: GopherAddress
    private let queue = DispatchQueue(label: "warren.gopher.session")
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private var idleTimer: DispatchSourceTimer?
    private var offlineTimer: DispatchSourceTimer?

    /// How long to wait for the network to come up (the Mac just woke,
    /// Wi-Fi or a VPN is still joining) before giving up.
    private static let offlineGrace: TimeInterval = 3

    init(address: GopherAddress) {
        self.address = address
    }

    func start(continuation: CheckedContinuation<Data, Error>) {
        queue.async {
            self.continuation = continuation

            guard let port = NWEndpoint.Port(rawValue: self.address.port) else {
                self.finish(.failure(GopherError.invalidAddress))
                return
            }
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 15
            let params = NWParameters(tls: nil, tcp: tcp)
            let connection = NWConnection(
                host: NWEndpoint.Host(self.address.host), port: port, using: params)
            self.connection = connection

            connection.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.offlineTimer?.cancel()
                    self.offlineTimer = nil
                    self.sendRequest()
                case .waiting(let error):
                    // Refused, unreachable or an unknown host:
                    // Network.framework would keep retrying until the idle
                    // timeout, then report a misleading "did not respond".
                    // A browser should say what went wrong right away.
                    if self.connection?.currentPath?.status == .satisfied {
                        self.finish(.failure(GopherError.connectionFailed(self.describe(error))))
                    } else {
                        // No network at the moment. It may be about to
                        // come up, and the connection retries by itself
                        // when it does.
                        self.startOfflineTimer()
                    }
                case .failed(let error):
                    self.finish(.failure(GopherError.connectionFailed(self.describe(error))))
                case .cancelled:
                    self.finish(.failure(CancellationError()))
                default:
                    break
                }
            }
            self.resetIdleTimer()
            connection.start(queue: self.queue)
        }
    }

    /// Gives up, once, if the network hasn't come up within the grace period.
    private func startOfflineTimer() {
        guard offlineTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.offlineGrace)
        timer.setEventHandler { [weak self] in
            self?.finish(.failure(GopherError.connectionFailed(
                "You don't seem to be connected to the internet.")))
        }
        timer.resume()
        offlineTimer = timer
    }

    /// Plain words for the common reasons a connection can't be made.
    private func describe(_ error: NWError) -> String {
        let host = address.host
        switch error {
        case .posix(let code):
            switch code {
            case .ECONNREFUSED:
                return "\(host) refused the connection on port \(address.port)."
            case .EHOSTUNREACH, .EHOSTDOWN:
                return "\(host) can't be reached."
            case .ENETUNREACH, .ENETDOWN:
                return "You don't seem to be connected to the internet."
            case .ETIMEDOUT:
                return "\(host) took too long to answer."
            default:
                break
            }
        case .dns:
            return "Couldn't find a server named \(host)."
        default:
            break
        }
        return error.localizedDescription
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func sendRequest() {
        var request = address.selector
        if let query = address.searchQuery, !query.isEmpty {
            request += "\t\(query)"
        }
        request += "\r\n"
        connection?.send(content: Data(request.utf8), completion: .contentProcessed { [weak self] error in
            if let error {
                self?.finish(.failure(GopherError.connectionFailed(error.localizedDescription)))
            } else {
                self?.receiveNext()
            }
        })
    }

    private func receiveNext() {
        resetIdleTimer()
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > GopherClient.maxResponseSize {
                self.finish(.failure(GopherError.responseTooLarge))
                return
            }
            if isComplete {
                // Server closed the connection: transaction complete.
                self.finish(.success(self.buffer))
            } else if let error {
                // Some legacy servers slam the door instead of a clean FIN;
                // if we already have data, treat that as the response.
                if !self.buffer.isEmpty {
                    self.finish(.success(self.buffer))
                } else {
                    self.finish(.failure(GopherError.connectionFailed(error.localizedDescription)))
                }
            } else {
                self.receiveNext()
            }
        }
    }

    private func resetIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + GopherClient.idleTimeout)
        timer.setEventHandler { [weak self] in
            self?.finish(.failure(GopherError.timedOut))
        }
        timer.resume()
        idleTimer = timer
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        idleTimer?.cancel()
        idleTimer = nil
        offlineTimer?.cancel()
        offlineTimer = nil
        if let connection {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        continuation.resume(with: result)
    }
}
