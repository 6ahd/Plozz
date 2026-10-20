# Live TV reliability and deferred features

## Scope and evidence

Prioritize reliable playback, guide availability, understandable connection
errors, and uninterrupted healthy viewing over adding more Live TV features.
Dispatcharr-specific setup, DVR, archive catch-up, recommendations, and sports
integrations are deferred, not approved implementation work.

The initial assessment on 2026-10-20 used Plozz
`2e7b200f689045dc1c18d23b06270e01d65f3341`. The first implementation pass now
includes reproduced transport fixes and controlled, rendered-playback results
on tvOS and iOS simulators. It does not establish interoperability with a real
Dispatcharr installation. Implemented changes, measured outcomes, and remaining
coverage gaps are separated below.

The goal is no app-induced interruption while the source remains healthy, and
bounded, truthful recovery when it does not. A client cannot guarantee an
uninterrupted picture through an upstream outage longer than its available
buffer. Concealing a frozen picture, replaying stale data, or spinning forever
does not meet the goal.

See [current Live TV behavior](live-tv-prototype.md),
[troubleshooting history](iptv-history.md), and
[playback routing](playback-engines.md#iptv-live-streams).

## Preserve the safeguards already present

| Existing contract | Implementation and regression references |
| --- | --- |
| Saved channels remain available during slow or failed background catalogue refresh. Failed imports do not replace the last committed catalogue. | [IPTVClient](../Sources/ProviderIPTV/IPTVClient.swift), [IPTVIntegrationTests](../Tests/ProviderIPTVTests/IPTVIntegrationTests.swift) |
| Guide failure is distinct from channel/playback availability. Last-good guide windows survive ordinary failures; revoked authorization is not stale-data permission. | [LiveTVServerGuideImport](../Sources/FeatureLiveTVCore/LiveTVServerGuideImport.swift), [LiveTVServerGuideImportTests](../Tests/FeatureLiveTVCoreTests/LiveTVServerGuideImportTests.swift), [LiveTVIndexedCacheTests](../Tests/FeatureLiveTVCoreTests/LiveTVIndexedCacheTests.swift) |
| HLS refreshes keep stable segment addresses and reuse redirected live delivery sessions. Expired delivery URLs have bounded renewal; real origin refusals remain visible. | [IPTVPlaybackProxy](../Sources/ProviderIPTV/IPTVPlaybackProxy.swift), [IPTVPlaybackRedirectTests](../Tests/ProviderIPTVTests/IPTVPlaybackRedirectTests.swift) |
| Account headers do not cross origins. Authentication, catalogue, guide, and playback redirects retain their separate policies. | [IPTVHTTP](../Sources/ProviderIPTV/IPTVHTTP.swift), [IPTVPlaybackRedirectTests](../Tests/ProviderIPTVTests/IPTVPlaybackRedirectTests.swift) |
| One proxy does not open overlapping live root streams. Cancellation and stop drain owned work. Intentional Multiview streams and HLS child requests are different cases. | [IPTVPlaybackLifecycleTests](../Tests/ProviderIPTVTests/IPTVPlaybackLifecycleTests.swift), [IPTVHTTPLifecycleTests](../Tests/ProviderIPTVTests/IPTVHTTPLifecycleTests.swift) |
| Preview/fullscreen/Multiview transitions reuse the current owner where appropriate. Late callbacks cannot replace a newer channel, and authorization is rechecked after asynchronous work. | [LiveTVPlaybackCoordinatorTests](../Tests/FeatureLiveTVCoreTests/LiveTVPlaybackCoordinatorTests.swift), [LiveTVPlaybackPreparationTests](../Tests/FeatureLiveTVCoreTests/LiveTVPlaybackPreparationTests.swift), [LiveTVMultiviewCoordinatorTests](../Tests/FeatureLiveTVCoreTests/LiveTVMultiviewCoordinatorTests.swift) |
| The engine already distinguishes buffering from reconnecting. App-level startup, buffering, manual retry, and source-reset recovery are bounded. | [LiveChannelPlayerView](../Sources/FeaturePlayback/LiveChannelPlayerView.swift), [LiveChannelPlayerModelTests](../Tests/FeaturePlaybackTests/LiveChannelPlayerModelTests.swift), [LiveChannelRetuneBudget](../Sources/FeaturePlayback/LiveChannelRetuneBudget.swift) |

Do not replace these mechanisms with another player, generic retry wrapper,
periodic channel restart, permissive guide-name matching, or extra stream probes.

## First hardening pass

### 1. Exercise continuous playback, not just successful startup

**Original coverage limit:** the controlled HLS fixture in
[IPTVPlaybackHostedTests](../Tests/SubtitlePresentationSupport/IPTVPlaybackHostedTests.swift)
is a finite playlist with `EXT-X-ENDLIST`. Its ordinary render check requires
a first frame and more than 0.2 seconds of progress. An opt-in local relay case
observes 20 seconds of continued advancement. Those checks are useful, but do
not establish long-running rolling-HLS recovery or uninterrupted playback.

**Implemented:** [IPTVContinuityHostedTests](../Tests/SubtitlePresentationSupport/IPTVContinuityHostedTests.swift)
uses the existing HTTP fixture and hosted runners with the real provider,
playback lease, proxy, `PlozzigenVideoEngine`, and `LiveChannelPlayerModel`.
Synthetic timestamped media drives advancing four-segment live playlists with
no `EXT-X-ENDLIST`. Both MPEG-TS and fMP4 HLS are covered.

The tests count changing decoded-image fingerprints, measure player progress
and image gaps, and assert no terminal error or manual retry. They inject a raw
TS disconnect after the first frame, a five-second segment delay, an expired
redirected session, and HTTP/malformed-guide failures during viewing. Closing
the lease must leave zero upstream requests and no retained relay failure entry.
Existing lifecycle tests separately cover root serialization and stop races.

Manifest discontinuities, key/init-segment changes, repeated disruptions over
hours, and physical-device/audio observations remain follow-up coverage, not
claims made by these short controlled runs.

### 2. Separate temporary throttling from terminal refusals

**Reproduced and fixed:** a finite 429 refusal previously blocked the same proxy
for its entire lifetime. Playback 429/509 now accepts nonnegative integer seconds
or an HTTP-date, computes a monotonic deadline, and suppresses upstream requests
until that deadline. A later request can then reach the upstream and clears only
the obsolete rate-limit error, preserving diagnostic request history.

Overlapping HLS child refusals cannot shorten an existing cooldown. A regression
first demonstrated that a later one-second response overrode a ten-second
response; the proxy now retains the longer deadline. Missing or malformed
delays remain conservatively suppressed until a new lease. Authorization,
access, and recognized capacity refusals remain terminal for that proxy and
cannot be replaced by a late throttle.

No timer, polling, or new automatic retry loop was added. The existing visible
retry path is covered through the coordinator: it closes the failed lease once
and opens a fresh one for rate-limit and capacity errors.

Owner: [IPTVHTTP](../Sources/ProviderIPTV/IPTVHTTP.swift),
[IPTVPlaybackProxy](../Sources/ProviderIPTV/IPTVPlaybackProxy.swift), and the
[proxy diagnostics tests](../Tests/ProviderIPTVTests/IPTVPlaybackDiagnosticsTests.swift),
[recovery tests](../Tests/ProviderIPTVTests/IPTVPlaybackRecoveryTests.swift), and
[coordinator tests](../Tests/FeatureLiveTVCoreTests/LiveTVPlaybackCoordinatorTests.swift).

### 3. Make connection-limit errors actionable without another stream

**Reproduced and fixed:** a Dispatcharr-style capacity refusal previously lost
its typed cause. Playback GET responses with HTTP 503 and JSON content now inspect
at most 4 KiB of the original body for the recognized `error` field containing
`maximum connection limits`. That maps to the existing safe tuner-unavailable
message instead of generic HTTP 503 copy. Provider prose, URLs, and credentials
are not retained or forwarded.

Inspection is cancellation-aware and limited to one second after response-body
inspection begins; it does not replace connection/first-byte/startup timeouts.
Oversized, malformed, unrecognized, unavailable, or non-JSON bodies retain the
ordinary 503 failure and are not cached as capacity exhaustion.

The hosted engine/model regression requires the typed error and exactly one
upstream request. There is no second diagnostic GET, no automatic eviction of
another viewer, and no change to the existing single-connection handoff policy.

Sources: [Dispatcharr refusal handling][dispatcharr-stream],
[Rivulet's capacity check][rivulet-busy], and
[Plozz proxy diagnostics](../Tests/ProviderIPTVTests/IPTVPlaybackDiagnosticsTests.swift).
The useful lesson is the error distinction, not Rivulet's extra diagnostic GET.

### 4. Prove guide failure isolation, then address partial batches explicitly

**Already protected:** failed server-guide windows preserve earlier data, and
an unsupported guide does not by itself make channels unplayable.
`testUnsupportedGuideKeepsChannelsPlayableAndDoesNotLabelServerUnsupported`
documents that boundary.

**Observed provider-level limitation:** `IPTVProvider.retrieveGuide` accumulates
successful native Xtream rows, but throws if a later required XMLTV fallback
fails. `xmlTVGuide` likewise throws if a later configured guide fails after an
earlier one supplied rows. The current array-or-error return shape does not
publish those partial successes. The import layer can preserve previously
published windows, but cannot publish new rows from a batch that threw.

**Added coverage:** mixed native-guide success plus XMLTV fallback 401, 429, or
503 remains an explicit error while channels stay available. The rendered
rolling-stream fixture also preserves the same player and delivery session
through a guide 503 and malformed XML. Existing import/cache regressions protect
last-good windows. Partial-success publication is deliberately unchanged.

If partial publication is warranted, represent incomplete
coverage and its error explicitly; never turn failure into an empty successful
guide or suppress authentication/cancellation. Do not change guide matching or
profile boundaries to make row counts look better.

Owners: [IPTVProvider](../Sources/ProviderIPTV/IPTVProvider.swift),
[LiveTVServerGuideImport](../Sources/FeatureLiveTVCore/LiveTVServerGuideImport.swift),
[IPTVIntegrationTests](../Tests/ProviderIPTVTests/IPTVIntegrationTests.swift), and
[guide import tests](../Tests/FeatureLiveTVCoreTests/LiveTVServerGuideImportTests.swift).

### 5. Verify long-session recovery budgets and lifecycle boundaries

**Observed policy:** startup times out after 30 seconds; continuous buffering
after a presented frame times out after 60 seconds. Source-reset retunes allow
three attempts per channel session, spaced by at least 20 seconds after the
first. Sustained healthy playback does not replenish that retune budget.
Terminal engine failure and end-of-stream are not automatically treated as
source-reset requests.

**Unchanged:** the bounded disconnect, delayed-segment, and expired-session cases
recovered with the pinned engine and current budgets. They do not demonstrate a
need to increase retries or upgrade the engine.

These bounds prevent loops. Do not simply lengthen/remove them, reset budgets
on every frame, or turn all end-of-stream signals into retries. Reproduce
separated disruptions in one long session and distinguish upstream engine
reconnection from host retunes. Determine whether legitimate recovery is cut
short before choosing a narrowly scoped change.

Combine the real playback path with preview/fullscreen transitions, Multiview
promotion, guide/catalogue refresh, temporary inactivity, and background/return.
Verify that pause intent is preserved, unrelated changes do not reopen the
stream, and profile/account/source revocation still stops playback promptly.
Intentional background behavior must not be mislabeled as a continuity defect.

The pinned engine revision is owned by [Package.swift](../Package.swift).
Inspect its actual contract before changing the adapter or proposing an upgrade;
do not assume upstream lacks recovery because a host-level test uses a spy.

## Controlled playback results

Final hosted runs on 2026-10-20 used tvOS 26.2 (Apple TV 4K simulator), iOS 26.2
(iPhone 17 Pro simulator), and engine revision
`deb90eb3f740fe1ddda74301a64e3937e480877d`. Each platform completed 20 tests,
with zero failures and one explicitly opt-in real-relay test skipped. All seven
new continuity/capacity cases ran on both platforms.

Values below are tvOS / iOS. Observation starts at the first decoded frame.

| Case | Observation | Changing images | Longest image gap | Origin opens |
| --- | --- | --- | --- | --- |
| Healthy TS HLS | 25 s | 374 / 374 | 0.161 / 0.160 s | 1 / 1 |
| Healthy fMP4 HLS | 60 s | 899 / 899 | 0.160 / 0.156 s | 1 / 1 |
| Five-second fMP4 segment delay | 25 s | 359 / 343 | 1.125 / 2.121 s | 1 / 1 |
| Expired redirected fMP4 session | 25 s | 374 / 374 | 0.164 / 0.156 s | 2 / 2 |
| Guide failures during fMP4 playback | 25 s | 373 / 373 | 0.231 / 0.220 s | 1 / 1 |
| Raw TS disconnect after first frame | 25 s | 329 / 298 | 2.158 / 5.089 s | 2 / 2 |

Healthy fMP4 advanced 59.87 seconds across 30 manifest sequence positions.
Raw TS first-frame startup was 8.22 / 8.46 seconds; recovery advanced 21.97 /
19.86 seconds during observation. The raw reconnect fixture reopens synthetic
media, not a real broadcaster's live edge. Outages can produce visible gaps:
these results prove bounded recovery in this workload, not seamless recovery
from every provider failure. Audio was muted, so audible audio continuity was
not established. Sixty seconds is not an hours-long soak.

The final targeted package run completed 1,229 passing tests, nine skips, and
one failure in the unchanged
`PlayerSkipMarkerTrackTests.testFlatPerformanceTrackPairsItsSurfaceWithTheAppAppearance`
pixel-equality assertion. All 126 IPTV tests passed (six additional skips).
The unrelated rendering failure was reproduced on a second run and left outside
this work; the package run is not a full green result. The earlier six-module
run additionally exercised CoreModels, FeatureLiveTVCore, EnginePlozzigen, and
MediaTransportHTTP; its new refusal-body timing fixture was corrected and rerun.

### Fixture provenance and reproduction

The four `live-continuity*` files in `Tests/SubtitlePresentationSupport/Fixtures`
were generated locally with ffmpeg from `testsrc2=size=160x90:rate=15` and
`sine=frequency=440:sample_rate=48000`, not downloaded television content.
Both variants are 90 seconds of H.264 (`libx264`, ultrafast, CRF 32, GOP 30,
scene-cut disabled, yuv420p) and mono 48 kHz AAC at 32 kbps. HLS uses two-second
segments, `hls_list_size=0`, and `hls_flags=single_file`, once with segment type
`mpegts`, once with `fmp4`. The stored finite manifests are segment indexes;
the HTTP fixture serves only an advancing four-segment live window.

Use `IPTVContinuityHostedTests` and `IPTVPlaybackHostedTests` in the existing
`PlozzFocusTests` or `PlozziOSPresentationTests` schemes. Preserve explicit owned
simulator selection, bounded runners, and structured result bundles.

## Remaining execution priorities

1. Extend the passing rolling fixtures to discontinuities, key/init changes,
   and repeated separated disruptions in a longer, explicitly bounded soak.
2. Exercise preview/fullscreen/Multiview and background lifecycle transitions
   during those real playback workloads.
3. Validate against real Dispatcharr and physical devices, including audio.
4. Change partial-guide publication only with explicit error/coverage semantics.

Use the [testing policy](testing-policy.md) for selected suites and existing
hosted runners. Cover tvOS and iOS/iPadOS when shared behavior changes, and keep
Jellyfin/Emby and Plex lifecycle contracts intact. Use
[the performance lab](performance-lab.md) for resource/cost measurements, not
elapsed unit-test time. Do not add retries or dependencies without a demonstrated
failure in the existing path.

For each behavioral change, retain a failing baseline, the same passing
reproduction, source/platform/engine identity, request and cleanup counts, and
the observed recovery interval. Specify fault duration and acceptable recovery
bound before interpreting the result. Test resources must be owned and bounded.
Simulator evidence does not establish real-provider or physical-device behavior.

## Existing reports, not new diagnoses

- [#113](https://github.com/brandomoore/Plozz/issues/113): intermittent Live TV
  availability while accounts remain in Libraries. The issue records candidate
  admission fixes and remaining reporter uncertainty; do not equate it with
  source deletion or claim this assessment resolves it.
- [#116](https://github.com/brandomoore/Plozz/issues/116): a guide/API support
  failure report. Establish the actual provider and failing request before
  assigning a cause.
- [#168](https://github.com/brandomoore/Plozz/issues/168): a playlist URL/imported
  file rejection. Obtain the relevant sanitized response/fixture; do not assume
  a cloud-hosted download is returning M3U bytes rather than an HTML page.

Keep follow-up evidence on the existing report when it matches. The controlled
fixes above do not establish the cause of these reports or resolve them.

## Deferred feature gaps

| Feature | Current boundary | Deferred work |
| --- | --- | --- |
| Dedicated Dispatcharr setup | Generic M3U/XMLTV and Xtream interfaces exist; real-server interoperability is not established by this assessment. | Named-server onboarding, profile selection, optional API sign-in. Do not build another IPTV transport. |
| DVR management | No Dispatcharr recording adapter or shared recording-management capability was found in the inspected Live TV path. | Recording scheduling, series rules, cancellation, and recording-library integration. |
| Provider archive catch-up | Current live seek/pause behavior is not provider-archive playback. | Archive discovery, retention/time-zone semantics, and authenticated catch-up URLs. |
| Programme-first discovery | Existing guide, search, favorites, and recents remain the scope. | On Now/Starting Soon shelves and profile-scoped recommendations. |
| Sports scores and tune-to-game | No scoreboard-to-channel implementation was found in the inspected source. | External score data, game/guide matching, and scores layouts. |

Rivulet is reference material for product behavior, not a replacement
architecture. Relevant source: [Dispatcharr setup][rivulet-setup],
[DVR][rivulet-dvr], [recommendations][rivulet-suggestions], and
[game matching][rivulet-games]. Its [PolyForm Noncommercial license][rivulet-license]
must be considered before any code reuse; implement independently rather than
transplanting its code as part of reliability work.

[dispatcharr-stream]: https://github.com/Dispatcharr/Dispatcharr/blob/cc68a83f5a02580fa4ca5257228d85d520414bb3/apps/proxy/live_proxy/views.py
[rivulet-busy]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/RivuletCore/LiveTV/LiveTunerBusy.swift
[rivulet-setup]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/RivuletCore/LiveTV/LiveTVSourceConnector.swift
[rivulet-dvr]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/RivuletCore/LiveTV/IPTVProvider+DVR.swift
[rivulet-suggestions]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/RivuletCore/LiveTV/LiveSuggestions.swift
[rivulet-games]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/RivuletCore/Scores/GameMatcher.swift
[rivulet-license]: https://github.com/l984-451/Rivulet/blob/5a0f34b905ab5063ab665c8d1dbb16b5cd9e51de/LICENSE
