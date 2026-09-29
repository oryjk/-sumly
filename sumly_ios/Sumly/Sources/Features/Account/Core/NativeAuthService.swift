import Foundation

protocol AuthServicing: Sendable {
    /// Returns the data member of the backend envelope; never logs credentials.
    func execute(_ request: AuthRequest) async throws -> Data
}
extension AuthServicing {
    func fetch<T: Decodable & Sendable>(_ type: T.Type, _ request: AuthRequest) async throws -> T {
        try AuthCoding.decode(type, from: await execute(request))
    }
}
struct NativeAuthService: AuthServicing {
    let baseURL: URL
    var session: URLSession = .shared

    static func makeRequest(_ request: AuthRequest, baseURL: URL) throws -> URLRequest {
        let local = ["localhost", "127.0.0.1", "::1"].contains(baseURL.host ?? "")
        guard baseURL.scheme == "https" || (baseURL.scheme == "http" && local),
              baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil else { throw AuthError.insecureURL }
        var result = URLRequest(url: baseURL.appendingPathComponent("app/auth/" + request.path))
        result.httpMethod = request.method
        result.timeoutInterval = 20
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        if request.method != "GET" {
            result.httpBody = try JSONSerialization.data(withJSONObject: request.fields)
            result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer = request.bearer { result.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        return result
    }
    static func unwrap(_ data: Data, status: Int) throws -> Data {
        guard data.count <= 1_048_576 else { throw AuthError.malformed }
        if status == 401 { throw AuthError.unauthorized }
        if status == 404 || status == 503 { throw AuthError.unavailable }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? Int else { throw AuthError.malformed }
        guard (200..<300).contains(status), code == 0 else {
            throw AuthError.server(status, String((object["message"] as? String ?? "").prefix(300)))
        }
        guard let payload = object["data"], !(payload is NSNull) else { return Data("{}".utf8) }
        guard JSONSerialization.isValidJSONObject(payload) else { throw AuthError.malformed }
        return try JSONSerialization.data(withJSONObject: payload)
    }
    func execute(_ request: AuthRequest) async throws -> Data {
        let urlRequest = try Self.makeRequest(request, baseURL: baseURL)
        do {
            // Stream with a hard cap so an oversized response cannot grow memory without bound.
            let (bytes, response) = try await session.bytes(for: urlRequest, delegate: NoAuthRedirects())
            guard let http = response as? HTTPURLResponse else { throw AuthError.malformed }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw AuthError.malformed }
                data.append(byte)
            }
            if request.path == "account", http.statusCode == 401 || http.statusCode == 403 { throw AuthError.reauthenticate }
            return try Self.unwrap(data, status: http.statusCode)
        } catch let error as AuthError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw AuthError.network }
    }
}
private final class NoAuthRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
