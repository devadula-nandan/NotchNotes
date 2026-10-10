import Foundation

// What was typed is an address if it looks like one (scheme, dotted host, localhost); otherwise a web search
public func destination(for text: String) -> URL? {
    if text.contains("://") { return URL(string: text) }
    let host = String(text.prefix { $0 != "/" && $0 != ":" && $0 != "?" })
    let looksLikeAddress = !text.contains(" ") && (host.contains(".") || host == "localhost")
    // Dev servers and devices on the local network rarely serve https
    let scheme = isLocal(host) ? "http" : "https"
    if looksLikeAddress, let url = URL(string: scheme + "://" + text) { return url }
    var search = URLComponents(string: "https://www.google.com/search")
    search?.queryItems = [URLQueryItem(name: "q", value: text)]
    return search?.url
}

// localhost, *.localhost, *.local and bare IPv4 addresses
private func isLocal(_ host: String) -> Bool {
    let h = host.lowercased()
    if h == "localhost" || h.hasSuffix(".localhost") || h.hasSuffix(".local") { return true }
    let parts = h.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
}
