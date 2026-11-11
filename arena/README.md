# Local Arena

Ruby standard-library tournament runner with a replaceable game plugin. The
included Coders of the Caribbean adapter uses the existing C++17 simulator.
Requires Ruby 2.6 or newer and a C++17 compiler (`clang++` by default, configurable
with `CXX`). No packages or network access are needed.

## Quick Start

From the project root:

```sh
ruby arena/run.rb list
ruby arena/run.rb run --rounds 5 --workers 2 --seed 7
```

Discovery selects each `**/main.cpp` below `bots`, currently the independently
versioned Wood and Bronze bots. The top-level boilerplate is not selected.
`--bots DIR` changes the discovery root. Explicit `--bot NAME=PATH` entries
replace discovery; repeat the flag to select C++ sources or executable programs:

```sh
ruby arena/run.rb run \
  --bot bronze=bots/bronze_bot/main.cpp \
  --bot wood=bots/wood_bot/main.cpp \
  --rounds 3 --workers 2 --seed 42 \
  --option ships=3 --option turn_ms=100 \
  --output arena/runs/experiment-001
```

Names may contain letters, numbers, underscores, dots, and dashes. Executable
programs are invoked directly, without a shell, and may use a shebang for another
language. Bot programs are trusted local code, not sandboxed processes.

To run just one game, in the supplied player order:

```sh
ruby arena/run.rb match \
  --bot bronze=bots/bronze_bot/main.cpp \
  --bot wood=bots/wood_bot/main.cpp \
  --seed 7 --output arena/runs/single-001
```

Single-match mode requires exactly two bots and one round. Use `run`, not
`match`, for seat-balanced comparisons.

## Scheduling and Ranking

A tournament contains `rounds * bots * (bots - 1)` games. Every pair plays both
player positions on the same captured map in each round, selected using the same
match seed. The next pair or round receives the next seed. A fixed bot order,
round count, starting seed, and catalog produce the same schedule and maps.
Positions are zero-based in results: player 0 and
player 1 correspond to the first and second bot in `players`.

Elo starts at 1500 with K=32, configurable with `--initial-rating` and `--k`.
Wins score 1, draws 0.5, and losses 0; a draw follows the plugin's `winner: nil`,
not an ordinal rank tie. Ratings are applied in scheduled match-ID order, never
worker completion order. This is a conventional Elo-like system, not a claim to
reproduce CodinGame's proprietary rating algorithm. Each tournament starts fresh;
ratings are not carried forward automatically.

Rankings include games, wins, draws, losses, forfeits, and per-position counts.
Bot forfeits count as match outcomes. Engine, plugin, and capture-write failures
are recorded separately and excluded from Elo; they can leave the successful
subset unbalanced. Other scheduled games still run.

Progress is written to stderr and a JSON summary to stdout. Exit status is zero
only when every game completes without engine errors or bot forfeits. Both
forfeit and infrastructure failure counts appear explicitly in the summary.

## Captured Maps

Caribbean arena games use only existing CodinGame initial layouts, never
synthetically generated maps. The bundled `maps/caribbean.json` catalog contains
**1,407 distinct maps extracted from 1,407 public captured games**:

| Ships Per Player | Captured Maps |
| --- | --- |
| 1 | 476 |
| 2 | 496 |
| 3 | 435 |

The catalog preserves initial ship positions, owners, orientations, speeds, rum,
entity IDs, mine positions, barrel positions and rum amounts, and the original
map header. Each map has an initial-state SHA-256 ID and source game IDs and
capture hashes. Identical initial states are deduplicated while retaining their
source references. No downloaded replay archive is needed at runtime.

The arena seed selects a catalog entry; it does not recreate CodinGame's
seed-to-map algorithm. Selection uses replacement, so different seeds can select
the same map. Changing the catalog may change selected layouts; captures record
the catalog hash to make this distinction explicit. Home/away games always use
the exact same initial state. Only bot actions and resulting outcomes are new.

Rebuild the catalog from the public replay archive after capturing more games:

```sh
ruby arena/plugins/caribbean_maps.rb --archive ../caribbean-games
```

The builder rejects locally generated replays and validates initial states.
`--output FILE` writes another catalog. A custom catalog can be selected with
`--option 'maps="/path/to/catalog.json"'`. Missing, invalid, or fleet-incompatible
catalogs cause an error; there is no fallback to generated maps. A default mixed
fleet run requires maps for all three fleet sizes; a fixed-size run needs only
the requested size.

## Parallelism and Timing

`--workers N` runs up to N independent games concurrently (default 2; range
1-64). The Caribbean plugin compiles the engine, native MOVE-resolution probe,
and each C++ bot once per tournament into a temporary directory, removed after
workers finish. Each game uses separate engine and persistent bot processes.

Adapter settings use repeatable `--option KEY=JSON` flags:

| Caribbean Option | Default | Meaning |
| --- | --- | --- |
| `ships` | Seeded random | Uniform choice of 1, 2, or 3 ships, then a captured map with that fleet size |
| `maps` | Bundled catalog | Path to a captured-map catalog JSON file |
| `turn_ms` | `50` | Shared per-player wall-time budget per turn |
| `first_turn_ms` | `1000` | Shared first-turn budget per player |

When `ships` is omitted, a fresh `Random.new(seed)` uniformly chooses 1, 2, or 3
ships per player, then uniformly selects a captured map from that fleet-size
pool. Both players receive the original fleets. Selection is independent of
worker completion order and does not mutate shared random state. Uniform
selection does not guarantee equal counts of each size in a short tournament.
An explicit `--option ships=1`, `ships=2`, or `ships=3` filters the catalog to
that size; it never adds, removes, or repositions ships on an existing map.

High worker counts can cause timeout forfeits through CPU contention. Use one
worker for timing-sensitive comparisons, or explicitly increase budgets for
parallel strategy experiments. Local wall time is not CodinGame CPU accounting.

## Captures and Results

By default, each run creates a unique directory under `../local-arena-games`,
separate from the public `../caribbean-games` archive. `--output` chooses another
new directory; existing paths are rejected rather than overwritten or resumed.
The optional `arena/runs` location is Git-ignored.

```text
RUN/
  tournament.json
  coders-of-the-caribbean/
    games/
      1/
        replay.json
        metadata.json
        match.json
      2/
        ...
```

`replay.json` and `metadata.json` use the fetched-game JSON envelope and keyframe
conventions. Captures contain agents, stdout, frames, scores, ranks, and decoded
entity views; effective MOVE commands are resolved by the native core. Forfeit
frames identify disqualified players. These files round-trip through the
simulator replay validator in both original-command and resolved-MOVE modes.
Renderer-specific animations and byte-for-byte CodinGame viewer output are not
reproduced, and local files are not advertised as hosted CodinGame replays.

Every replay and metadata record is marked `origin: "local"` and carries a
tournament UUID. Metadata has no public replay URL or claimed public user ID;
it records the selection seed, chosen fleet size, core hash, and bot source
hashes. The `source_map` object in replay, metadata, and match configuration
records the map ID, original source game ID, source capture hash, original map
seed, and catalog hash. These identify the real initial layout, not a claim that
the newly played local game happened on CodinGame. Match IDs are unique within a
tournament, not across runs; retain the run directory or UUID when combining
results.

`match.json` contains the simulator's complete initial state and turn-by-turn
states, actions, timings, forfeits, and bounded bot stderr. `tournament.json`
contains configuration, source hashes, the entire planned schedule, completed
matches, failures, and rankings. It is atomically updated after each completed
game; captures are staged in temporary directories before publication. A crash
can leave an incomplete run, but does not intentionally overwrite another run.

```sh
ruby arena/run.rb results --input arena/runs/experiment-001
ruby simulator/run.rb validate --archive arena/runs/experiment-001 --mode both
ruby arena/run.rb --help
```

## Game Plugin Contract

The scheduler, workers, Elo, and archive publication do not import the simulator.
Only the Caribbean plugin and its map-catalog helper know Caribbean state,
simulator calls, or keyframe encoding. Select another trusted Ruby adapter with
`--plugin FILE`.

A plugin file defines `class Plugin`, loaded in an isolated Ruby module, with:

- `game`: a lowercase, filesystem-safe game identifier.
- `prepare(bots:, directory:, options:)`: called once; compile or resolve bot
  paths and prepare shared read-only resources in the supplied temporary folder.
- `play(players:, seed:, match_id:)`: called concurrently; return a result hash.
  Each call must use independent mutable match state and clean up its processes.

The result uses symbol keys:

```ruby
{
  scores: [10, 5], winner: 0, reason: 'finished',
  forfeits: [],
  replay: {'frames' => [...]},
  metadata: {'schema_version' => 1},
  details: {}
}
```

Scores must be two finite numbers. Winner is player index 0 or 1, or nil for a
draw. Forfeits are hashes with `player: 0` or `player: 1`, optionally including
turn and error information. Replay and metadata use string keys; their
game-specific contents and compatibility are the adapter's responsibility.
`details` is an optional JSON object for detailed analysis. Exceptions mark a
match as failed without aborting unrelated games. Plugins are trusted code,
not a security boundary.

## Visualization

Start the read-only local replay viewer from the project root:

```sh
ruby arena/visualization/server.rb
```

Open the printed URL, normally <http://127.0.0.1:8765>. The viewer discovers runs
under `arena/runs` and `../local-arena-games`. It provides tournament standings,
game filtering, play/pause, frame stepping, a timeline, direct turn selection,
playback speed, ship inspection, and per-turn orders. Desktop and mobile layouts
are supported. See [the visualization guide](visualization/README.md) for custom
archive roots, dependencies, tests, and adding another game renderer.

The UI reads schema-version-1 `tournament.json`. Each successful match has
a `view` object with `interface_version: 1`, a `game` identifier, and `replay`,
`metadata`, and `details` paths relative to the run directory. The UI selects a
game-specific renderer by `game`; it does not depend on the simulator or Ruby
worker implementation. Replay frames supply the game-specific timeline.
Failed matches have an `error` instead of replay references. This keeps both
the game engine and visualization replaceable without changing scheduling or
ranking code.

## Tests

```sh
ruby arena/test.rb
```

Offline tests cover balanced scheduling, captured-map pairing, seeded fleet
selection, fixed fleet filters, catalog deduplication and integrity, exact
initial-state preservation and provenance, deterministic Elo,
draws, forfeits, bounded parallel execution with an unrelated fake game plugin,
engine failure isolation, archive protection, generic UI references, CLI
results, single matches, and real persistent-bot captures. Tournament capture
fixtures are replayed in both validation modes. Temporary test data is removed.
