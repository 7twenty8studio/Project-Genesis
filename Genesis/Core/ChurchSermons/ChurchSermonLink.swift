import Foundation

/// A sermon's one link (VRS-18): https://versely.7twenty8studio.com/s/<slug>,
/// which opens Versely where it's installed (a Universal Link, the
/// Associated Domains entitlement) and the guest web page everywhere else.
/// versely://sermon/<slug> is the web page's "Open in Versely".
enum ChurchSermonLink {
    /// The Versely web app's host. Links and QR codes always use it exactly
    /// (Universal Links don't follow redirects).
    static let host = "versely.7twenty8studio.com"

    /// Ten lowercase letters and digits (`genesis_new_sermon_slug`).
    static func isSlug(_ text: String) -> Bool {
        text.count == 10 && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
    }

    /// The link people share.
    static func url(slug: String) -> URL {
        URL(string: "https://\(host)/s/\(slug)")!
    }

    /// Church Studio on the web, opened on this church (for its owner and
    /// moderators). Not a Universal Link (only /s/* is), so it opens Safari.
    static func studio(church: UUID) -> URL {
        URL(string: "https://\(host)/studio?church=\(church.uuidString.lowercased())")!
    }

    /// The slug a link opens, or nil for any other address.
    static func slug(in url: URL) -> String? {
        let parts = url.pathComponents.filter { $0 != "/" }
        let slug: String?
        switch url.scheme?.lowercased() {
        case "https":
            guard url.host()?.lowercased() == host, parts.count == 2, parts[0] == "s" else { return nil }
            slug = parts[1]
        case GenesisLink.scheme:
            guard url.host()?.lowercased() == "sermon", parts.count == 1 else { return nil }
            slug = parts[0]
        default:
            slug = nil
        }
        return slug.flatMap { isSlug($0) ? $0 : nil }
    }
}
