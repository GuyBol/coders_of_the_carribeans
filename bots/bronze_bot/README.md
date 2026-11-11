# Bronze Bot

A standalone C++17 bot for the [Bronze rules](../../rules/rules.md), derived from [the Wood bot](../wood_bot/README.md). It retains the Wood bot's parsing, hex geometry, fleet barrel allocation, mine memory, and coordinated combat policies. Its new navigation planner uses manual commands and a bounded forward model instead of estimating automatic `MOVE` steering. The Wood bot remains a separate version.

## Submit or Run

Submit the contents of [main.cpp](main.cpp) to CodinGame with C++ selected. No other source files or external libraries are required.

From the repository root:

```sh
clang++ -std=c++17 -O2 -Wall -Wextra -Wpedantic bots/bronze_bot/main.cpp -o /tmp/bronze_bot
/tmp/bronze_bot < turns.txt
```

The input file must contain complete game turns. The bot reads the entire turn, prints and flushes one command for each friendly ship in input order, and exits cleanly at end of input. It uses `FASTER`, `SLOWER`, `PORT`, `STARBOARD`, `WAIT`, `FIRE`, and `MINE`; it never emits `MOVE`.

## Fleet Strategy

The fleet assigns distinct barrel targets to maximize a shared score based on estimated travel time, useful rum, opponent proximity, hazards, and target stability. Low-rum ships receive extra priority. Barrels are valued using their actual contents, including up to 30 rum from sunken ships.

Seen mines remain in memory outside the fleet's vision. A remembered mine is removed when any friendly ship can see its location but the mine is absent. Targets and cooldowns are keyed by ship ID, so a sinking ship does not transfer its state to a teammate.

## Manual Navigation

Each ship searches four turns ahead using a beam of ten candidate states. It compares all five manual movement choices, pruning redundant acceleration or braking at the speed limits.

The forward model applies:

1. Rum consumption and speed changes.
2. Two movement stages, with border stops and iterative front-collision cancellation after each stage.
3. Barrel collection and immediate mine damage along the movement path.
4. Rotation after movement, with border and collision cancellation.
5. Contact checks after rotation, cannonball countdowns and impacts, and ship removal.

Search states retain consumed barrels and mines, so the same object cannot be collected or detonated repeatedly. Barrel ownership is recorded so a ship cannot receive a completion bonus for a teammate's pickup.

The evaluation favors survival, useful rum collection, and shorter remaining travel time. A terminal travel estimate guides routes beyond the search horizon. Two fleet-planning passes account for teammates' intended first-turn actions; commands are reconsidered before output to account for combat decisions already made by earlier ships.

## Combat

Cannon targeting is adapted from the Wood bot. The bot evaluates cells within 10 steps of the bow using rounded flight times and weighted forecasts for coasting, braking, turning either way, and accelerating. Friendly movement plans are considered when rejecting dangerous shots. Incoming friendly shots and newly selected shots reduce the value of redundant fire against the same opponent.

Firing and mine placement require coasting instead of steering. The planner therefore evaluates a second search constrained to `WAIT` on its first turn and permits combat only when this stays close to the best navigation score. It rejects forecasts in which the ship dies within the search horizon.

Mines are placed selectively behind the stern when an opponent is projected to cross the drop cell within two turns. The cell must be free of ships, barrels, and known mines, and friendly forecasts must stay clear of the blast. New mines are immediately shared with later ship decisions and added to memory.

After firing, that ship skips the next turn before firing again. After dropping a mine, it skips the next four turns before another drop.

## Configuration

The `Strategy` struct in the submission file exposes the main parameters:

| Parameter | Default | Purpose |
| --- | --- | --- |
| `search_depth` | 4 | Number of navigation turns simulated. |
| `beam_width` | 10 | Number of states retained at each search depth. |
| `planning_passes` | 2 | Fleet coordination passes before final decisions. |
| `rum_value` | 5.0 | Weight of collected rum and damage in navigation. |
| `minimum_shot_value` | 20.0 | Minimum estimated useful shot damage. |
| `combat_detour` | 2.0 | Allowed navigation-score loss to make a combat action. |
| `fleet_urgency` | 30.0 | Priority boost for low-rum ships. |

The remaining fields control travel estimates, target stability, and opponent competition. Increasing the search settings increases runtime; all ships share the game's 50 ms turn budget.

## Tests

Run the standard-library Ruby test script:

```sh
ruby bots/bronze_bot/test.rb
```

It compiles into a temporary directory with warnings enabled and checks:

- Manual speed changes, direction wrapping, movement before rotation, and turning while stopped.
- First-stage and second-stage collisions, cancellation cascades, rotation collisions, and map boundaries.
- Collection along the path, the rum cap, collection before elimination, mine contact and splash, and cannonball timing.
- Fleet allocation, barrel ownership, shared vision, friendly-fire rejection, and mine-placement safety.
- Closed-loop collection routes, including turning around, reaching a distant barrel, and a route with a mine.
- EOF handling, multi-ship output order, cannon and mine cooldowns, shot allocation, and cooldowns after a ship sinks.
- Streaming three-ship workloads with 26 barrels, 10 mines, and incoming shells, plus a separate fleet combat workload. These validate commands and report full-turn latency, including input and output.

Set `CXX` to select another C++ compiler.

## Validation Limits

The forward model is a planning aid built from the supplied rules, not a referee validated against captured CodinGame games. Tests of that model establish internal consistency, not absolute game fidelity. In particular, it does not create speculative barrels when forecast ships sink; real wreck barrels are read from subsequent game inputs.

Other ships are assumed to coast beyond their known first-turn plans during navigation search. Cannon targeting uses a few weighted scenarios, not a complete opponent policy. Unknown mines, unexpected actions, and changes made after a planning pass can invalidate forecasts. Fixed-width search can also discard useful longer-term routes.

Synthetic timing and route tests do not establish a win rate or promotion. Validate the submission in live Bronze games before treating it as a stronger baseline than the Wood bot.
