# Nuvio

Optional, profile-scoped watch-progress sync with [Nuvio](https://nuvio.tv).
When a movie or episode is paused or stopped in Plozz, its resume point is
written to the linked Nuvio profile, so Nuvio's Continue Watching (phone, TV,
web) continues from where Plozz left off.

## Configuration

Set `NUVIO_ANON_KEY` in the ignored `Config/Secrets.local.xcconfig`. It is the
public Supabase anon key of `api.nuvio.tv`; it grants nothing without a signed-in
session. Empty hides the Nuvio row in Settings.

## Sign-in

Nuvio's TV login: Plozz opens an anonymous session, starts a login
(`start_tv_login_session`) and shows its QR and code. The user approves on
nuvio.tv; Plozz polls (`poll_tv_login_session`) and exchanges the approved code
(`/functions/v1/tv-logins-exchange`) for a session. No password enters Plozz.

The session lives in the Keychain per Plozz profile and, unlike the other
trackers, is **device-local**: Supabase rotates the refresh token on each use and
revokes a session whose old token is replayed, so an iCloud-synced copy would
sign devices out of each other.

Progress is written to one Nuvio profile. The first profile is chosen after
sign-in; Settings offers a choice when the account has several.

## What is sent

`sync_push_watch_progress` with the row shape Nuvio's own apps use: IMDb id (or
`tmdb:<id>`) as `content_id`, the **series** id for episodes, key `<id>` or
`<id>_s<S>e<E>`, millisecond position/duration/time, and a per-install
`p_origin_client_id` prefixed `plozz-`. At 90 % the position is set to the full
duration so Nuvio treats the title as finished. Media without such an id or
without a runtime (home videos, live TV) is skipped.

Only pause and stop write; there is no now-watching call. A 429 pauses writes
for at least 15 minutes. Failures never reach playback.

## Not yet

Pulling Nuvio progress or library into Plozz, and syncing the Nuvio library with
the universal watchlist.
