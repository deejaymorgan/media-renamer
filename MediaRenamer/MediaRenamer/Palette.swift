import SwiftUI

/// The app's colour legend, in one place so chips, badges, and before→after
/// names stay consistent everywhere they appear.
///
/// Two independent axes:
/// - **Change axis** — is this text the *new* name or the *original* one?
///   New names are tinted (`renamed`); originals stay muted via `.secondary`
///   at the call site (a hierarchical style, not a fixed `Color`).
/// - **Category axis** — what kind of item/issue is this? Used by the summary
///   chips and the flag badges so a category reads the same colour wherever it
///   shows up.
enum Palette {
    /// The resulting / new name. Reads like a diff addition against the muted
    /// original — green for "this is what you'll get."
    static let renamed: Color = .green

    // Categories — shared by SummaryChips and FlagBadges.
    static let tv: Color = .blue
    static let movie: Color = .purple
    static let conflict: Color = .red
    static let junk: Color = .orange
    static let verify: Color = .orange
}
