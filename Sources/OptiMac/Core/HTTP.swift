import Foundation

/// Requêtes internet compatibles macOS 11 (URLSession « async » n'existe qu'à partir de macOS 12).
enum HTTP {
    static func data(for request: URLRequest) async -> (Data?, Int, Error?) {
        await withCheckedContinuation { cont in
            URLSession.shared.dataTask(with: request) { data, resp, err in
                cont.resume(returning: (data, (resp as? HTTPURLResponse)?.statusCode ?? 0, err))
            }.resume()
        }
    }

    static func data(from url: URL, timeout: TimeInterval = 20) async -> (Data?, Int, Error?) {
        var r = URLRequest(url: url)
        r.timeoutInterval = timeout
        r.setValue("OptiMac/\(SystemInfo.appVersion)", forHTTPHeaderField: "User-Agent")
        return await data(for: r)
    }

    static func json(from url: URL) async -> [String: Any]? {
        let (d, code, _) = await data(from: url)
        guard code == 200, let d else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
