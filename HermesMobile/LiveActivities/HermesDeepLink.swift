import Foundation

enum HermesDeepLink {
    static var scheme: String {
        Bundle.main.object(forInfoDictionaryKey: "HermesURLScheme") as? String
            ?? "hermes-agent"
    }

    static let sessionHost = "session"

    /// Host for the parameter-less "open the New Chat composer" deep link used by the
    /// New Chat App Intent (issue #337). Mirrors the share extension's host-based routing
    /// so the intent can reuse `ContentView.handleOpenURL` rather than inventing a new path.
    static let newChatHost = "new-chat"

    /// `hermes-agent://new-chat` (scheme follows the active build, e.g. `-branch`).
    static var newChatURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatHost
        return components.url
    }

    static func isNewChatURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == newChatHost
    }

    /// Host for "open the New Chat composer *and* auto-start voice dictation", used by the
    /// "New Chat with Voice" App Intent (issue #338). A distinct host from `newChatHost`
    /// so the two intents never alias each other — `isNewChatURL` and `isNewChatVoiceURL`
    /// are mutually exclusive.
    static let newChatVoiceHost = "new-chat-voice"

    /// `hermes-agent://new-chat-voice` (scheme follows the active build, e.g. `-branch`).
    static var newChatVoiceURL: URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatVoiceHost
        return components.url
    }

    static func isNewChatVoiceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == newChatVoiceHost
    }

    /// Host for "open the New Chat composer pinned to a specific profile", used by the
    /// "New Chat in <Profile>" App Intent (issue #339). A distinct host from the other
    /// new-chat hosts so the three intents never alias; the profile name rides as a query
    /// item (like `sessionURL`'s `id`) rather than in the host, so it can carry spaces and
    /// non-ASCII safely via percent-encoding.
    static let newChatInProfileHost = "new-chat-profile"

    /// Query-item name carrying the profile's server name.
    static let profileQueryItem = "profile"

    /// `hermes-agent://new-chat-profile?profile=<name>` (scheme follows the active build).
    /// Returns nil for a blank profile name so callers can pass it straight through.
    static func newChatInProfileURL(profileName: String) -> URL? {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = newChatInProfileHost
        components.queryItems = [URLQueryItem(name: profileQueryItem, value: trimmed)]
        return components.url
    }

    static func isNewChatInProfileURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
            && url.host?.lowercased() == newChatInProfileHost
    }

    /// Extracts the profile name from a "New Chat in <Profile>" URL, or nil when the URL is a
    /// different kind or carries no (non-blank) profile.
    static func profileName(fromNewChatInProfile url: URL) -> String? {
        guard isNewChatInProfileURL(url) else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let raw = components?.queryItems?.first(where: { $0.name == profileQueryItem })?.value
        else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Query item carrying the server a session link was rendered for, so the
    /// app can drop links that point at a server other than the now-active one
    /// (sweep MED #3).
    static let serverQueryItem = "server"

    /// Longest session ID the app will build or parse a link for. Server IDs
    /// are short opaque tokens (12-char hex upstream); anything longer can't
    /// name a real session.
    private static let maxSessionIDLength = 128

    /// `hermes-agent://session?id=<id>` — no server item, so the link opens
    /// against whichever server is active (Live Activity taps, in-app links).
    static func sessionURL(sessionID: String) -> URL? {
        sessionURL(sessionID: sessionID, serverURL: nil)
    }

    /// `hermes-agent://session?id=<id>&server=<server>` — the `server` item
    /// lets the app verify the link still targets the active server before
    /// opening it (widget snapshot rows). Both values ride percent-encoded.
    static func sessionURL(sessionID: String, serverURL: URL?) -> URL? {
        guard let sessionID = normalizedSessionID(sessionID) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = sessionHost
        var queryItems = [URLQueryItem(name: "id", value: sessionID)]
        if let serverURL {
            queryItems.append(URLQueryItem(name: serverQueryItem, value: serverURL.absoluteString))
        }
        components.queryItems = queryItems
        return components.url
    }

    /// The server a session link was rendered for, or nil when the link carries
    /// no (usable) `server` item.
    static func serverURL(from url: URL) -> URL? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == sessionHost
        else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let rawValue = components?.queryItems?.first(where: { $0.name == serverQueryItem })?.value else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let serverURL = URL(string: trimmed),
              serverURL.scheme == "https" || serverURL.scheme == "http",
              serverURL.host != nil
        else { return nil }
        return serverURL
    }

    /// Whether the link carries a `server` query item at all — even an
    /// unusable one. A present-but-unparseable item can't be validated, so
    /// callers must drop the link rather than open it unvalidated.
    static func carriesServerItem(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == sessionHost
        else {
            return false
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.contains { $0.name == serverQueryItem } ?? false
    }

    static func sessionID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == sessionHost
        else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let id = components?.queryItems?.first(where: { item in
            item.name == "id" || item.name == "session_id"
        })?.value {
            return normalizedSessionID(id)
        }

        let pathID = url.pathComponents
            .filter { $0 != "/" }
            .first
        return normalizedSessionID(pathID)
    }

    /// Session IDs are server-generated opaque tokens. An ID carrying
    /// whitespace, control characters, or path separators can't name a real
    /// session, so it's dropped instead of resolved into a wrong-session
    /// lookup (sweep LOW #18).
    private static func normalizedSessionID(_ rawValue: String?) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              trimmed.count <= maxSessionIDLength,
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !trimmed.contains("/"),
              !trimmed.contains("\\")
        else {
            return nil
        }
        return trimmed
    }
}
