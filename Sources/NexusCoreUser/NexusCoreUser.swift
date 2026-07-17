import Foundation
#if canImport(UIKit)
import UIKit
#endif

public final class NexusCoreUser: @unchecked Sendable {
    public static let shared = NexusCoreUser()
    public static let version = "0.0.3"

    private var config: CoreUserConfig?
    private var storage: CoreUserStorage?
    private var api: CoreUserAPI?

    private init() {}

    public func initialize(config: CoreUserConfig, appGroupSuiteName: String? = nil, session: URLSession = .shared) {
        self.config = config
        self.storage = CoreUserStorage(suiteName: appGroupSuiteName, productId: config.productId)
        self.api = CoreUserAPI(config: config, session: session)
    }

    public func getSdkConfig() throws -> CoreUserConfig {
        guard let config else { throw CoreUserError.notInitialized }
        return config
    }

    public func getConfig() throws -> [String: Any] {
        try requireStorage().getLoginConfig()
    }

    public func getDeviceId() throws -> String {
        try requireStorage().getOrCreateDeviceId()
    }

    public func setLoginAttributionEnabled(_ enabled: Bool) throws {
        try requireStorage().setLoginAttributionEnabled(enabled)
    }

    public func isLoginAttributionEnabled() throws -> Bool {
        try requireStorage().isLoginAttributionEnabled()
    }

    public func silentLogin(loginType: LoginType = .guest) async throws -> SDKUser {
        let storage = try requireStorage()
        let api = try requireAPI()
        let deviceId = storage.getOrCreateDeviceId()
        let existingUid = storage.getUser()?.uid ?? ""
        let login = try await api.login(
            deviceId: deviceId,
            uid: existingUid,
            loginType: loginType,
            att: storage.isLoginAttributionEnabled() ? 1 : 0
        )
        let user = (try? await api.getUserInfo(uid: login.uid, deviceId: deviceId))
            ?? SDKUser(uid: login.uid, deviceId: deviceId, userInfoSynced: false)
        storage.saveLoginConfig(login.config)
        storage.saveUser(user)
        return user
    }

    public func silentLogin(loginType: LoginType = .guest, completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        Task {
            do { completion(.success(try await silentLogin(loginType: loginType))) }
            catch { completion(.failure(error)) }
        }
    }

    public func getCurrentUser() throws -> SDKUser? {
        try requireStorage().getUser()
    }

    public func fetchUserInfo() async throws -> SDKUser {
        let storage = try requireStorage()
        let current: SDKUser
        if let cached = try getCurrentUser() {
            current = cached
        } else {
            current = try await silentLogin()
        }
        let user = try await requireAPI().getUserInfo(uid: current.uid, deviceId: current.deviceId)
        storage.saveUser(user)
        return user
    }

    public func fetchUserInfo(completion: @escaping @Sendable (CoreUserResult<SDKUser>) -> Void) {
        Task {
            do { completion(.success(try await fetchUserInfo())) }
            catch { completion(.failure(error)) }
        }
    }

    public func bindEmail(_ email: String) async throws -> BindAccountResult {
        try await bindAccount(BindAccountParams(accountType: .email, email: email))
    }

    public func bindPhone(phonePrefix: String, phone: String) async throws -> BindAccountResult {
        try await bindAccount(BindAccountParams(accountType: .phone, phonePrefix: phonePrefix, phone: phone))
    }

    public func bindAccount(_ params: BindAccountParams) async throws -> BindAccountResult {
        let current: SDKUser
        if let cached = try getCurrentUser() {
            current = cached
        } else {
            current = try await silentLogin()
        }
        let result = try await requireAPI().bindAccount(uid: current.uid, deviceId: current.deviceId, params: params)
        var updated = current
        updated.uid = result.uid
        updated.userInfoSynced = true
        switch params.accountType {
        case .email:
            updated.email = result.accountValue
            updated.emailBound = result.bound
        case .phone:
            updated.phone = result.accountValue
            updated.phoneBound = result.bound
        }
        try requireStorage().saveUser(updated)
        return result
    }

    public func consumeChatCoins(cost: Double, remark: String? = nil) async throws -> ConsumeChatCoinsResult {
        guard cost > 0 else { throw CoreUserError.invalidConfig("cost must be greater than 0") }
        let current: SDKUser
        if let cached = try getCurrentUser() {
            current = cached
        } else {
            current = try await silentLogin()
        }
        return try await requireAPI().consumeChatCoins(uid: current.uid, cost: cost, remark: remark)
    }

    public func consumeChatCoins(
        cost: Double,
        remark: String? = nil,
        completion: @escaping @Sendable (CoreUserResult<ConsumeChatCoinsResult>) -> Void
    ) {
        Task {
            do { completion(.success(try await consumeChatCoins(cost: cost, remark: remark))) }
            catch { completion(.failure(error)) }
        }
    }

    #if canImport(UIKit)
    public func ensureEmailBound(
        presenting viewController: UIViewController,
        completion: @escaping @Sendable (BindEmailFlowResult) -> Void = { _ in }
    ) {
        Task {
            let user: SDKUser
            do {
                user = try await fetchUserInfo()
            } catch {
                await MainActor.run {
                    completion(BindEmailFlowResult(status: .userInfoFailed, error: error))
                }
                return
            }

            if user.emailBound {
                await MainActor.run {
                    completion(BindEmailFlowResult(status: .alreadyBound, user: user))
                }
                return
            }

            await MainActor.run {
                CoreUserEmailBindPresenter.show(
                    presenting: viewController,
                    initialEmail: user.email,
                    onCancel: {
                        completion(BindEmailFlowResult(status: .cancelled, user: user))
                    },
                    onSubmit: { [weak self] email in
                        guard let self else { return }
                        Task {
                            do {
                                let result = try await self.bindEmail(email)
                                let updated = try self.getCurrentUser()
                                await MainActor.run {
                                    completion(BindEmailFlowResult(status: .bound, user: updated, bindResult: result))
                                }
                            } catch {
                                await MainActor.run {
                                    completion(BindEmailFlowResult(status: .bindFailed, user: user, error: error))
                                }
                            }
                        }
                    }
                )
            }
        }
    }
    #endif

    public func getRelatedProducts(forceRefresh: Bool = false) async throws -> [RelatedProduct] {
        try await requireAPI().getRelatedProducts()
    }

    public func logout() throws {
        let storage = try requireStorage()
        storage.clearUser()
        storage.clearLoginConfig()
    }

    private func requireStorage() throws -> CoreUserStorage {
        guard let storage else { throw CoreUserError.notInitialized }
        return storage
    }

    private func requireAPI() throws -> CoreUserAPI {
        guard let api else { throw CoreUserError.notInitialized }
        return api
    }
}
