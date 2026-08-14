import Foundation
import Sentry
import PostHog

enum Telemetry {
    static func start() {
        if !Config.sentryDSN.isEmpty {
            SentrySDK.start { options in
                options.dsn = Config.sentryDSN
                options.tracesSampleRate = 0.2
            }
        }
        if !Config.posthogKey.isEmpty {
            let cfg = PostHogConfig(apiKey: Config.posthogKey, host: Config.posthogHost)
            PostHogSDK.shared.setup(cfg)
        }
    }

    static func event(_ name: String, _ props: [String: Any] = [:]) {
        guard !Config.posthogKey.isEmpty else { return }
        PostHogSDK.shared.capture(name, properties: props)
    }
}
