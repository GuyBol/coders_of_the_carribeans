# Local Arena

## Matches

- Use the simulator to run local matches between bots in the `bots` folder.
- Organize games fairly among participating bots, similarly to the CodinGame arena.
- For example, ensure that each pair of bots plays the same number of games as player 1 and player 2.

## Ranking

- Rank bots using an Elo-like rating system, similar to CodinGame's.

## Game Captures

- Capture games in the same format used by `fetch_games`.
- Save local captures in a dedicated folder, separate from CodinGame arena captures, so their local origin remains clear.

## Performance

- The simulator should support running games in parallel to maximize the number of games played in the shortest time.

## Architecture

- Keep the arena loosely coupled to the simulator. Integrate the simulator as a replaceable plugin so the arena code can be reused for another game.
- Define a generic interface between the arena and game-specific UIs so a different UI can be plugged in for another game.

## Visualization

- A visualization, developed later in a separate folder, could be used to display arena games.

## Documentation

- Generate a README with documentation and usage instructions.
