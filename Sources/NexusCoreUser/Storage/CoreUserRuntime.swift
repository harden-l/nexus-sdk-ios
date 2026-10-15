import Foundation

final class CoreUserRuntime: @unchecked Sendable {
    let config: CoreUserConfig
    let storage: CoreUserStorage
    let api: CoreUserAPI
    private let lock = NSRecursiveLock()
    private var active = true
    private var revision = 0
    private var loginTask: (id: UUID, task: Task<SDKUser, Error>)?

    init(config: CoreUserConfig, suiteName: String?, session: URLSession) {
        self.config = config
        storage = CoreUserStorage(suiteName: suiteName, productId: config.productId, apiBaseUrl: config.apiBaseUrl)
        api = CoreUserAPI(config: config, session: session)
    }

    func locked<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try action()
    }

    func invalidate() {
        locked { active = false; revision += 1; loginTask?.task.cancel(); loginTask = nil }
    }

    func validSession() throws -> LoginSession? {
        try locked {
            guard active else { throw CoreUserError.sessionChanged }
            guard let session = try storage.getSession() else { return nil }
            guard session.isValid else { revision += 1; try storage.clearSession(); return nil }
            return session
        }
    }

    func user() throws -> SDKUser? {
        try locked {
            guard let session = try validSession() else { return nil }
            return storage.getUser().flatMap { $0.uid == session.uid ? $0 : nil }
                ?? SDKUser(uid: session.uid, deviceId: storage.getOrCreateDeviceId())
        }
    }

    func clear(resetLoginType: Bool) throws {
        try locked {
            guard active else { throw CoreUserError.sessionChanged }
            revision += 1
            loginTask?.task.cancel()
            loginTask = nil
            try storage.clearSession(resetLoginType: resetLoginType)
        }
    }

    func assertIdentity(_ session: LoginSession, expectedRevision: Int? = nil) throws {
        guard active, expectedRevision == nil || expectedRevision == revision,
              try validSession() == session else { throw CoreUserError.sessionChanged }
    }

    func login(type: LoginType, email: String? = nil, phonePrefix: String? = nil, phone: String? = nil, password: String? = nil) async throws -> SDKUser {
        let work: Task<SDKUser, Error> = try locked {
            guard active else { throw CoreUserError.sessionChanged }
            if type == .guest, let user = try user() { return Task { user } }
            if let loginTask {
                if type == .guest { return loginTask.task }
                throw CoreUserError.invalidConfig("A login is already in progress")
            }
            if type == .guest, storage.lastLoginType != .guest {
                throw CoreUserError.business(code: 401, message: "Please sign in again with email or phone", httpStatus: 200, traceId: nil)
            }
            let epoch = revision
            let id = UUID()
            let deviceId = storage.getOrCreateDeviceId()
            let task = Task { [self] () throws -> SDKUser in
                defer { locked { if loginTask?.id == id { loginTask = nil } } }
                let session = try await api.login(deviceId: deviceId, type: type, email: email, phonePrefix: phonePrefix, phone: phone, password: password)
                let persistedRevision = try locked {
                    guard active, epoch == revision else { throw CoreUserError.sessionChanged }
                    try storage.saveSession(session)
                    revision += 1
                    storage.saveUser(SDKUser(uid: session.uid, deviceId: deviceId))
                    return revision
                }
                do { return try await fetchUser(session: session, expectedRevision: persistedRevision) }
                catch {
                    return try locked {
                        try assertIdentity(session, expectedRevision: persistedRevision)
                        // A profile transport failure does not erase a successful authentication.
                        return storage.getUser() ?? SDKUser(uid: session.uid, deviceId: deviceId)
                    }
                }
            }
            loginTask = (id, task)
            return task
        }
        return try await work.value
    }

    func authenticatedSession() async throws -> LoginSession {
        if let session = try validSession() { return session }
        _ = try await login(type: .guest)
        guard let session = try validSession() else { throw CoreUserError.sessionChanged }
        return session
    }

    func captureContext() async throws -> CoreUserSessionContext {
        _ = try await authenticatedSession()
        return try locked {
            guard let session = try validSession() else { throw CoreUserError.sessionChanged }
            return CoreUserSessionContext(runtime: self, session: session, revision: revision)
        }
    }

    func request(path: String, body: Data = Data("{}".utf8), session: LoginSession, expectedRevision: Int? = nil) async throws -> Data {
        let epoch = try locked { try assertIdentity(session, expectedRevision: expectedRevision); return revision }
        do {
            let data = try await api.post(path: path, body: body, token: session.token)
            try locked { try assertIdentity(session, expectedRevision: epoch) }
            return data
        } catch {
            if (error as? CoreUserError)?.businessCode == 401 {
                try locked {
                    if active, revision == epoch, try storage.getSession() == session {
                        revision += 1
                        try storage.clearSession()
                    }
                }
            }
            throw error
        }
    }

    func fetchUser(session: LoginSession, expectedRevision: Int? = nil) async throws -> SDKUser {
        let epoch = try locked { try assertIdentity(session, expectedRevision: expectedRevision); return revision }
        let data = try await request(path: "/api/v1/account/info", session: session, expectedRevision: epoch)
        let user = try CoreUserAPI.user(data, deviceId: locked { storage.getOrCreateDeviceId() })
        try locked {
            try assertIdentity(session, expectedRevision: epoch)
            guard user.uid == session.uid else { throw CoreUserError.invalidResponse("User identity mismatch") }
            storage.saveUser(user)
        }
        return user
    }
}
