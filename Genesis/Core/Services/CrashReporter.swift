import Foundation
import OSLog
import Sentry

/// Crash and error reporting through Sentry. Analytics stay minimal by design:
/// no performance tracing, no session replay and no personal data.
enum CrashReporter {
    private static let logger = Logger(subsystem: "com.7twenty8studio.genesis", category: "errors")

    static func start(configuration: AppConfiguration = .current) {
        guard let dsn = configuration.sentryDSN else {
            logger.info("Sentry DSN not configured; crash reporting is off.")
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.enableAutoPerformanceTracing = false
            #if DEBUG
            options.environment = "debug"
            #else
            options.environment = "production"
            #endif
        }
    }

    /// Records a non-fatal error. Never include Scripture notes or journal text.
    static func record(_ error: Error, context: String) {
        logger.error("\(context, privacy: .public): \(String(describing: error), privacy: .public)")
        SentrySDK.capture(error: error) { scope in
            scope.setTag(value: context, key: "context")
        }
    }
}
