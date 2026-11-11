# Local Simulator

Rules-derived C++17 physics core with Ruby tooling for local bot matches and
captured-game validation. No referee source was retrieved. Requires a C++17
compiler (`clang++` by default, configurable through `CXX`) and Ruby 2.6 or newer.
Only standard libraries are used. Binaries are compiled into temporary directories
and removed after each command.

## Run Local Bots

From the project root:

```sh
ruby simulator/run.rb match \
  --bot0 bots/bronze_bot/main.cpp \
  --bot1 bots/wood_bot/main.cpp \
  --seed 7 --ships 3 --output /tmp/caribbean-match.json
```

Each bot argument accepts either C++ source or an executable path. The bot uses
the normal CodinGame stdin/stdout protocol and stays alive throughout the match.
Bot paths are executed directly, not interpreted as shell commands. Other
languages can participate through an executable with an appropriate shebang.

Bot inputs include friendly ships first, in ascending entity-ID order, all enemy
ships and barrels, cannonballs still in flight, and mines within distance less
than five of any friendly center. Each player receives one shared time budget
for its entire fleet: 1,000 ms on the first turn and 50 ms thereafter. Override
these with `--first-turn-ms` and `--turn-ms` for local experimentation. These
budgets measure local wall time, not CodinGame's hardware or CPU accounting.

Invalid output, missing lines, premature exit, and timeout cause forfeits. Bot
stderr is drained and bounded, and subprocess groups are terminated on cleanup.
Bots are local trusted programs: subprocess isolation is not a security sandbox.

The JSON summary reports scores, ranks, zero-based winner (`null` for a draw),
turn count, termination reason, and forfeits. Exit status is zero for a completed
match, including a loss or draw; forfeits and command errors return one. The
optional output file includes the initial state, every turn's commands, timings,
entity states, configuration, and bounded bot diagnostics.
Ranks are stable zero-based ordinal positions: equal scores produce `[0, 1]`,
matching captures, although equal total rum still produces a `null` winner.

## Initial Maps

`--seed` generates a reproducible symmetric local layout with one to three ships
per player, six mines, and twelve barrels. This generator follows the documented
map constraints but **does not reproduce CodinGame's seed-to-map algorithm**.
Seeds alone therefore do not establish initial-state fidelity.

For exactly the same initial entities as an arena game, use a captured replay:

```sh
ruby simulator/run.rb match \
  --bot0 bots/bronze_bot/main.cpp \
  --bot1 bots/wood_bot/main.cpp \
  --initial ../caribbean-games/coders-of-the-caribbean/games/919705948/replay.json \
  --output /tmp/caribbean-captured-layout.json
```

Only the initial entities are used in a local match; the bots choose new actions.
Changing actions naturally changes the outcome from that of the captured game.

## Fetch and Validate Games

```sh
ruby fetch_games/fetch.rb fetch --top 12 --limit 25 --interval 0.7 --output ../caribbean-games
ruby fetch_games/fetch.rb fetch --player GuyBol --limit 200 --interval 0.7 --output ../caribbean-games
ruby simulator/run.rb validate --archive ../caribbean-games \
  --mode both --report simulator/validation.json
```

`--archive` accepts a capture repository, its games directory, or one replay JSON
file. Validation decodes the replay's initial keyframe, then simulates continuously
without resetting from later expected states. It compares all ship identities,
owners, centers, orientations, speeds, rum, barrels, mines, cannonball identities,
targets, origins, flight times, and final scores and ranks. Sunk ships remain
inert display entries, matching captured views. Replay coordinates are decoded
from row/column into the bot's column/row convention.

Validation stops at the first discrepancy in each game, continues with other
games, and returns a nonzero exit status for any failure. Reports include missing
and unexpected entities, the failing turn and commands, compared turn counts,
capture SHA-256 hashes, and the physics-core hash. Renderer animations, text,
explosion effects, and byte-for-byte viewer serialization are not compared.

Three modes separate automatic navigation from physical simulation:

- `raw` (default): execute the original bot stdout, including `MOVE` conversion.
  This is the strict end-to-end check.
- `resolved`: replace only `MOVE` with the effective manual steering command
  already recorded in the corresponding captured keyframe. Other commands still
  come from bot stdout. This isolates physical simulation from automatic steering;
  it does **not** validate the implementation of `MOVE`.
- `both`: run both checks independently and report both. Any raw failure still
  makes the overall command fail.

## Current Fidelity

The checked-in `validation.json` records **1,407/1,407 games passing both strict
raw-command replay and resolved-action physics replay**, with 279,286 turn
comparisons across both modes. The archive grew from 23 games by fetching 384
additional unique captures, then another 1,000, including top-player games and
MOVE-heavy games.
The earlier raw-command result was 14/23; all original games now pass too.

The additional 1,000 games initially produced one mismatch, preserved in
`additional-1000-validation.json` with the pre-fix core hash. Game 919340579
exposed rotation-phase barrel pickup and mine splash ordering at the rum cap.
Each contact phase now collects barrels for all ships before checking mine
contacts. The formerly failing game passes all 137 turns without corrections
to simulated state; the full report above reflects this fix.

In the original 407-game MOVE corpus, MOVE was fitted on 336 training games:
all 2,433 observed decisions match. The
converter was then evaluated unchanged on 71 held-out games: all 685 decisions
match, as recorded in `move-validation.json`. `corpus.json` preserves the split
and capture hashes. All 23 original development games belong to training; new
games use a deterministic game-ID hash to allocate approximately 20% to holdout.
Held-out games were not used to select the MOVE rules.

The public rules describe MOVE only as a simplified algorithm. The inferred
implementation now accounts for stationary bearings, speed-dependent braking,
projected-center bearings, a turning penalty, and center-aware turn ties. Run the
direct decision check independently of physics:

```sh
ruby simulator/analyze.rb --archive ../caribbean-games --subset training
ruby simulator/analyze.rb --archive ../caribbean-games --subset holdout \
  --report simulator/move-validation.json
```

The analyzer also supports `--subset all` and `--manifest PATH`; contradictory
observations and mismatches return a nonzero exit status. Existing capture hashes
must remain unchanged. Preserve an untouched partition when tuning future rules;
once its failures influence a change, it is no longer independent evidence.

Captured comparisons identified and corrected center-only map boundary checks,
landing-frame cannonball retention, inert sunk-ship display, post-decay wreck rum,
speed-1 ship cancellation during a speed-2 movement stage, case-insensitive
commands, ordinal ranks for equal scores, and pickup-before-mine contact ordering.
Physics comparisons
include top-player games, mine placement, cannon fire, pickups, collisions, sinking,
and timeout elimination. **Passing this finite sample does not certify an exact
replacement for CodinGame or prove all unobserved interactions correct.** Map
generation and local timing retain the limitations described above. Regenerate
the reports after changing the core.

## Implementation and Tests

- `engine.hpp`: self-contained C++ state, geometry, two-stage movement, iterative
  collision cancellation, rotation, contacts, weapons, cooldowns, damage, and wrecks.
- `main.cpp`: persistent text-protocol adapter for the core.
- `replay.rb`: capture decoder, engine client, continuous comparisons.
- `match.rb`: map generation, visibility, subprocess control, local match logging.
- `run.rb`: compilation and command-line interface.
- `analyze.rb`: captured MOVE decisions, stable training/holdout assignment, and
  direct native-converter checks.

```sh
ruby simulator/test.rb
ruby simulator/run.rb --help
```

Tests compile the native regression suite and benchmark, then check reproducible
maps, entity IDs, bot visibility and input order, persistent engine reset, complete
matches and draws, mixed-case MOVE extraction and replay, invalid output, EOF,
timeout forfeits, and cleanup. Native tests cover capped barrel pickups followed
by another ship's mine splash in both ship iteration orders. Tests use
temporary files and no network. Capture validation is a separate integration
check because the data archive lives outside this repository.

The native benchmark measures repeated six-ship physics steps with barrels and
mines. It excludes compilation, Ruby replay decoding, JSON logging, and bot CPU
time, and is not an end-to-end match-throughput estimate.
