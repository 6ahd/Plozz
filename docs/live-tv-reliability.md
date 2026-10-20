# Live TV reliability and deferred features

## Scope and evidence

Prioritize reliable playback, guide availability, understandable connection
errors, and uninterrupted healthy viewing over adding more Live TV features.
Dispatcharr-specific setup, DVR, archive catch-up, recommendations, and sports
integrations are deferred, not approved implementation work.

This assessment was made on 2026-10-20 against Plozz
`2e7b200f689045dc1c18d23b06270e01d65f3341`. It is a source and test-coverage
inspection, not a new runtime result or confirmation against a real Dispatcharr
installation. The priorities below distinguish observed implementation behavior
from risks that still need reproduction. Existing tests are evidence of the
intended contracts, not a claim that they were rerun for this document.

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

## Hardening priorities

### 1. Exercise continuous playback, not just successful startup

**Observed coverage limit:** the controlled HLS fixture in
[IPTVPlaybackHostedTests](../Tests/SubtitlePresentationSupport/IPTVPlaybackHostedTests.swift)
is a finite playlist with `EXT-X-ENDLIST`. Its ordinary render check requires
a first frame and more than 0.2 seconds of progress. An opt-in local relay case
observes 20 seconds of continued advancement. Those checks are useful, but do
not establish long-running rolling-HLS recovery or uninterrupted playback.

Extend that existing fixture and hosted runner rather than introducing a new
test framework. Exercise raw transport streams, rolling MPEG-TS HLS, and rolling
fMP4 HLS through the actual proxy, engine, player model, and ownership path.
Use valid timestamped media and advancing sequences; a repeated static manifest
or a mocked `.playing` state is not continuous-playback evidence.

First add bounded cases for a brief mid-stream disconnect, a delayed segment,
an expired redirected delivery session, and a failed guide refresh while video
continues. Add manifest discontinuities and key/init-segment changes where the
current route supports them. Extend to an explicitly selected longer soak only
after the short cases complete reliably.

Measure first-frame time, actual presentation/progress, recovery duration,
unexpected terminal transitions, origin opens, peak concurrent root requests,
and cleanup. A progressing clock alone does not prove an unfrozen picture or
audible audio. Keep healthy-stream and fault-injected results separate.

### 2. Separate temporary throttling from terminal refusals

**Observed behavior:** `IPTVPlaybackProxy.refusal` caches HTTP 401, 403, 429, 451,
and 509 for the proxy's remaining lifetime. Immediate repeated requests avoid
the upstream, intentionally preventing native fallback from hammering a refusal.
There is no cooldown expiry in that cached state. `IPTVHTTP.bytes` parses
`Retry-After` as a numeric delay for 429, not an HTTP-date.

This is a hardening candidate, not yet a demonstrated production retry failure:
the coordinator can retire a failed lease and create a new proxy. Reproduce both
same-proxy requests and the actual visible retry path before changing semantics.

Add a deterministic sequence: upstream 429 with a finite `Retry-After`, then
healthy media. Assert no request storm during the delay and that an authorized
retry can reach the recovered upstream afterward. Cover numeric/date/malformed
headers, cancellation during backoff, channel replacement, and repeated refusal.
Keep terminal authorization/access failures distinct. Do not add automatic
retries to every HTTP failure or remove the existing immediate-refusal guard.

Owner: [IPTVHTTP](../Sources/ProviderIPTV/IPTVHTTP.swift),
[IPTVPlaybackProxy](../Sources/ProviderIPTV/IPTVPlaybackProxy.swift), and the
existing [proxy diagnostics tests](../Tests/ProviderIPTVTests/IPTVPlaybackDiagnosticsTests.swift).

### 3. Make connection-limit errors actionable without another stream

**Observed gap:** Dispatcharr can return HTTP 503 with a JSON error identifying
exhausted provider connections. Plozz retains the HTTP status, but `IPTVHTTP.bytes`
cancels non-success bodies before classification; there is no Dispatcharr-style
capacity classification. A 503 alone is not proof of a connection limit:
Dispatcharr also uses it for other temporary failures.

Reproduce capacity refusal, ordinary 503, and malformed/private error bodies.
If adding classification, inspect only a bounded body from the original failed
request, map recognized evidence to a safe typed category, and discard the body.
Do not persist provider prose, URLs, or credentials. Do not open a second stream
to diagnose the first, automatically stop another viewer, or treat every 503 as
an exhausted tuner. Preserve usable current playback when an additional stream
cannot be opened, subject to the existing single-connection handoff policy.

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

Start with mixed-success fixtures, including cold and cached guides. Keep video
and channel identity stable while guide fetches time out, return malformed data,
or fail on one source. If partial publication is warranted, represent incomplete
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

## Smallest useful execution order

1. Establish the rolling-stream baseline and deterministic refusal fixtures.
2. Reproduce and fix only confirmed retry/error-classification defects, one
   coherent change at a time, retaining the existing ownership boundaries.
3. Exercise mixed guide failures during rendered playback; change partial-result
   behavior only with explicit error/coverage semantics.
4. Run the longer continuity and lifecycle scenarios against the candidate.

Use the [testing policy](testing-policy.md) for selected suites and existing
hosted runners. Cover tvOS and iOS/iPadOS when shared behavior changes, and keep
Jellyfin/Emby and Plex lifecycle contracts intact. Use
[the performance lab](performance-lab.md) for resource/cost measurements, not
elapsed unit-test time. Do not run a full suite or install a new dependency merely
to perform this documentation assessment.

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

Keep follow-up evidence on the existing report when it matches. The unproven
hardening candidates above are not newly established shipped defects.

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
