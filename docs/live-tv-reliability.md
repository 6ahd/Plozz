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

**Reproduced and hardened:** the fourth app-level source reset previously failed
even after five minutes of healthy viewing between interruptions. The three
automatic attempts now replenish only after 300 seconds of observed, advancing
playback with a presented frame. Merely waiting five minutes does not renew
them. Frozen playheads, more than five seconds without observed progress,
backward/nonfinite clocks, pause, inactivity, buffering, seeking and new loads
discard the accumulated healthy interval. Normal coarse clock publications
within that five-second tolerance remain supported.

**Unchanged:** automatic attempts remain at least 20 seconds apart, duplicate
signals coalesce, and only one retune may run. Manual retry does not itself
replenish the automatic allowance. Startup still times out after 30 seconds and
continuous buffering after 60 seconds. Terminal engine failure and EOF do not
become automatic source-reset requests. No new timer, periodic restart,
engine upgrade, or extra upstream connection was introduced.

The exact threshold and negative paths use injected monotonic clocks in the
budget/model regressions. That deterministic evidence is not an hours-long
real-server or audible-playback observation. The existing rendered rolling-HLS
checks remain separate from the host policy's simulated elapsed time.

Combine the real playback path with preview/fullscreen transitions, Multiview
promotion, guide/catalogue refresh, temporary inactivity, and background/return.
Verify that pause intent is preserved, unrelated changes do not reopen the
stream, and profile/account/source revocation still stops playback promptly.
Intentional background behavior must not be mislabeled as a continuity defect.

The pinned engine revision is owned by [Package.swift](../Package.swift).
Inspect its actual contract before changing the adapter or proposing an upgrade;
do not assume upstream lacks recovery because a host-level test uses a spy.

### 6. Identify non-video successful stream responses

**Reproduced and hardened:** a live root GET could return HTTP 200 with HTML,
JSON, XML or no bytes and be forwarded to the decoder as successful media.
The authenticated IPTV relay now recognizes conservative document signatures
in the same 16-byte prefix it already reads. It rejects a recognized non-video
root with a loopback 502 while retaining the real upstream status and closed
body classification. Repeated engine attempts on that lease do not reopen the
origin; an explicit retry still obtains a fresh lease.

The retained failure and visible message distinguish a web page, data document,
or empty response without guessing expired credentials or copying provider
text. Engine failure combination keeps that classification even if a previous
successful HLS root remains in delivery history. No additional probe, network
read budget, body storage, response-text logging, or automatic telemetry is added.

Unknown/truncated prefixes still belong to the media decoder. This is not a
general XML/JSON validator. HEAD, byte-range responses, HLS child resources
(including arbitrary AES keys/encrypted segments), and on-demand delivery retain
their existing behavior. Actual HLS wins over a misleading HTML content type.
The change is scoped to authenticated IPTV relay playback, not a new sniffing
request for older standalone direct streams.

Owners and regressions: [IPTVPlaybackProxy](../Sources/ProviderIPTV/IPTVPlaybackProxy.swift),
[proxy diagnostics](../Tests/ProviderIPTVTests/IPTVPlaybackDiagnosticsTests.swift),
[engine failure combination](../Tests/EnginePlozzigenTests/PlozzigenLiveFailureTests.swift),
and [real-player continuity](../Tests/SubtitlePresentationSupport/IPTVContinuityHostedTests.swift).

## Guide compatibility hardening

The guide reports associated with [#107](https://github.com/brandomoore/Plozz/issues/107)
and [#116](https://github.com/brandomoore/Plozz/issues/116) established an explicit
XMLTV download returning HTTP 404 before parsing, repeatedly across channel
batches. They do not establish why that configured address was wrong or whether
the account's standard guide endpoint works. These changes are not confirmation
that the reporter's service is fixed.

The follow-up comparison used Rivulet
[`9f574c5`](https://github.com/l984-451/Rivulet/tree/9f574c5d449f1bfc3df4b59663e5b35d0b5fd433).
Its guide parser and loading behavior informed independently written compatibility
changes; no upstream implementation was copied. Rivulet does not supply a native
Xtream recovery API that automatically solves the reported 404.

- A configured Xtream guide's HTTP 404 permits one standard account `xmltv.php`
  fallback, after other configured guides have had priority. Recovered rows only
  fill uncovered channels. The same configured default is not requested twice.
  Whole-guide recovery avoids tens of thousands of new per-channel requests.
  Authentication, rate-limit, transport, malformed-document, and other HTTP
  failures are not fallback triggers. Failure of the fallback remains an error.
- A refresh-local scope lets the provider reuse confirmed XMLTV 404s across its
  2,000-channel/window batches. It does not cache errors across refreshes or
  clients, suppress cancellation, or disable the source. Last-good guide windows,
  independent sources, and authorization checks retain their existing behavior.
  Successful-document caching and parsing limits are unchanged: this is not an
  hour-long full-guide cache, and large/noncacheable successful documents may
  still be fetched or parsed in multiple batches.
- Playlist discovery accepts `tvg-url` in addition to `url-tvg` and `x-tvg-url`,
  preserving URL validation, relative resolution, order, and deduplication.
- XMLTV numeric timezone offsets accept `+HH:MM` and `-HH:MM` as well as compact
  offsets. Invalid dates/offsets are still rejected rather than guessed as UTC.
- Programme channel IDs can be matched without `<channel>` declarations.
  No display names are invented; existing exact-identity, duplicate-stream,
  provider, region, and manual-override rules remain in force. Channel IDs count
  toward the same channel/text budgets, including when declarations arrive later.

Regression coverage includes the real account guide-loader adapter, plain/gzip
programme-only feeds, malformed timestamps, parser bounds, cross-origin header
isolation, fallback request counts, refresh/client isolation, cancellation, and
a 4,001-channel multi-batch import retaining old listings while another source
continues working. Existing native Xtream behavior, partial-success publication,
playback recovery budgets, and permissive name/case matching are unchanged.

Owners: [XMLTV parser](../Sources/FeatureLiveTVCore/LiveTVXMLTVParser.swift),
[guide importer](../Sources/FeatureLiveTVCore/LiveTVServerGuideImport.swift),
[IPTV client](../Sources/ProviderIPTV/IPTVClient.swift), and
[provider](../Sources/ProviderIPTV/IPTVProvider.swift).

## Controlled playback results

Initial continuity/capacity hosted runs on 2026-10-20 used tvOS 26.2
(Apple TV 4K simulator), iOS 26.2
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

That pass's targeted package run completed 1,229 passing tests, nine skips, and
one failure in the unchanged
`PlayerSkipMarkerTrackTests.testFlatPerformanceTrackPairsItsSurfaceWithTheAppAppearance`
pixel-equality assertion. All 126 IPTV tests passed (six additional skips).
The unrelated rendering failure was reproduced on a second run and left outside
this work; the package run is not a full green result. The earlier six-module
run additionally exercised CoreModels, FeatureLiveTVCore, EnginePlozzigen, and
MediaTransportHTTP; its new refusal-body timing fixture was corrected and rerun.

### Recovery-credit and response-classification follow-up

The subsequent tvOS and iOS hosted runs each completed 21 passing tests, zero
failures and the same one opt-in real-relay skip. The new HTTP-200 HTML, JSON,
XML and empty-body cases reached the real player as typed failures with factual
messages and exactly one origin request per case. The rolling media, guide
failure, redirected-session and disconnect cases also continued to pass.
Healthy fMP4 again presented 899 changing images over 60 seconds on both
platforms; raw-disconnect recovery's longest image gap was 5.14 / 2.98 seconds.
These remain bounded simulator observations with muted audio, not uninterrupted
hours-long playback claims.

Both new policy defects were reproduced before their fixes. The final
player/provider package rerun completed 1,248 passes, nine skips and only the
same pre-existing rendering assertion failure above. CoreModels and
EnginePlozzigen passed in the preceding candidate run. Five-minute credit uses
injected monotonic time and explicit progress/interruption cases; it is not
substituted for a real-provider soak. No engine or dependency revision changed.

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

## Comparative reliability audit

The additional references below were inspected at pinned revisions, against
Plozz's corresponding implementation and existing regression coverage. This is
source-level comparison, not an independent runtime qualification of those apps.
Stars indicate visibility and interest, not correctness: evaluate the specific
behavior, failure cases, tests, maintenance and fit with Plozz instead.

### Lume

[Lume](https://github.com/bilipp/Lume) was inspected at
`a1edf063efafddbc39f6588ab1403b683a807b17`. Its
[retry controller][lume-retry] coalesces duplicate failures and uses bounded
backoff, with a slower schedule for overloaded sources. Its LumeEngine host
[resets that budget on a playing-state recovery][lume-recovered].
Plozz keeps its existing refusal/Retry-After handling and requires five minutes
of sustained observed progress before replenishing automatic retunes; a brief
return to playing is not enough.

Lume's [startup watchdog][lume-failures] extends its initial deadline when
downloaded bytes advance, while retaining a hard cap. This is a candidate for
future measured slow-source work, not a reason to increase Plozz's startup
timeout without a reproduction. The same file permits a new session to open
after a two-second shutdown grace even if the old one has not closed.
Do not copy that tradeoff into Plozz's single-connection IPTV lease handling.

Its [session-health tracker][lume-health] distinguishes unmeasured/short sessions
from healthy ones; it gates review prompts rather than controlling playback.
The useful lesson is evidence quality, not adding another playback watchdog.
These comparisons add no engine, protocol, dependency or telemetry. Lume uses
[AGPL-3.0][lume-license]; the Plozz changes are independently implemented, not
transplanted source.

### AerioTV

[AerioTV](https://github.com/jonzey231/AerioTV) was inspected at
`c3a5334830a8e49d3d4adf1e1dff11f5c21a078b` (GPL-3.0).
Its [player refusal handling][aerio-refusals] latches a provider stop until
manual Retry and retires scheduled reconnects on a new tune. Those principles
already match Plozz's terminal lease failures and recovery-generation guards;
do not add a parallel retry controller.

Its handling of a player-reported unknown format confirms the value of
distinguishing provider documents from bad media. However, its diagnostic
probe makes another ranged GET and can record response text. Plozz instead
classifies the existing response's bounded prefix, preserves the actual
status, and records only fixed classifications. Keep that safer connection and
privacy boundary rather than copying the probe.

AerioTV's [playlist/guide loading][aerio-guides] downloads to files and parses
incrementally, including gzip feeds. Plozz already incrementally imports M3U,
streams bounded XML/gzip parsing, limits retained guide data, and rejects
malformed documents rather than publishing a parser's partial result
(`LiveTVXMLTVParser.parseXML`). The authenticated provider guide download still
materializes a bounded `Data` and may repeat parsing across batches
(`IPTVClient.downloadGuideData`). File-backed download and refresh-scoped
successful parse reuse remain measurement candidates, not a reason to relax
size limits or change partial-guide publication.

### OrivioTV Apple TV

[OrivioTVAppleTV](https://github.com/prehakanson-art/OrivioTVAppleTV) was inspected
at `5e4c904f165238fff3181f87cdc48bf426007552` (GPL-3.0). Its Stremio-addon and
multi-engine architecture makes it an adjacent playback reference, not proof
of parity with Plozz's authenticated IPTV providers.

Its [stall handling][orivio-stalls] avoids rearming on identical buffering
notifications and rechecks pause/exit/loading conditions when a watchdog fires.
Its [progress handling][orivio-progress] also distinguishes a timer firing from
a playhead advancing. These are useful failure cases, not missing Plozz
features: `LiveChannelPlayerModel` retains the buffering start until activity
ends, checks current pause/suspension/generation before retuning, and keeps
startup bounded until the engine reports a first frame. The new recovery credit
additionally requires observed progress. Preserve the engine's authoritative
typed phase instead of importing another clock-derived playback state machine.
YouTube page extraction and extra playback engines remain outside this work.

### IPTVnator

[IPTVnator](https://github.com/4gray/iptvnator) was inspected at
`9c5bbf628d070a8fe16b0d624a04e94e9782116f` (MIT). Its TypeScript/Electron stack
does not prevent useful comparison of retry policies and data ownership; its
platform/decoder mechanics are not drop-in Apple-platform implementations.

The [embedded MPV reconnect policy][iptvnator-reconnect] and
[regression tests][iptvnator-reconnect-tests] preserve spent attempts through
brief recoveries, replenish after a stable playing interval, and cancel/disarm
on explicit pause. This independently supports the current hardening direction.
Its six attempts and 30-second playing-state threshold are not adopted: Plozz
keeps three spaced retunes and requires five minutes of observed advancing
playback, with interruptions and sample gaps invalidating credit.

Its [guide source generations][iptvnator-generations] and
[worker lifecycle][iptvnator-fetch] retire obsolete imports, reject late
messages, and wait for worker termination on timeout before advancing the queue.
Plozz already checks source revision, account authorization and cancellation
after provider work before publishing (`LiveTVServerGuideImport`), and its
indexed-cache regression verifies a malformed replacement preserves the prior
guide generation. Keep those boundaries; cancellation must not become success,
and a source removed during refresh must not reappear.

The next justified investigation remains large-guide download/parse cost and
longer fault-injected playback/lifecycle coverage, not more retries or a new
engine. Source inspection alone does not demonstrate that either requires a
production behavior change.

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
[lume-retry]: https://github.com/bilipp/Lume/blob/a1edf063efafddbc39f6588ab1403b683a807b17/Lume/Views/Player/PlaybackRetryController.swift
[lume-recovered]: https://github.com/bilipp/Lume/blob/a1edf063efafddbc39f6588ab1403b683a807b17/Lume/Views/Player/LumeEngineCoordinator.swift#L426-L435
[lume-failures]: https://github.com/bilipp/Lume/blob/a1edf063efafddbc39f6588ab1403b683a807b17/Lume/Views/Player/LumeEngineCoordinator+Failures.swift
[lume-health]: https://github.com/bilipp/Lume/blob/a1edf063efafddbc39f6588ab1403b683a807b17/Lume/Services/Diagnostics/PlaybackHealthTracker.swift
[lume-license]: https://github.com/bilipp/Lume/blob/a1edf063efafddbc39f6588ab1403b683a807b17/LICENSE
[aerio-refusals]: https://github.com/jonzey231/AerioTV/blob/c3a5334830a8e49d3d4adf1e1dff11f5c21a078b/App/MPVPlayerView.swift#L2231-L2355
[aerio-guides]: https://github.com/jonzey231/AerioTV/blob/c3a5334830a8e49d3d4adf1e1dff11f5c21a078b/Networking/PlaylistParsers.swift
[orivio-stalls]: https://github.com/prehakanson-art/OrivioTVAppleTV/blob/5e4c904f165238fff3181f87cdc48bf426007552/OrivioTV/Player/PlayerViewModel.swift#L937-L1029
[orivio-progress]: https://github.com/prehakanson-art/OrivioTVAppleTV/blob/5e4c904f165238fff3181f87cdc48bf426007552/OrivioTV/Player/PlayerViewModel.swift#L2062-L2114
[iptvnator-reconnect]: https://github.com/4gray/iptvnator/blob/9c5bbf628d070a8fe16b0d624a04e94e9782116f/apps/electron-backend/src/app/services/embedded-mpv-reconnect.ts#L274-L327
[iptvnator-reconnect-tests]: https://github.com/4gray/iptvnator/blob/9c5bbf628d070a8fe16b0d624a04e94e9782116f/apps/electron-backend/src/app/services/embedded-mpv-reconnect.spec.ts#L157-L180
[iptvnator-generations]: https://github.com/4gray/iptvnator/blob/9c5bbf628d070a8fe16b0d624a04e94e9782116f/apps/electron-backend/src/app/events/epg-source-generation.ts
[iptvnator-fetch]: https://github.com/4gray/iptvnator/blob/9c5bbf628d070a8fe16b0d624a04e94e9782116f/apps/electron-backend/src/app/events/epg-fetch-operation.ts#L84-L153
