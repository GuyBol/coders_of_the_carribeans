# Coders of the Caribbean Rules: Bronze

Source: rules copied from CodinGame.

## League Overview

This is a league-based puzzle.

For this puzzle, multiple versions of the same game are available. Higher leagues unlock additional rules. **Bronze introduces the final rule change**; no further rules are unlocked after this league.

### New in Bronze

You can now steer ships manually with `FASTER`, `SLOWER`, `PORT`, and `STARBOARD` for more precise control. Ships can travel at **speed 2**, moving two cells per turn, twice as fast as speed 1.

When a ship is destroyed by a mine or a cannonball, the rum held by the ship is put into a new barrel at the position where the ship sank. The amount of rum in this barrel is limited to **30 units**.

Control of up to **3 ships**, cannonballs, mines, and the existing collision rules still apply. Speed-2 movement has two stages, with collisions checked after each stage.

## The Goal

In this game, you are in command of pirate ships and your goal is to avoid running out of rum. If all the rum dries up on a given ship, your crew will go mad and you will lose the ship. Barrels of rum are placed randomly across the map. You must control the movements of your ship in order to collect the barrels of rum before your opponent does.

## Rules

The game is played on a hexagonal grid **23 cells wide and 21 high**.

Each player can control **up to 3 ships**. Every ship is **3 cells long and 1 cell wide**.

> **Statement clarification:** The pasted statement still says players have one ship, with up to 3 in later leagues. The fleet rule introduced in Wood 1 and the current `1 ≤ myShipCount ≤ 3` constraint supersede that sentence.

On the grid you will find barrels of rum (`BARREL`). The initially placed barrels contain between **10 and 20 units of rum**. Barrels created when a ship is destroyed by a mine or a cannonball can contain up to **30 units**. Each ship can carry a maximum of **100 units of rum** (surplus will be lost).

Each turn, the players choose an action for each of their ships. The `MOVE` command moves a ship towards the cell of their choice. Ships can gain speed, slow down, turn left (port) or right (starboard). The `MOVE` action uses a very simplified algorithm to reach the destination. In Bronze, players can also control speed and steering directly using the manual commands described below.

### Mines

Ships can place mines on the grid with the `MINE` command. This action spawns a mine in the cell directly behind the ship. After placing a mine, a ship cannot place another for the **next 4 turns**.

If a mine is touched by a ship or hit by a cannonball, it explodes:

- A ship touching a mine loses **25 units of rum**.
- A ship in a cell adjacent to an exploding mine loses **10 units of rum**.

Players can only see mines if they are at a distance **less than 5 cells** away from the center of one of their ships.

### Cannonballs

A ship can fire a cannonball with the `FIRE x y` command, where `x` and `y` are the grid coordinates of the target cell. The target must be within **10 cells of the front of the ship**.

The cannonball is launched from the front of the ship and takes **1 + (distance to target) / 3 turns** to reach the target, with the result rounded to the nearest integer.

| Impact location | Rum lost |
| --- | --- |
| Front or back of a ship | 25 units |
| Center of a ship | 50 units |

After shooting a cannonball, a ship cannot fire during the **next turn**.

> **Note:** When using `MINE`, `FIRE`, or `WAIT`, the ship keeps moving with the same direction and speed as last turn. Using `SLOWER` slows the ship down.

### Game Turns

One game turn is computed as follows:

1. The amount of rum each ship is carrying is decreased by 1 unit.
2. The players' commands are applied (spawning of cannonballs, mines, and ship movement).
3. Ships move forward by the same number of cells as their speed, in up to two stages with collision checks after each stage.
4. Ships turn.
5. Damage from cannonballs is computed.
6. Ships with no more rum are eliminated.

If at any point during its movement a ship shares a cell with a barrel of rum, the ship collects that rum. In the same way, if a ship touches a mine, that mine explodes and the loss of rum is applied immediately.

Ships destroyed by a mine or a cannonball leave a barrel at their sinking position containing the rum they held, capped at **30 units**.

### The Grid

The `(0, 0)` coordinate is at the top left corner of the grid. The game's grid is made up of hexagonal cells in which odd-numbered rows are slightly shifted compared to a normal grid. Each cell has **6 neighbors**, except cells on the edges of the map.

![Hexagonal grid with shifted odd-numbered rows](https://www.codingame.com/servlet/fileservlet?id=12049844763948)

The distance between two cells is the minimum number of cell-to-cell steps needed to get from one to the other.

![Distance between cells on a hexagonal grid](https://www.codingame.com/servlet/fileservlet?id=12049826052986)

See [Red Blob Games' hexagonal grid guide](https://www.redblobgames.com/grids/hexagons/) for more information about working with hexagonal grids.

### The Ships

A ship's position in the grid is represented by the coordinates of its center and its direction. The direction is a number between **0 and 5**.

![The six possible ship directions](https://www.codingame.com/servlet/fileservlet?id=11930285451274)

The following table describes the hexagonal directions shown in the original image:

| Direction | Heading |
| --- | --- |
| 0 | Right |
| 1 | Top right |
| 2 | Top left |
| 3 | Left |
| 4 | Bottom left |
| 5 | Bottom right |

A ship can have one of the 6 directions shown above.

## Victory Conditions

- Your opponent runs out of rum and loses all their ships.
- After 200 turns, you have more rum in total across your ships than your opponent has across theirs.

## Expert Rules

### Collisions

If a ship attempts to leave the map, it is stopped and its speed is set to **0**.

Collisions between ships are computed during the movement phase. If a moving ship's front would collide with another ship, its movement is cancelled and its speed is set to **0**. Every time a movement is cancelled, collisions are checked again using the new positions.

For ships with a speed of **2**, movement is split into two stages:

1. All ships with speed **at least 1** move one cell forward.
2. Ships with speed **2** move one more cell forward.

Collisions are checked at the end of **each stage**, not only after the full two-cell movement. A ship stopped during the first stage does not move in the second stage.

At the end of the ships' rotation phase, collisions are checked again. Ships whose rotation would cause a collision have their rotation cancelled and their speed set to **0**. Collisions are rechecked each time a rotation is cancelled.

### Manual Steering

Starting in Bronze, ships can be controlled manually:

| Command | Effect |
| --- | --- |
| `FASTER` | Increase speed by 1, up to a maximum of 2. |
| `SLOWER` | Decrease speed by 1, down to a minimum of 0. |
| `PORT` | Turn left by one direction. |
| `STARBOARD` | Turn right by one direction. |

Speed changes are applied before forward movement. Turning occurs **after forward movement**, during the rotation phase: the new heading determines the direction of subsequent turns' movement. `PORT` and `STARBOARD` do not themselves change speed.

![A ship at speed 2 moves forward before turning to port](https://www.codingame.com/servlet/fileservlet?id=12033645600826)

In this example, the ship has speed **2** and receives `PORT`. It moves two cells along its existing heading, then turns left, subject to the collision rules. It does not move along the new heading during that turn.

Each ship still receives only **one command per turn**: for example, it cannot both accelerate and turn manually on the same turn. Automatic navigation with `MOVE x y` remains available.

### Source Code

The statement links to the [CodinGame game source repository](https://github.com/CodinGame/coders-of-the-caribbean/).

## Game Input

### Input for One Game Turn

- **Line 1:** `myShipCount`, an integer for the number of ships you control.
- **Line 2:** `entityCount`, an integer for the number of entities on the grid.
- **The next `entityCount` lines:** An integer `entityId`, a string `entityType`, two integers `x` and `y` for the coordinates of the entity, then 4 integers `arg1`, `arg2`, `arg3` and `arg4`.

```text
entityId entityType x y arg1 arg2 arg3 arg4
```

#### Ship Entities

If `entityType` equals `SHIP`, then the integers represent:

| Argument | Meaning |
| --- | --- |
| `arg1` | The ship's rotation orientation (between 0 and 5). |
| `arg2` | The ship's speed (between 0 and 2). |
| `arg3` | The ship's stock of rum units. |
| `arg4` | `1` if the ship is controlled by you, `0` otherwise. |

#### Barrel Entities

If `entityType` equals `BARREL`, then the integers represent:

| Argument | Meaning |
| --- | --- |
| `arg1` | The amount of rum in this barrel. |

#### Cannonball Entities

If `entityType` equals `CANNONBALL`, `x` and `y` are the **target coordinates**, and the integers represent:

| Argument | Meaning |
| --- | --- |
| `arg1` | The `entityId` of the ship that fired the cannonball. |
| `arg2` | The number of turns before impact. `1` means the cannonball lands at the end of the current turn. |

#### Mine Entities

If `entityType` equals `MINE`, the four integer arguments have no meaning.

## Game Output

### Output for One Game Turn

For each one of your ships, output one of the following commands:

Print **one command per ship**, in the **same order as your ships appear in the input**. Their `entityId` values are in ascending order.

| Command | Action |
| --- | --- |
| `MOVE x y` | Move automatically towards the specified coordinate. |
| `FIRE x y` | Launch a cannonball towards the specified coordinate. |
| `MINE` | Place a mine on the cell behind the ship. |
| `PORT` | Turn the ship left after forward movement. |
| `STARBOARD` | Turn the ship right after forward movement. |
| `FASTER` | Increase speed by 1, up to 2. |
| `SLOWER` | Decrease speed by 1, down to 0. |
| `WAIT` | Perform no action. |

## Constraints

| Parameter | Constraint |
| --- | --- |
| `myShipCount` | 1 ≤ `myShipCount` ≤ 3 |
| `rumBarrelCount` | 10 ≤ `rumBarrelCount` ≤ 26 |
| `initialMineCount` | 5 ≤ `initialMineCount` ≤ 10 |
| `x` | 0 ≤ `x` ≤ 22 |
| `y` | 0 ≤ `y` ≤ 20 |
| `shipSpeed` | 0 ≤ `shipSpeed` ≤ 2 |
| Response time for first turn | ≤ 1000 ms |
| Response time for one turn | ≤ 50 ms |

## Final Ruleset

This is the last rule change. Higher leagues use the same rules as Bronze.
