# FeatureSettings

The Settings screen and its detail pages. Profile-aware, integration-aware,
and the single place caption customization lives.

## Responsibility

- `HeroSettingsControls` — Hero keeps content selection, watched filtering, item
  count, and automatic changes together, shared by TV and mobile. **Ratings** and
  **Trailers** each show their current On/Off state and open their detailed
  controls; neither is hidden behind a generic Appearance label.
  The shared rating-count picker is visibly labeled **Maximum ratings shown**:
  it caps available scores rather than promising every title has that many.
  **Hero content sources** is the source-selection page; its link summarizes the
  currently permitted selections using the current app locale for both source
  labels and list formatting. Library, collection, Watchlist variety, and
  Discovery options use the shared `ViewPreferenceChoiceGroup` with the source
  they configure, so a source toggle and its links form one visual group.
  TV forms share row/section spacing and contained, concentric focus geometry;
  inline steppers use the same row height and align to the trailing value column.
  Hero copy uses **content** for the overall selection and **item** for one entry,
  rather than calling entries titles. **Advance automatically** and its conditional
  **Seconds per item** control share a group without a redundant section heading.
  Mobile source groups use separate native Section rows; grouped-page links
  use independent buttons with native navigation destinations so no link can
  claim a sibling switch's cell action.
  **Discovery** consistently means external recommendations; its
  provider selections and **Show provider labels** attribution toggle live together.
  Ratings, trailers, and the longer source/provider/library/collection lists use subpages. TV uses
  retained detail panes with a separate nested navigation owner and returns focus
  to the originating link; mobile keeps system switches and native navigation.
- **Kids profiles** always disable external Home Discovery, including Showcase's
  Discovery row, independently of whether a Parental PIN exists. Preferences stay
  saved for later use outside Kids mode; this restriction is not synced as an
  editable setting. Connected server-user restrictions still govern library
  content—Plozz does not infer maturity from incomplete external catalog ratings.
- `CardAppearanceControls` — the independent **Show unwatched episode count**
  toggle lives beside Watched Indicator on both platforms. It defaults on,
  persists per profile, and transfers/syncs with that profile without changing
  its watched/unwatched style.
- `SettingsView` / `SettingsWorkspace` — tvOS keeps two fixed columns: profile
  identity and categories on the left, the selected section on the right.
  General is initially visible. The avatar/name switches profiles; the adjacent
  Edit action uses the same `ProfileActionsList` as the profile picker.
  `SettingsFormLayout` groups related controls into one vertical form, retaining
  child pages for longer editors. Single-control preferences such as Language
  use one compact label-and-control row without an extra heading or explanatory
  paragraphs. General owns language and spoiler protection.
  Appearance & Layout starts with Theme (including gradient backgrounds and
  Liquid Glass), followed by Customize Home, display size, artwork, cards,
  navigation, Music Player, Circadian Mode and Detail Page. Playback groups
  audio, autoplay/Up Next, marker skipping, seeking and display fades.
  Subtitles is its own profile category for mode, language, downloading,
  per-series memory and the shared/Live TV style editors; downloading still
  follows the active profile's provider capabilities.
  Both subtitle-style editors reclaim the full screen: the category column
  slides and fades away as the detail expands, then returns with Back to the
  same Subtitles section. Reduce Motion changes the layout without the slide.
  Hidden or focus-ineligible categories also stop observing native focus, so
  an editor control cannot be mistaken for a category during the transition.
  The existing navigation stack and profile context remain intact, including
  inside the editor's font and appearance subpages.
  Libraries, Live TV and Trackers remain profile-owned. Household setup is
  separate under Everyone; About and Help & Diagnostics have their own entries.
  `SettingsRowStyle` and `SettingsContext` provide shared controls and dependencies.
  The right navigation viewport extends through the vertical safe area, keeping
  the initial top inset inside its scrollable content instead of clipping pages
  at that inset. Segmented choices share the body-sized control font; explanatory
  copy uses the smaller shared helper style.
- `ProfileDetailView` — manage the active profile: rename, recolor,
  switch / sign out of accounts, configure the Plex Home-user mapping
  (`PlexLinkedUserDetailView`).
- `ServerDetailView` + `ServersAndLibrariesDetailView` — manage stored
  household servers / accounts (`AccountStore`) and remove accounts.
  `MyLibrariesDetailView` owns the active profile's server-user and library choices.
- `IntegrationsDetailView` — "Trackers" page: connect/disconnect for Trakt,
  Simkl, AniList & MyAnimeList (delegates to each tracker service) plus the
  Watch Status across-servers sync toggle.
- `PreferenceDetailViews` — subtitle behaviour / spoiler / diagnostics /
  Home-customization preferences. Subtitle *behaviour* (mode, language,
  auto-download) lives here; the subtitle *look* is now adjusted in the
  player while watching.
- `HeroCollectionPickerView` — Customize Home's opt-in **Collections** hero source
  chooses multiple collections across enabled movie and TV libraries, or from accounts'
  personal collections when its provider advertises that capability. The native picker
  is shared by TV, iPhone and iPad, scopes requests to the active account and
  server viewer, and loads collection pages only while open. Errors retain
  loaded rows and expose Retry. TV reuses the settings detail-page scroll layout,
  local header, native Back and wrapping checkable source rows rather than a
  full-page List or automatic segmented Picker. Mobile retains grouped native
  navigation. Choosing a collection toggles only that selection; switching sources
  retains other selections. Selected rows show their source and can be removed
  individually, including when a source is unavailable. Choice identity includes
  account, optional library, server viewer and collection, not the display name.
  The account/optional-library/collection selections stay
  in the profile's `HeroSettings` blob and travels with existing profile
  transfer/sync; older single-selection blobs migrate to a one-element array,
  and unavailable sources do not silently erase saved choices.
- `SettingsAboutSection` — app identity / version / release notes.
- `SettingsCommunityLinks` — separate Discord-first and GitHub cards shared by
  About and mobile Settings. Apple TV shows them below the app identity.
  Mobile uses one shared Community section with full-wordmark direct links and
  expandable QR cards: directly above Support in compact iPhone Settings,
  and on the About page in regular-width layouts. The cards use
  official icon-and-wordmark lockups directly on their surfaces, without colored
  icon tiles or duplicate name labels. They follow the theme's primary text color
  and stay outside the codes' white scan margins. Narrow layouts stack without
  shrinking the codes. Public destinations are centralized in `CoreModels.AppLinks`.
  `SettingsCommunityLogo` balances both brands by visible ink area rather than
  equal height: Discord renders at 75% of GitHub's height, with each original
  aspect ratio preserved. A common layout height keeps caption baselines aligned
  on TV and mobile; hosted coverage compares the rendered areas at both sizes.
  Lockup sources are from [Discord](https://discord.com/branding) and
  [GitHub](https://brand.github.com/foundations/logo); original SVGs are in
  `docs/assets/{discord,github}-lockup.svg`. The marks and lockups live in
  `App/Resources/CommunityAssets.xcassets`, linked by both app targets and their
  presentation-test hosts; platform-only catalogs must not own shared logos.
  Their vector PDF exports use CairoSVG
  with `dpi=72` so source units map to PDF points without fractional-height
  rounding by the asset compiler:
  `python3 -c "import cairosvg; cairosvg.svg2pdf(url='docs/assets/discord-lockup.svg', dpi=72, write_to='App/Resources/CommunityAssets.xcassets/DiscordLockup.imageset/discord_lockup.pdf')"`
  (substitute `github` / `GitHubLockup` for the GitHub export).
  The Discord mark comes from [Simple Icons](https://simpleicons.org/) (CC0).
  Its original path is in `docs/assets/discord-mark.svg`; the asset catalog uses
  a vector PDF because Xcode's SVG renderer distorts this path's compact arcs.
  Regenerate it with
  `python3 -c "import cairosvg; cairosvg.svg2pdf(url='docs/assets/discord-mark.svg', write_to='App/Resources/CommunityAssets.xcassets/DiscordMark.imageset/discord_mark.pdf')"`.

## Invariants

- **Settings surfaces.** Read-only focusable panels use the same adaptive
  gradient surface as ordinary groups, including the opaque Reduce Transparency
  fallback. Their native focus behavior stays unchanged.
- **TV navigation ownership.** Focusing a category previews its section; Select
  or Right enters its first control. Left returns to the selected category.
  Back pops a child, then returns to categories, then leaves Settings for the
  previous available app destination. MainTabView presents the workspace outside
  the navigation-style shell, retaining the hidden shell while excluding it from
  focus and accessibility. This prevents native sidebar adaptation from expanding
  a right-pane destination across both columns. Changing navigation style retains
  the Settings section and typed child path; all three styles restore on exit.
  Focus requests are separate from native focus arrival: competing controls stay
  gated until `NativeFocusRegionObserver` confirms ownership.
- **Profile and parental scope.** Switching profile or changing Kids/PIN status
  resets the workspace. Parental unlock proof is tied to the active profile and
  current PIN verifier, not a persistent boolean. Route rendering enforces the
  same restrictions as category visibility, including artwork/metadata cross-links.
  A PIN unlock opens the selected protected pane in place; it must not dismiss
  Settings. Kids without a household PIN retain their simplified, unsealed setup.
  Mobile keeps its existing Settings navigation and control layouts.
- **Review capture.** `SettingsWorkspaceRemoteTests` is opt-in through
  `PLOZZ_SETTINGS_REVIEW=1` and runs only against the real app on an explicitly
  owned simulator. The DEBUG-only `PLOZZ_SHOTS_SETTINGS=1` launch fixture uses
  fictional Alex/Sam profiles. `PLOZZ_SHOTS_SETTINGS_NAVIGATION` chooses the
  initial navigation style; `PLOZZ_SHOTS_SETTINGS_KIDS` configures the test child
  as `off`, `no-pin`, or `pin`. These fixtures are never enabled on physical TVs
  or normal launches. Attachments include native screenshots and accessibility
  trees, not browser mockups.

- **Artwork and label presets.** Choosing any preset, including reselecting the
  previous one, replaces the whole configuration through `applyPreset`. Editing
  a view switches to Custom: no preset is selected, and a single badge appears on
  "Customize by view". `selectedPreset` derives this status from existing stored
  overrides; the backing preference retains unedited views' behavior, including
  mixed recommended rules. Settings remain in the existing profile store and sync
  payload; artwork's `scopeVersion` migrates earlier shared choices once.
  Matching a preset's value manually stays Custom; choosing a preset replaces all
  overrides. Rows show a name and short value: Library / Metadata providers, or
  On / Off. Only title-detail artwork and Home/Recommended labels also offer
  Mixed: metadata backgrounds/logos with library posters, or labels except in
  Showcase/on series artwork, respectively. Mixed is an explicit, persisted
  per-view choice independent of the backing preset. TV Select cycles the same
  supported choices as the mobile menus, with focused explanatory artwork.
  On iPhone/iPad, a chevron-marked value control opens a native checked menu:
  opening or dismissing it never changes settings. It checks the effective
  value, without an extra default/inheritance option. Presets reset the entire
  configuration, including explicit Mixed choices. The mobile Artwork page
  places its heading outside the three-preset group and customization in its
  own group below.
  Mobile customization pages use inset grouped rows on an opaque theme-aware
  background, not the ambient gradient. Only the value opens the menu; the view
  label stays in the row while the menu shows choices without a repeated title.
  Accessibility hints retain explanations without repetitive row descriptions. Mixed labels in
  Home and library Recommended retain their Showcase/title-artwork rules until
  edited. Long values and accessibility text sizes stack instead of clipping.
  Both lists group library tabs under "Libraries". Artwork separates Home's
  Showcase/hero from other Home rows, and library Recommended's hero (TV only)
  from its rows. Browse, Collections, and Playlists have independent choices;
  titles inside collections/playlists use Browse. Continue Watching rows share
  one choice across Home and libraries, independent of the series-artwork option.
  Watchlist means the standalone page, not Home's Watchlist row. Episode browser
  means detail-page episode cards; Video player artwork covers player menus,
  Up Next, and system Now Playing. Shared view components retain these scopes
  rather than treating a common layout as a shared preference.
  Labels retain equal-height visual presets: App default uses a single split illustration with
  caption bars on only one half. Show labels everywhere and Hide labels everywhere
  govern all media captions; App default owns Showcase and title-artwork exceptions.
  Explicit per-view choices, including Episodes, last until a preset replaces them.
  Library navigation names and on-artwork information are not captions.
  Per-view help states whether labels are visible or hidden; Mixed explains
  the Showcase and series-artwork exceptions. It follows the focused setting
  and updates when that setting changes.
  TV customization pages share the same scrolling Back control and title.
  Their scroll content can cross the top safe-area inset without a hard crop;
  a scroll-dependent fade handles the outer edge. Neither Back nor the title
  is pinned. Pages without contextual help also draw through the bottom safe
  area to the screen edge; pages with a fixed help footer retain its clearance.
- **Scoped TV detail navigation.** `SettingsDetailPages` and `SettingsDetailLink`
  in `SettingsDetailNavigation.swift` are reusable across settings, independent of
  artwork and labels. A `SettingsSplitRow` opts in with `SettingsDetailSubpage`;
  use `SettingsDetailLink` inside its root content to open that child. Outside a
  scoped pane, the link uses ordinary navigation. Both pages slide by the pane's
  full width: the root leaves toward the leading edge as the child enters from
  the trailing edge, and Back reverses both motions. The root stays mounted to
  preserve state and scroll position; it becomes ineligible for input while away.
  The sidebar stays stationary. Entry transfers native focus to the first row;
  Back restores the originating link after removal completes. Stale completions
  are invalidated when changing the selected sidebar page. Left remains available
  for sidebar navigation, RTL mirrors the motion, and Reduce Motion disables it.
  The slide mask contains horizontal overflow but extends through the vertical
  safe area, preserving native scroll rendering at the pane's top and bottom.
  Do not clip the safe-area frame on both axes: it cuts preview cards off above
  the panel's lower edge.
  Child content chooses its initial native focus target and calls
  `SettingsDetailNavigation.focusArrived()` when that control receives focus.
  Customization lists and their inset contextual cards occupy separate regions.
  Larger 16:9 illustrations highlight only the affected artwork, beside one sentence
  of help; full-page outlines sit inside the preview's rounded corners rather than
  being clipped by its mask. Label settings reuse the card-style preview. Navigation follows the active
  profile, including native sidebar, pinned rail, and top-tab differences. Ordinary
  title rows use 2:3 posters; episode/player thumbnails use their landscape ratios.
  Home follows the active Fullscreen Hero/Showcase layout, including disabled heroes;
  Continue Watching uses its actual thumbnail or extended series-artwork shape.
  The shared title-detail choice shows separate movie and show layouts: show episodes
  stay muted because the episode choice owns those images. Extras and cast photos
  are not promised a title-level source replacement. Keep the card and viewport
  stable as focus or values change, with no extra focus stop or content behind
  the card. A smooth 40-point bottom fade and matching scroll clearance keep focused
  rows above the fade. Lists without help reserve no footer. Horizontal pane-level
  transition clipping remains. Artwork values use "Library" and "Metadata providers", with "Mixed" for
  Recommended title details (metadata-provider heroes and library-first related posters); narrow/mobile
  and accessibility layouts stack the complete value rather than abbreviating it.
- **Profile Seerr setup uses page gutters, not artwork padding.** On iPhone/iPad,
  `ProfileSeerrSetupView` uses `SettingsPageScroll` and a centered, at-most
  720-point column. Its noninteractive profile chip uses `ProfileAvatarView`
  for the real photo, emoji, or symbol and wraps below the heading when needed.
  Panel rows and footers share one inner inset. Actions fill
  the column and stack at accessibility text sizes; long profile/user names
  wrap without widening the scroll content. TV retains its bounded settings
  layout with contained row focus.
- **Mobile Settings is a presentation action.** The profile button is the default
  entry point. Its navigation shortcut starts hidden on iPhone and iPad, keeping
  the default navigation at five destinations or fewer even with Watchlist.
  The arranger can explicitly Show it; this profile-scoped override survives
  relaunches, while Reset Navigation restores the hidden default. Automatic
  hiding is not saved as a manual preference and does not hide Settings on TV.
  Its optional tab or More entry opens
  the drawer over the current page without selecting a replacement destination.
  Keep the active content stack and overflow navigation intact on dismissal;
  destination normalization still retains the Settings-only recovery screen.
  The native tab delegate must reject the Settings transition before UIKit
  changes navigation insets; declining only the SwiftUI selection binding can
  move a scrolled page. Forward other delegate callbacks and restore the prior
  delegate when the action bridge is removed.
- **Automatic iCloud sync.** The main sync page does not show a separate Live TV
  explanation panel. Recovery lives in Troubleshooting, with a warning above
  Reload and Reset explaining that neither is normally needed. Both platforms
  use the shared transient-status presenter for progress and the actual result,
  and disable both actions while either is running. Reset still requires
  confirmation. Pending Live TV source repair rows remain in Troubleshooting.
- **Profile-namespaced settings.** Per-user prefs (theme, captions,
  diagnostics, spoiler) are namespaced by the active profile id; the
  default profile uses no suffix so an upgrading install keeps existing
  values (`migrateLegacyIfNeeded` in `ProfileStore`).
- **No tokens here.** Account & Trakt token management is delegated to
  `FeatureAuth.AccountStore` / `TraktService.TraktTokenStore`.
- **Dual-provider.** Server/library management must work for both Plex
  and Jellyfin accounts (Plex Home-user mapping is Plex-specific, but
  the UI must clearly say so).
- **No persistence schema duplication.** Persistence lives in
  `CoreModels` / `FeatureAuth` / `TraktService`; this module only
  **edits** what they store.

## Where to look first

- `SettingsView.swift` — the row composition (the tree of detail pages).
- `ProfileDetailView.swift` — profile-scoped editing.
- `PreferenceDetailViews.swift` — caption / spoiler / diagnostics prefs.
