import Foundation
import Network

/// Shares only the quota snapshot. Listens exclusively on IPv4 loopback, never the LAN.
final class LocalQuotaServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "local.codexquota.snapshot")
    private let lock = NSLock()
    private var payload = Data()
    private var listener: NWListener?
    func update(_ snapshot: Snapshot) {
        let data = (try? JSONEncoder().encode(snapshot)) ?? Data("{}".utf8)
        lock.lock(); payload = data; lock.unlock()
    }
    func start(snapshot: Snapshot) throws {
        update(snapshot)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 52743)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var request = accumulated
            if let data { request.append(data) }
            guard request.count <= 8192 else { connection.cancel(); return }
            guard let text = String(data: request, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete { connection.cancel() } else { self.receive(connection, accumulated: request) }
                return
            }
            let ok = text.hasPrefix("GET /quota HTTP/1.")
            self.lock.lock(); let body = ok ? self.payload : Data(); self.lock.unlock()
            var response = Data("HTTP/1.1 \(ok ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
