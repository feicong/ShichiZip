import Cocoa

enum ArchiveOperationRunner {
    @MainActor
    static func runSynchronously<T>(operationTitle: String,
                                    initialFileName: String? = nil,
                                    parentWindow: NSWindow? = nil,
                                    deferredDisplay: Bool = false,
                                    work: @escaping (SZOperationSession) throws -> T) throws -> T {
        let coordinator = ArchiveOperationCoordinator(operationTitle: operationTitle,
                                                     initialFileName: initialFileName,
                                                     parentWindow: parentWindow,
                                                     deferredDisplay: deferredDisplay)
        coordinator.start()

        var result: Result<T, Error>?
        let session = coordinator.session
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let value = try work(session)
                DispatchQueue.main.async {
                    result = .success(value)
                }
            } catch {
                DispatchQueue.main.async {
                    result = .failure(error)
                }
            }
        }

        while result == nil {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        coordinator.finish()
        return try result!.get()
    }

    @MainActor
    static func run<T>(operationTitle: String,
                       initialFileName: String? = nil,
                       parentWindow: NSWindow? = nil,
                       deferredDisplay: Bool = false,
                       work: @escaping (SZOperationSession) throws -> T) async throws -> T {
        let coordinator = ArchiveOperationCoordinator(operationTitle: operationTitle,
                                                     initialFileName: initialFileName,
                                                     parentWindow: parentWindow,
                                                     deferredDisplay: deferredDisplay)
        coordinator.start()
        defer { coordinator.finish() }

        return try await withCheckedThrowingContinuation { continuation in
            let session = coordinator.session
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try work(session)
                    DispatchQueue.main.async {
                        continuation.resume(returning: result)
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}
