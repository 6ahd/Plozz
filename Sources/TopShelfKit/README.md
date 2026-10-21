# TopShelfKit

Publishes the tvOS **Top Shelf** snapshot (poster rows or full-screen artwork on
the Apple TV Home Screen) from the app's domain models into the shared App Group
container, where the Top Shelf extension reads it.

## Responsibility

- `TopShelfSnapshot` — the on-disk Codable snapshot shape (sections,
  display titles, item ids, artwork URLs and optional full-screen metadata).
  The **extension** compiles this type, `TopShelfStore` and
  `TopShelfContentBuilder` directly, keeping `CoreModels` out of its memory budget.
- `TopShelfStore` — read/write helper around the shared App Group
  container. Used by both the app (to write) and the extension (to read).
- `TopShelfContentBuilder` — native sectioned/carousel content mapping, shared
  by the extension and its package tests without the app's model stack.
- `TopShelfPublisher` — app-side mapping from `[MediaItem]`
  Continue-Watching + Latest rows onto a `TopShelfSnapshot`, with empty-row
  pruning. Always writes (even empty) so a freshly-signed-out state clears
  the shelf.

Top Shelf preferences are device-local and shared by Plozz profiles. Settings →
Everyone → Top Shelf explains the Apple TV Home Screen placement, offers a
default-on **Show Top Shelf** switch, and exposes independent Continue Watching and Recently Added
counts, each defaulting to 4 with a 1–20 range. The app applies the limits before
resolving artwork, without changing provider order, content identity, library
visibility, or the active profile's artwork policy. Editing either count
republishes current Home content, cancels superseded artwork work, and notifies
tvOS after a successful snapshot write. Short feeds are not padded.
Turning Top Shelf off writes an empty snapshot immediately, including without a
loaded Home model, and hides layout/count controls without erasing their values.
Publication commits and settings changes are serialized on the main actor;
generation checks reject suspended artwork from before a settings change or a
newer publication, including a quick off/on cycle. Disabled publication does not
resolve artwork. The extension returns no media for the empty snapshot.

**Posters** remains the default. **Full Screen** publishes the same limited feeds
as a native `TVTopShelfCarouselContent` with `.details`: Continue Watching first,
then Recently Added, deduplicated by account-qualified identity. tvOS owns the
Home Screen presentation and swipe-up expansion; Plozz does not force fullscreen.
The carousel exposes Play using the existing account-scoped route, not a More
Info button that would misleadingly start playback. No video autoplay is added.

Full-screen art uses the active profile's Top Shelf artwork policy and bounded
hero resolution. Episodes resolve series artwork, not episode stills. The app
writes 1920x1080 JPEGs; portrait fallbacks are fitted without cropping and missing
art gets a neutral background. Episode titles and summaries respect spoiler
protection. Only the selected style's artwork is resolved. Preview cards in
Settings are schematic illustrations, never a second copy of profile media.
Old settings and snapshots without a layout flag keep their poster presentation.

## Invariants

- **App Group container is the only side-channel.** No network, no
  keychain.
- **No secrets in the snapshot.** Item ids and artwork URLs only — tokens
  for token-protected art are scoped to a refresh strategy outside this
  module.
- **`CoreModels` only imported by the app, not the extension.** The snapshot
  and store stay independent of domain models and UI; the store uses OSLog
  only to report write failures.
- **Idempotent.** Republishing the same snapshot is cheap and side-effect
  free.

## Where to look first

- `TopShelfPublisher.swift` — domain → snapshot mapping.
- `TopShelfSnapshot.swift` — on-disk shape.
- `TopShelfStore.swift` — shared-container I/O.
- `TopShelfContentBuilder.swift` — native poster/carousel mapping, compiled directly
  into the extension and exercised by package tests.
- `TopShelfBackdropComposer.swift` — bounded full-screen artwork export.
