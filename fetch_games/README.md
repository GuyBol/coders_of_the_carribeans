# Fetch Coders of the Caribbean Games

Dependency-free Ruby script for discovering public arena players and archiving
their recent games. Ruby handles HTTP, JSON, and filesystem work; the bots remain
standalone C++. Requires Ruby 2.6 or newer with its standard libraries and working
TLS certificates. No account credentials or authentication cookies are needed.

Run the following commands from the project root.

## Player Lookup

```sh
ruby fetch_games/fetch.rb leaderboard --limit 10
ruby fetch_games/fetch.rb lookup --player Daporan
ruby fetch_games/fetch.rb lookup --user-id 1452472
ruby fetch_games/fetch.rb lookup --handle 189ceb936f80d641d8245553f46fdac72742541
```

Lookup accepts your own account just like another player's account. Nicknames
must match exactly, ignoring case; partial or ambiguous search results are not
silently selected. Lookup prints the nickname, user ID, public profile handle,
arena agent ID, rank, and league when available. A profile with no arena entry
has a null agent ID; submit a bot to the arena or supply a known agent ID.

The public leaderboard currently returns at most 1,000 players. Profile lookup
also checks the personalized `codingamerUserRank` entry rather than relying on
membership in that list. Leaderboard keyword filters were ignored in live probes
and are deliberately not exposed.

## Capture Games

Pass the path to your dedicated game-data repository or archive with `--output`.
It is created if needed. The script does not initialize Git, commit data, or add
captures to this bot repository automatically.

```sh
ruby fetch_games/fetch.rb fetch --player Daporan --limit 5 --output ../caribbean-games
ruby fetch_games/fetch.rb fetch --user-id 1452472 --limit 5 --output ../caribbean-games
ruby fetch_games/fetch.rb fetch --agent-id 6797473 --limit 5 --output ../caribbean-games
ruby fetch_games/fetch.rb fetch --top 10 --limit 20 --output ../caribbean-games
ruby fetch_games/fetch.rb fetch --game-id 919705948 --output ../caribbean-games
```

Choose exactly one player, user ID, profile handle, agent ID, top-player count,
or game ID. `--limit` defaults to 20 games per player. Only completed games are
selected, in the order returned by the recent-battles service. Duplicate game
IDs, including games shared by selected players, are downloaded once per run.
Existing valid captures are skipped; the limit includes these skipped games.
This retrieves the service's available recent history, not every game ever
played, and does not invent pagination for older games.

Add `--refresh` to replace existing captures. Downloads and JSON writes complete
in a temporary sibling directory before an existing capture is replaced. A failed
download leaves the previous capture intact. Invalid or incomplete local captures
produce an error instead of being silently skipped; use `--refresh` to repair them.
Use one writer per archive directory at a time.

Progress goes to standard error. Standard output contains JSON: lookup results,
leaderboard rows, or a fetch summary with `saved`, `skipped`, `failed`, and
`errors`. Partial failures do not stop remaining games; the exit status is 1 if
any game or player failed, otherwise 0. A player with no completed recent games
produces a successful summary with zero downloads.

Requests are spaced at least 0.5 seconds apart by default. Change this with
`--interval SECONDS`; keep polling and batch sizes modest. HTTP 429 and 5xx
responses are retried twice with backoff; numeric `Retry-After` delays are capped
at 30 seconds. Network timeouts, expired games, access restrictions, invalid
JSON, and changed response schemas are reported as errors. TLS verification is
always enabled; fix your Ruby/OpenSSL certificate configuration rather than
disabling verification.

## Archive Layout

```text
caribbean-games/
  coders-of-the-caribbean/
    games/
      919705948/
        replay.json
        metadata.json
```

- `replay.json` preserves the complete decoded API response, including all frames,
  available views, bot output, referee input, scores, ranks, and agent data. JSON
  is pretty-printed; it is not a byte-for-byte HTTP response capture.
- `metadata.json` records schema version, puzzle and game IDs, UTC capture time,
  replay URL, frame count, referee input, requesting player, original battle
  listing entry when available, and normalized player identities and results.
- Players are matched to battle entries by agent ID. Scores and ranks use each
  replay agent's index, not the order of the battle listing. Public handles are
  nullable for direct game downloads when the replay does not provide them.

Replay frames are stored unchanged, not interpreted into simulator turns yet.
This preserves evidence for later referee validation without claiming that the
local referee has already been validated. Fetching an already captured game for
another player does not merge metadata; refresh explicitly when needed. Raw
replays may include bot debug output and public account identifiers, so review
captures before publishing or sharing your data repository.

## API Endpoints

These undocumented JSON POST services were verified against public responses:

| Service under `https://www.codingame.com/services/` | JSON argument array |
| --- | --- |
| `Search/search` | `[nickname, "en", null]` |
| `CodinGamer/findCodinGamerPublicInformations` | `[userId]` |
| `CodinGamer/findCodingamePointsStatsByHandle` | `[publicHandle]` |
| `Leaderboards/getFilteredPuzzleLeaderboard` | `["coders-of-the-caribbean", publicHandleOrNull, "global", {}]` |
| `gamesPlayersRanking/findLastBattlesByAgentId` | `[agentId, null]` |
| `gameResult/findByGameId` | `[gameId, null]` |

Profile request definitions were cross-checked against the public
[codingame API client](https://github.com/takos22/codingame), then tested against
the service. No game referee source was retrieved. These services are not a
supported API contract and may change or become unavailable. The captured
`refereeInput` can contain the generation seed and initial configuration; the
script does not guess missing values or synthesize missing frames.

## Tests and Library Use

```sh
ruby fetch_games/test.rb
ruby fetch_games/fetch.rb --help
```

Tests are offline, use temporary directories, and require no packages. They
cover RPC payloads, bounded retries, response validation, exact nickname and
user-ID lookup, personalized ranking, identity/result mapping, raw-data retention,
resume, corrupt captures, safe refresh, duplicate games, and partial failures.

For Ruby automation, require `fetch_games/api.rb` or `fetch_games/archive.rb`,
then use `FetchGames::Client` and `FetchGames::Archive`. Library calls raise
`FetchGames::Error` for API failures. The CLI entry point is
`FetchGames::CLI.run(arguments)`, returning an exit code.
