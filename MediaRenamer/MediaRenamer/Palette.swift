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
    // Layout — one colour per mode, adopting the split the destination bands
    // already drew (a blue `folder.fill`, a teal flat band).
    //
    // This **reverses** an earlier decision to tint both modes the same, whose
    // stated worry was that a split would make one mode read as the warning and
    // the other as the safe default. Blue and teal are both calm hues and
    // neither carries an alarm reading, so differentiating them no longer
    // implies that asymmetry — while sharing one tint left the two layouts
    // genuinely hard to tell apart at a glance, which is what prompted the
    // reversal. Colour is still never the only signal: the glyph and the word
    // carry it too.
    //
    // Blue doing double duty with the TV chip is accepted: different context,
    // different shape.
    static let folders: Color = .blue
    static let flat: Color = .teal
}
