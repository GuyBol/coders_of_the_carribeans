# Bronze Rules, Simply Explained

This guide explains **Bronze** in **Coders of the Caribbean**. You still control **up to three ships**, but now you can choose speed changes and turns yourself. Ships can move **two cells per turn**, and collisions are checked after each step. Fleet, rum, cannonball, and mine rules still apply. See [the full rules](rules.md) for the detailed input format and constraints.

## The Goal

Keep your fleet supplied with rum for longer than your opponent.

- Each player can control **up to three ships** in this league.
- Every ship loses **1 unit of rum per turn**.
- A ship with no rum left is lost.
- Losing one ship does not end the game if you still have others.
- You win if your opponent loses all their ships. If the game reaches **200 turns**, compare the **total rum across each player's surviving ships**: more rum wins.

## Collecting Rum

Barrels are scattered around the map. The starting barrels contain **10 to 20 units of rum** each.

Your ship collects a barrel when any part of the ship passes over its cell during movement. You do not need a separate command to pick it up.

A ship can hold at most **100 units of rum**. Anything above that limit is wasted.

For example, collecting a barrel containing 15 units when you have 90 brings you to 100, not 105.

### Rum from Sunken Ships

When a mine or cannonball destroys a ship, a new barrel appears where it sank. It contains the rum held by that ship, capped at **30 units**. This rule specifically applies to ships destroyed by those weapons, not simply running out of rum.

## The Map and Your Ship

- The map is **23 cells wide and 21 cells high**.
- Cells are hexagons, so there are six possible directions to face.
- Odd-numbered rows are shifted. Distance is the smallest number of steps between neighboring cells, not straight-line distance on a square grid.
- Coordinates start at `(0, 0)` in the top-left corner.
- Your ship occupies three cells: its center, its front, and its back.
- Its speed is **0, 1, or 2**, meaning it moves that many cells forward each turn.

## Choosing an Action

Each turn, choose **one command for each ship you control**:

| Command | What it means |
| --- | --- |
| `MOVE x y` | Ask the ship to travel toward cell `(x, y)`. The game automatically handles steering and speed using a simplified algorithm. |
| `FIRE x y` | Shoot a cannonball at a cell. It arrives after a delay. |
| `MINE` | Drop a mine in the cell directly behind your ship. |
| `PORT` | Turn left after moving forward. Keep the same speed. |
| `STARBOARD` | Turn right after moving forward. Keep the same speed. |
| `FASTER` | Increase speed by 1, up to 2. |
| `SLOWER` | Reduce speed by 1, down to 0. |
| `WAIT` | Keep the current speed and direction. |

**`WAIT`, `FIRE`, and `MINE` do not stop your ship.** It keeps its previous speed and direction when you use them.

**`MOVE` does not teleport the ship.** It may take several turns to reach the destination.

For example, `MOVE 12 8` asks your ship to head toward the cell at column 12, row 8.

If you control three ships, print three command lines. Match the order of your ships in the input, which is ascending ship ID order. For example:

```text
MOVE 12 8
FIRE 15 10
WAIT
```

The first command belongs to your first ship in the input, the second to your second ship, and the third to your third ship. If a ship is lost, the next turn needs fewer command lines.

## Steering Manually

`MOVE` still handles navigation automatically. The new manual commands let you make more precise decisions, but each ship can use **only one command per turn**. You cannot send both `FASTER` and `PORT` to the same ship on the same turn.

- `FASTER` and `SLOWER` change how far the ship moves **this turn**.
- `PORT` and `STARBOARD` change the heading **after this turn's forward movement**. The ship travels along the new heading on following turns.
- Speed 0 means no forward movement, but the ship can still turn.

For example, a ship moving right at speed 2 that receives `PORT` moves two cells to the right, then turns to face top right. It does not move diagonally during that turn.

See [the movement diagram in the full rules](rules.md#manual-steering) for the illustrated example.

## Shooting Cannonballs

- Aim at a cell within **10 hex-grid steps of your ship's front**, not its center.
- A cannonball takes **1 + distance / 3 turns**, rounded to the nearest whole number, to arrive.
- Hitting the center of a ship costs that ship **50 rum**. Hitting its front or back costs **25 rum**.
- After a ship fires, that ship cannot fire on the next turn. Your other ships have their own cooldowns.

For example, a shot at a cell 6 steps from your ship's front takes 3 turns to arrive. Since ships move before impacts are resolved, aim where the opponent will be, not necessarily where it is now.

## Mines

The map starts with **5 to 10 mines**, and ships can add more using `MINE`.

- Touching a mine triggers an immediate explosion and costs the touching ship **25 rum**.
- A ship next to an exploding mine loses **10 rum**.
- A cannonball can also trigger a mine.
- You can only see a mine if it is **fewer than 5 steps from the center of at least one of your ships**. Exactly 5 steps is not close enough unless another ship is nearer.
- After a ship drops a mine, that ship cannot drop another for the next **4 turns**. Each ship has its own cooldown.

Not seeing a mine does not mean the path ahead is safe.

## Collisions

- Trying to leave the map stops your ship and sets its speed to **0**.
- If a moving ship's front would hit another ship, its movement is cancelled and its speed becomes **0**.
- If turning would cause a collision, that turn is cancelled and the ship's speed becomes **0**.

The game checks collisions again whenever a movement or turn is cancelled. Leave room for your own ships as well as enemy ships.

**Speed 2 does not let a ship jump over obstacles.** First, all ships moving at speed 1 or 2 advance one cell, then collisions are checked. Next, ships still moving at speed 2 advance another cell, followed by another collision check. A ship stopped in the first step cannot take the second step.

## What Happens Each Turn

1. Every ship loses 1 unit of rum.
2. The players' commands are applied, including speed changes, firing cannonballs, and placing mines.
3. Ships move forward in up to two one-cell steps, with collision checks after each step. They collect barrels and trigger mines they touch along the way; mine damage happens immediately.
4. Ships turn.
5. Cannonballs due to land deal their damage.
6. Ships with no rum left are removed.

Ships destroyed by mines or cannonballs leave rum barrels at their sinking positions, capped at 30 units each.

Movement happens **before turning**, so a ship cannot instantly change direction and move along that new direction in the same turn.

## What Your Bot Does

On each turn, your program receives the number of ships you control, followed by the ships, barrels, visible mines, and cannonballs. It must choose one action for each of your ships and print commands in their input order.

For a cannonball, the reported position is its **target cell**, and its countdown tells you when it lands. A countdown of **1** means impact at the end of the current turn. Mine input has no extra information beyond its ID, type, and position.

The first turn allows **1 second** to respond. Later turns allow **50 milliseconds** each for all your ships together, not per ship.

## No More Rule Changes

Bronze introduces the final ruleset. Higher leagues use the same rules; there are no more mechanics to unlock.
