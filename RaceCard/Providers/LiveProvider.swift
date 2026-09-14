import Foundation
import Security
import MQTTNIO
import NIOSSL

struct Credentials: Codable, Sendable { var username: String; var password: String }
enum CredentialVault {
    static func read() throws -> Credentials? {
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Product.bundleID,kSecAttrAccount as String:"openf1",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw VaultError.status(status) }; return try JSONDecoder().decode(Credentials.self,from:data)
    }
    static func save(_ value: Credentials) throws {
        let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Product.bundleID,kSecAttrAccount as String:"openf1"]
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(q as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound { var insert = q; insert[kSecValueData as String] = data; insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly; let s = SecItemAdd(insert as CFDictionary,nil); guard s == errSecSuccess else { throw VaultError.status(s) } } else if status != errSecSuccess { throw VaultError.status(status) }
    }
    static func delete() throws { let s = SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Product.bundleID,kSecAttrAccount as String:"openf1"] as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw VaultError.status(s) } }
    enum VaultError: LocalizedError { case status(OSStatus); var errorDescription: String? { if case .status(let s) = self { return SecCopyErrorMessageString(s,nil) as String? ?? "Keychain error \(s)" }; return nil } }
}
actor TokenManager {
    var token: String?; var expiry = Date.distantPast
    let transport: URLSession
    let credentials: @Sendable () throws -> Credentials?
    init(transport: URLSession = .shared, credentials: @escaping @Sendable () throws -> Credentials? = { try CredentialVault.read() }) { self.transport = transport; self.credentials = credentials }
    func access(force: Bool = false, now: Date = Date()) async throws -> String {
        if !force, let token, expiry.timeIntervalSince(now) > 120 { return token }
        guard let c = try credentials(), !c.username.isEmpty, !c.password.isEmpty else { throw ProviderError.noCredentials }
        var request = URLRequest(url:URL(string:"https://api.openf1.org/token")!); request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        request.httpBody = "username=\(c.username.addingPercentEncoding(withAllowedCharacters:allowed)!)&password=\(c.password.addingPercentEncoding(withAllowedCharacters:allowed)!)".data(using:.utf8)
        let (data,response) = try await transport.data(for:request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { token = nil; throw ProviderError.liveAccess }
        let row = try JSONDecoder().decode([String:JSONValue].self,from:data)
        guard let value = row.s("access_token") else { throw ProviderError.invalidResponse }
        token = value; expiry = now.addingTimeInterval(row.n("expires_in") ?? 3600); return value
    }
    func refreshAfter() -> Double { max(1,expiry.timeIntervalSinceNow-120) }
    func invalidate() { token = nil; expiry = .distantPast }
}
struct LivePacket: Sendable { var endpoint: String; var data: Data; var received: Date }
protocol BrokerTransport: Sendable {
    func consume(token: String, topics: [String], receive: @escaping @Sendable (LivePacket) async -> Void, connected: @escaping @Sendable () async -> Void) async throws
}
struct MQTTTransport: BrokerTransport {
    var host = "mqtt.openf1.org"; var port = 8883
    func consume(token: String,topics: [String],receive: @escaping @Sendable (LivePacket) async -> Void,connected: @escaping @Sendable () async -> Void) async throws {
        let config = MQTTConnectionConfiguration(keepAliveInterval:.seconds(20),connectTimeout:.seconds(10),userName:"racecard",password:token,transport:.tcp(tls:.enable(.niossl(.makeClientConfiguration()),tlsServerName:host)))
        try await MQTTConnection.withConnection(address:.hostname(host,port:port),configuration:config,identifier:"racecard-\(UUID().uuidString)") { connection in
            try await connection.subscribe(to:topics.map { MQTTSubscribeInfo(topicFilter:"v1/\($0)",qos:.atLeastOnce) }) { subscription in
                await connected()
                for try await message in subscription {
                    try Task.checkCancellation(); var buffer = message.payload
                    if let bytes = buffer.readBytes(length:buffer.readableBytes) { await receive(.init(endpoint:String(message.topicName.split(separator:"/").last ?? ""),data:Data(bytes),received:Date())) }
                }
            }
        }
    }
}
actor OpenF1LiveProvider {
    let tokens: TokenManager; let broker: any BrokerTransport
    private var policy = ReconnectPolicy()
    init(tokens: TokenManager,broker: any BrokerTransport = MQTTTransport()) { self.tokens = tokens; self.broker = broker }
    func run(session: SessionState,telemetry: Bool,receive: @escaping @Sendable (LivePacket) async -> Void,status: @escaping @Sendable (Bool) async -> Void) async {
        policy.reset()
        var topics = ["sessions","drivers","position","intervals","laps","location","stints","pit","race_control","weather","overtakes","starting_grid","session_result"]
        if session.isRace { topics += ["championship_drivers","championship_teams"] }; if telemetry { topics.append("car_data") }
        while !Task.isCancelled {
            do {
                let token = try await tokens.access(); let refresh = await tokens.refreshAfter()
                try await withThrowingTaskGroup(of:Void.self) { group in
                    group.addTask { try await self.broker.consume(token:token,topics:topics,receive:receive,connected:{ await self.didConnect(); await status(true) }) }
                    group.addTask { try await Task.sleep(for:.seconds(refresh)); throw RefreshNeeded() }
                    defer { group.cancelAll() }; _ = try await group.next()
                }
                policy.reset()
            } catch is CancellationError { return }
            catch is RefreshNeeded { await status(false); await tokens.invalidate(); policy.reset() }
            catch { await status(false); await tokens.invalidate() }
            if Task.isCancelled { return }
            do { try await Task.sleep(for:.seconds(policy.nextDelay())) } catch { return }
        }
    }
    private func didConnect() { policy.reset() }
    private struct RefreshNeeded: Error {}
}
