import SwiftUI

/// The app's few animation curves and transitions, so motion feels the same
/// everywhere (the review in .claude/skills/review-animations):
/// - Things appearing or answering a tap use a strong ease-out: they start
///   moving at once and settle softly. Never ease-in for UI; it feels late.
/// - Everyday UI stays under 0.3 s; exits are quicker than entrances.
/// - Things move a few points, not across the screen.
/// - With Reduce Motion, things fade instead of moving (callers check).
enum Motion {
    /// Strong ease-out, for anything appearing or responding.
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// Strong ease-in-out, for something on screen moving to a new place.
    static func easeInOut(_ duration: Double) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    /// The iOS sheet curve, for a whole step sliding in.
    static func drawer(_ duration: Double) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }

    /// A small change in the interface (a banner, a card, a state).
    static func change(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : easeOut(0.22)
    }

    /// Something leaving: quicker than it came.
    static let exit: Animation = easeOut(0.15)
}

extension AnyTransition {
    /// Rises a few points as it fades in: bars along the bottom.
    static var rise: AnyTransition {
        .opacity.combined(with: .offset(y: 12))
    }

    /// Drops a few points as it fades in, and simply fades out: banners.
    static var drop: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity)
    }

    /// The next card in a game: a short step in the reading direction.
    static var nextCard: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: 24)),
            removal: .opacity.combined(with: .offset(x: -24))
        )
    }
}
