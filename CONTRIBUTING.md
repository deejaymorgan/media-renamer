# Contributing

Thanks for your interest! This is a personal project shared **as-is**, so please
read the expectations at the bottom before investing much time — but issues and
PRs are genuinely welcome.

## Project shape

- **`RenamerCore/`** — the engine: a pure Swift package, **Foundation only**, no
  UI and no dependencies. All parsing/planning/execution logic lives here and is
  headlessly testable.
- **`MediaRenamer/`** — the SwiftUI app (Xcode project) that links `RenamerCore`
  as a local package and decides presentation and when to touch disk.

See [`SPEC.md`](SPEC.md) for the full design and roadmap, and
[`CLAUDE.md`](CLAUDE.md) for a deeper architecture map.

## Building & testing

```sh
# Engine — no Xcode app required:
swift test --package-path RenamerCore

# App — open in Xcode and run, or build headless:
xcodebuild -project MediaRenamer/MediaRenamer.xcodeproj \
  -scheme MediaRenamer -destination 'platform=macOS' build
```

Please make sure **both** the engine tests pass and the app builds before opening
a PR.

## Conventions

- Keep the engine **Foundation-only** with no new dependencies. Logic that can
  live in `RenamerCore` (and be unit-tested there) should.
- New parsing/planning/execution behaviour should land **with tests**. The engine
  is parity-tested against the Python oracle; mirror that style.
- Match the surrounding code: its naming, comment density, and idioms.
- The preview is read-only — only **Apply** touches disk. Test on **copies** of
  real media, never your library.

## Pull requests

- Keep changes focused; a clear description of the *why* helps a lot.
- Note what you ran to verify (test output, a build, a manual check).

## Expectations

Maintained on a best-effort basis with **no guaranteed response or merge**. If a
change is small and obviously correct, it has the best odds. For anything larger,
open an issue to discuss it first so you don't build something that won't land.
