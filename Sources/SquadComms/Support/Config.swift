import Foundation

/// External service configuration. Values are injected at build time via
/// xcconfig / CI environment so nothing sensitive is committed to the repo.
enum Config {
    private static func value(_ key: String) -> String {
        if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
        if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty { return v }
        return ""
    }

    static var liveKitURL: String { value("LIVEKIT_URL") }
    static var supabaseURL: URL? { URL(string: value("SUPABASE_URL")) }
    static var supabaseAnonKey: String { value("SUPABASE_ANON_KEY") }
    static var sentryDSN: String { value("SENTRY_DSN") }
    static var posthogKey: String { value("POSTHOG_API_KEY") }
    static var posthogHost: String {
        let h = value("POSTHOG_HOST")
        return h.isEmpty ? "https://us.i.posthog.com" : h
    }
    static var isConfigured: Bool { !liveKitURL.isEmpty && supabaseURL != nil }
}
