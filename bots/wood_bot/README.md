# Wood Bot: Wood 1

A standalone C++17 bot for the Wood 1 rules described in [the game rules](../../rules/rules.md). It coordinates up to three ships to collect rum, avoid known hazards, fire predictive cannon shots, and selectively lay mines. It still uses automatic `MOVE` navigation rather than later-league manual steering.

## Submit or Run

Submit the contents of [main.cpp](main.cpp) to CodinGame with C++ selected. No other files or external libraries are required.

From the repository root, build and run locally:

```sh
clang++ -std=c++17 -O2 -Wall -Wextra -Wpedantic bots/wood_bot/main.cpp -o /tmp/wood_bot
/tmp/wood_bot < turns.txt
```

The input file must contain complete turns in the game's input format. The bot prints one command per controlled ship per turn, flushes each command, and exits cleanly at end of input. The parser follows [the input boilerplate](../boilerplate.cpp), handles `SHIP`, `BARREL`, `MINE`, and `CANNONBALL` entities, and rebuilds the visible game state each turn.

Commands preserve the input order of friendly ships. Target history and cooldowns are keyed by ship ID, so losing a ship does not transfer its state to a surviving ship.

## Strategy

For every barrel, the bot estimates the time needed to reach it using hex-grid distance, the ship's three-cell footprint, heading, and speed. It then scores the barrel by the amount of rum it can use divided by the estimated travel time plus a small overhead.

- Prefer nearby barrels that do not require a large turn.
- Favor useful rum rather than rum that would exceed the 100-unit limit.
- Reduce a barrel's score if the opponent appears likely to arrive first.
- Strongly reduce the score of barrels estimated to be beyond the ship's remaining lifetime.
- Give the previous target a small bonus to avoid switching targets unnecessarily.
- Reconsider the target every turn, so collected barrels are not chased after they disappear.
- Penalize barrels on or near known mines and near cannonball impacts expected around arrival time.

### Fleet Allocation

The bot scores every ship-barrel pair, then searches the possible assignments to maximize the fleet's total score. Each barrel can be assigned to only one ship. Low-rum ships receive extra priority, so a healthy teammate is less likely to take their last reachable pickup. Ships can remain unassigned when barrels are scarce.

New barrels from sunken ships are treated like other pickups, using their actual rum quantity, including amounts up to 30. The bot does not assume that all barrels contain at most 20.

Assignment ties are resolved deterministically using input ship order and ascending barrel IDs. The values in the `Strategy` struct can be adjusted to compare strategy variants.

### Safety

Before moving, the bot estimates the next turn's path and final three-cell footprint. It checks mines along the path, mine explosions triggered by incoming cannonballs, direct shell damage, predicted ship collisions, and map boundaries.

Three planning passes let ships adjust to their teammates' projected movements. Friendly collision checks compare all three occupied cells at intermediate movement steps and after turning, not just the ships' centers. Combat actions are allowed only if coasting is also safe relative to the current fleet plan.

If the intended move is risky, it compares braking, coasting, and six nearby waypoints. Avoiding expected rum damage takes priority over reaching the barrel quickly. Cannonballs landing this turn matter most; those landing next turn receive a smaller risk penalty.

Seen mines remain in memory when they leave vision. A remembered mine is removed when its location is within any friendly ship's vision again but the mine is absent from the input.

### Cannon Fire

When maintaining the current speed and direction is predicted to be safe and still makes progress toward its assigned barrel, a ship can fire instead of navigating. An unassigned ship can also fire while stopped or coasting.

- Scan target cells within 10 hex steps of the bow.
- Compute the rounded flight time for each cell.
- Estimate opponent positions at impact under straight movement, slowing, and left/right turn scenarios. Straight movement receives the highest weight.
- Prefer expected damage, including mine detonations, and reject shots that would hit a friendly ship under the current plan and subsequent forecasts.
- Discount damage already covered by friendly shells arriving no later than the proposed shot. Newly chosen shots are immediately shared with the rest of the fleet, reducing overkill while allowing useful focus fire.
- Fire only when the expected damage reaches the configured threshold.
- After a ship fires, skip its next turn before firing again; other ships keep their own cooldowns.

### Mine Placement

If a ship is not firing and can safely maintain its course, it considers dropping a mine behind its stern. It only does so when an opponent's projected path touches that cell within two turns and friendly projected positions are clear of the blast.

The drop cell must be on the map and free of ships, barrels, and known mines. Newly placed mines are immediately shared with the fleet and added to memory. After a drop, that ship waits through the next four turns before another attempt. It does not scatter mines indiscriminately.

When a ship has no assigned barrel and neither combat action is selected, it normally uses `SLOWER` until stopped, then `WAIT`. Safety checks can select another action to avoid a hazard or teammate.

## Geometry and Limits

The geometry uses offset hex coordinates with odd-numbered rows shifted right. Movement forecasts apply forward movement before rotation and stop at map boundaries.

Arrival times and automatic steering forecasts are heuristics, not an exact simulation of `MOVE`: the supplied rules do not specify its steering algorithm. Ship collision checks are conservative risk estimates, not the referee's iterative collision resolution. Fleet planning uses a fixed number of passes rather than proving that all actions are mutually collision-free. Opponents can change course, unseen mines can exist, and remembered mines may already have exploded out of sight. Safety checks therefore reduce risk but cannot guarantee avoiding damage.

For three ships and 26 barrels, target assignment considers at most 27 cubed combinations, including unassigned ships; duplicate barrel assignments are pruned. Navigation scores a bounded set of actions, and each eligible ship considers at most 483 firing cells. Enemy forecasts extend at most four turns for firing. No external dependencies are needed.

## Tests

Run the standard-library Ruby test script from the repository root:

```sh
ruby bots/wood_bot/test.rb
```

The script compiles into a temporary directory and runs:

- C++ assertions for hex geometry, damage, boundaries, fleet allocation, friendly collision and fire avoidance, shared mine vision, and mine-placement legality.
- Fixed transcripts for barrel selection, three-ship output order, scarce-rum allocation, 30-unit barrels, braking before mines, shell evasion, moving-target aim, range, shared shots, and cooldowns after a ship sinks.
- A 200-turn navigation transcript with 26 barrels and a 200-turn combat transcript with 10 mines.
- Two 200-turn fleet transcripts: three ships facing three opponents with barrels, mines, and incoming shells; and coordinated three-ship cannon fire. Each verifies 600 command lines.

Set `CXX` to select another C++ compiler.

These are synthetic checks, not matches: the repeated-turn load checks do not simulate movement or collection. They do not prove a win rate or promotion. Wood 1 qualification still needs validation against real CodinGame opponents or a referee validated with captured games.
