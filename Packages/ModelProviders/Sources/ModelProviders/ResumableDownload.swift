import Foundation

/// Streams to a sibling partial file, retaining bytes across cancellation and process restarts.
/// The caller supplies a revision identity from its catalog and serializes writes per destination.
public final class ResumableDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public static let resumedBytes = ProgressUserInfoKey("ModelProviders.resumedBytes")
    private let destination: URL
    private let partial: URL
    private let identityFile: URL
    private let expectedBytes: Int64?
    private let progress: Progress
    private let origin: URL
    private let lock = NSLock()
    private var cancelled = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var handle: FileHandle?
    private var failure: Error?
    private var offset: Int64 = 0
    private var received: Int64 = 0

    private init(destination: URL, expectedBytes: Int64?, progress: Progress, origin: URL) {
        self.destination = destination; self.expectedBytes = expectedBytes; self.progress = progress; self.origin = origin
        partial = destination.appendingPathExtension("partial")
        identityFile = destination.appendingPathExtension("partial-id")
    }

    public static func download(_ request: URLRequest, to destination: URL, identity: String?,
                                expectedBytes: Int64?, progress: Progress) async throws {
        guard let url = request.url else { throw Inference.Failure("Missing download URL") }
        let transfer = ResumableDownload(destination: destination, expectedBytes: expectedBytes, progress: progress, origin: url)
        var request = request
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let saved = try? String(contentsOf: transfer.identityFile, encoding: .utf8)
        // No stable revision: restarting is safer than combining different versions.
        let fingerprint = identity.map { url.absoluteString + "\n" + $0 + "\n" + String(expectedBytes ?? -1) }
        if fingerprint == nil || saved != fingerprint {
            try? FileManager.default.removeItem(at: transfer.partial)
        }
        if let fingerprint { try Data(fingerprint.utf8).write(to: transfer.identityFile, options: .atomic) }
        transfer.offset = Int64((try? transfer.partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if let expectedBytes, transfer.offset >= expectedBytes {
            try? FileManager.default.removeItem(at: transfer.partial); transfer.offset = 0
        }
        if transfer.offset > 0 { request.setValue("bytes=\(transfer.offset)-", forHTTPHeaderField: "Range") }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        progress.totalUnitCount = expectedBytes ?? 0
        progress.completedUnitCount = transfer.offset
        progress.setUserInfoObject(transfer.offset, forKey: resumedBytes)
        let finalRequest = request
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                transfer.lock.withLock {
                    if transfer.cancelled { continuation.resume(throwing: CancellationError()); return }
                    transfer.continuation = continuation
                    let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.timeoutIntervalForRequest = 60
                    configuration.timeoutIntervalForResource = 7 * 24 * 3600
                    transfer.session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: queue)
                    transfer.task = transfer.session!.dataTask(with: finalRequest)
                    transfer.task!.resume()
                }
            }
        } onCancel: {
            transfer.lock.withLock { transfer.cancelled = true; transfer.task?.cancel() }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        if origin.scheme == "https" && next.url?.scheme != "https" {
            failure = Inference.Failure("The model source redirected to an insecure address."); completionHandler(nil); return
        }
        if next.url?.host != origin.host || next.url?.port != origin.port || next.url?.scheme != origin.scheme {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 206 else {
                throw Inference.Failure("Model download failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check the source and access token.")
            }
            if http.statusCode == 206 {
                guard offset > 0, let range = http.value(forHTTPHeaderField: "Content-Range"),
                      range.hasPrefix("bytes \(offset)-") else { throw Inference.Failure("The model source returned an invalid download range.") }
            } else {
                offset = 0; progress.setUserInfoObject(Int64(0), forKey: Self.resumedBytes)
            }
            if !FileManager.default.fileExists(atPath: partial.path) { FileManager.default.createFile(atPath: partial.path, contents: nil) }
            handle = try FileHandle(forWritingTo: partial)
            if offset == 0 { try handle!.truncate(atOffset: 0) }
            try handle!.seek(toOffset: UInt64(offset))
            received = offset; progress.completedUnitCount = offset
            completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard let handle else { throw Inference.Failure("Cannot write model download") }
            try handle.write(contentsOf: data); received += Int64(data.count)
            if let expectedBytes, received > expectedBytes { throw Inference.Failure("The download exceeds its advertised size.") }
            progress.completedUnitCount = received
        } catch { failure = error; dataTask.cancel() }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var result: Result<Void, Error>
        do {
            try handle?.close(); handle = nil
            if let failure { throw failure }
            if lock.withLock({ cancelled }) { throw CancellationError() }
            if let error { throw error }
            if let expectedBytes, received != expectedBytes { throw Inference.Failure("The download is incomplete. Resume to finish it.") }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: partial)
            } else { try FileManager.default.moveItem(at: partial, to: destination) }
            try? FileManager.default.removeItem(at: identityFile)
            result = .success(())
        } catch { result = .failure(error) }
        let callback = lock.withLock {
            let callback = continuation; continuation = nil; self.task = nil
            return callback
        }
        session.finishTasksAndInvalidate(); self.session = nil
        callback?.resume(with: result)
    }
}
