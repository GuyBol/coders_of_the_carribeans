#pragma once
#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace caribbean {
struct Cell {
    int x = 0;
    int y = 0;
    bool operator==(Cell other) const { return x == other.x && y == other.y; }
};
inline Cell neighbor(Cell cell, int direction) {
    const int parity = cell.y & 1;
    const std::array<Cell, 6> offsets{{{1, 0}, {parity, -1}, {parity - 1, -1},
                                      {-1, 0}, {parity - 1, 1}, {parity, 1}}};
    return {cell.x + offsets[direction].x, cell.y + offsets[direction].y};
}
inline int distance(Cell first, Cell second) {
    const int delta = first.x - (first.y - (first.y & 1)) / 2
                    - second.x + (second.y - (second.y & 1)) / 2;
    const int rows = first.y - second.y;
    return (std::abs(delta) + std::abs(rows) + std::abs(delta + rows)) / 2;
}
inline bool inside(Cell cell) { return cell.x >= 0 && cell.x < 23 && cell.y >= 0 && cell.y < 21; }
struct Ship {
    int id = 0;
    int owner = 0;
    Cell position;
    int direction = 0;
    int speed = 0;
    int rum = 100;
    int fire_cooldown = 0;
    int mine_cooldown = 0;
};
inline std::array<Cell, 3> footprint(const Ship& ship) {
    return {{ship.position, neighbor(ship.position, ship.direction),
             neighbor(ship.position, (ship.direction + 3) % 6)}};
}
inline int distance_to(const Ship& ship, Cell target) {
    int result = 100;
    for (Cell cell : footprint(ship)) result = std::min(result, distance(cell, target));
    return result;
}
inline bool overlaps(const Ship& first, const Ship& second) {
    for (Cell cell : footprint(first)) if (distance_to(second, cell) == 0) return true;
    return false;
}
struct Barrel { int id; Cell position; int rum; };
struct Mine { int id; Cell position; };
struct Ball { int id; Cell position; int owner; int remaining; Cell origin; int initial; };
struct Action {
    int id = 0;
    std::string command = "WAIT";
    Cell target;
};
inline Action parse_action(int id, const std::string& line) {
    Action action;
    action.id = id;
    std::istringstream input(line);
    input >> action.command;
    std::transform(action.command.begin(), action.command.end(), action.command.begin(),
                   [](unsigned char character) { return static_cast<char>(std::toupper(character)); });
    if (action.command == "MOVE" || action.command == "FIRE") {
        if (!(input >> action.target.x >> action.target.y)) throw std::runtime_error("Missing action coordinates");
    } else if (action.command != "WAIT" && action.command != "FASTER" && action.command != "SLOWER"
               && action.command != "PORT" && action.command != "STARBOARD" && action.command != "MINE") {
        throw std::runtime_error("Unknown action: " + action.command);
    }
    return action;
}

struct State {
    int turn = 0;
    int next_id = 0;
    std::vector<Ship> ships;
    std::vector<Ship> sunk;
    std::vector<Barrel> barrels;
    std::vector<Mine> mines;
    std::vector<Ball> balls;

    std::array<int, 2> scores() const {
        std::array<int, 2> result{{0, 0}};
        for (const Ship& ship : ships) result[ship.owner] += std::max(0, ship.rum);
        return result;
    }
    bool finished() const {
        const auto totals = scores();
        return turn >= 200 || totals[0] == 0 || totals[1] == 0;
    }
    void explode(Cell position) {
        for (Ship& ship : ships) {
            const int separation = distance_to(ship, position);
            ship.rum = std::max(0, ship.rum - (separation == 0 ? 25 : (separation == 1 ? 10 : 0)));
        }
    }
    void contacts() {
        for (Ship& ship : ships) {
            for (auto barrel = barrels.begin(); barrel != barrels.end();) {
                if (distance_to(ship, barrel->position) == 0) {
                    ship.rum = std::min(100, ship.rum + barrel->rum);
                    barrel = barrels.erase(barrel);
                } else ++barrel;
            }
        }
        for (Ship& ship : ships) {
            for (auto mine = mines.begin(); mine != mines.end();) {
                if (distance_to(ship, mine->position) == 0) {
                    explode(mine->position);
                    mine = mines.erase(mine);
                } else ++mine;
            }
        }
    }
    std::string move(const Ship& ship, Cell target) const {
        if (ship.position == target) return "SLOWER";
        if (ship.speed == 2) return "SLOWER";
        if (ship.speed == 0) {
            const double delta_x = target.x - ship.position.x + ((ship.position.y - target.y) & 1) * 0.5;
            const double delta_y = (ship.position.y - target.y) * std::sqrt(3.0) / 2;
            double angle = std::atan2(delta_y, delta_x) * 3 / std::acos(-1.0);
            if (angle < 0) angle += 6;
            double difference = angle - ship.direction;
            if (std::abs(std::abs(difference) - 3) < 1e-9)
                difference = ship.direction % 3 == 0 ? -3 : (difference > 0 ? 3 : -3);
            if (difference > 3) difference -= 6;
            if (difference < -3) difference += 6;
            if (std::abs(difference) <= 0.5 + 1e-9) return "FASTER";
            return difference > 0 ? "PORT" : "STARBOARD";
        }
        const Cell origin = ship.speed == 1 ? neighbor(ship.position, ship.direction) : ship.position;
        if (ship.speed == 1 && !inside(origin)) return "SLOWER";
        if (origin == target) return "WAIT";
        if (ship.speed == 1 && distance(origin, target) == 1) {
            const double delta_x = target.x - origin.x + ((origin.y - target.y) & 1) * 0.5;
            const double delta_y = (origin.y - target.y) * std::sqrt(3.0) / 2;
            double angle = std::atan2(delta_y, delta_x) * 3 / std::acos(-1.0);
            if (angle < 0) angle += 6;
            const double difference = std::min(std::abs(ship.direction - angle), 6 - std::abs(ship.direction - angle));
            if (difference > 1.5) return "SLOWER";
        }
        int best_direction = ship.direction;
        int best_distance = 100;
        double best_angle = 100;
        const double delta_x = target.x - origin.x + ((origin.y - target.y) & 1) * 0.5;
        const double delta_y = (origin.y - target.y) * std::sqrt(3.0) / 2;
        double angle = std::atan2(delta_y, delta_x) * 3 / std::acos(-1.0);
        if (angle < 0) angle += 6;
        for (int direction : {ship.direction, (ship.direction + 5) % 6, (ship.direction + 1) % 6}) {
            if (ship.speed == 1 && !inside(neighbor(origin, direction))) continue;
            const int separation = distance(neighbor(origin, direction), target);
            const double difference = std::min(std::abs(direction - angle), 6 - std::abs(direction - angle))
                                    + (direction == ship.direction ? 0.0 : 0.5);
            const bool center_tie = separation == best_distance && difference == best_angle
                && direction != ship.direction && best_direction != ship.direction
                && distance(neighbor(origin, direction), {11, 10})
                   <= distance(neighbor(origin, best_direction), {11, 10});
            if (separation < best_distance || (separation == best_distance && difference < best_angle) || center_tie) {
                best_distance = separation;
                best_angle = difference;
                best_direction = direction;
            }
        }
        if (best_direction == ship.direction) return ship.speed == 0 ? "FASTER" : "WAIT";
        return best_direction == (ship.direction + 1) % 6 ? "PORT" : "STARBOARD";
    }
    void step(const std::vector<Action>& actions, int disqualified = 0) {
        for (const Ship& ship : ships) if (ship.rum <= 0) sunk.push_back(ship);
        ships.erase(std::remove_if(ships.begin(), ships.end(), [](const Ship& ship) { return ship.rum <= 0; }), ships.end());
        std::vector<int> initial_rum;
        std::vector<int> rotations(ships.size(), 0);
        for (Ship& ship : ships) {
            initial_rum.push_back(ship.rum);
            ship.rum = std::max(0, ship.rum - 1);
            ship.fire_cooldown = std::max(0, ship.fire_cooldown - 1);
            ship.mine_cooldown = std::max(0, ship.mine_cooldown - 1);
        }
        std::vector<Cell> impacts;
        balls.erase(std::remove_if(balls.begin(), balls.end(), [](const Ball& ball) { return ball.remaining == 0; }), balls.end());
        for (Ball& ball : balls) {
            if (ball.remaining > 0 && --ball.remaining == 0) impacts.push_back(ball.position);
        }
        for (std::size_t index = 0; index < ships.size(); ++index) {
            Ship& ship = ships[index];
            Action action;
            for (const Action& candidate : actions) if (candidate.id == ship.id) action = candidate;
            if (disqualified & (1 << ship.owner)) { action.command = "WAIT"; ship.rum = 0; }
            if (action.command == "MOVE") action.command = move(ship, action.target);
            if (action.command == "FASTER") ship.speed = std::min(2, ship.speed + 1);
            if (action.command == "SLOWER") ship.speed = std::max(0, ship.speed - 1);
            if (action.command == "PORT") rotations[index] = 1;
            if (action.command == "STARBOARD") rotations[index] = -1;
            if (action.command == "MINE" && ship.mine_cooldown == 0) {
                const Cell position = neighbor(neighbor(ship.position, (ship.direction + 3) % 6), (ship.direction + 3) % 6);
                bool occupied = !inside(position);
                for (const Ship& other : ships) occupied = occupied || distance_to(other, position) == 0;
                for (const Mine& mine : mines) occupied = occupied || mine.position == position;
                for (const Barrel& barrel : barrels) occupied = occupied || barrel.position == position;
                if (!occupied) { mines.push_back({next_id++, position}); ship.mine_cooldown = 5; }
            }
            if (action.command == "FIRE" && ship.fire_cooldown == 0 && inside(action.target)) {
                const Cell origin = neighbor(ship.position, ship.direction);
                const int separation = distance(origin, action.target);
                if (separation <= 10) {
                    const int travel = 1 + static_cast<int>(std::round(separation / 3.0));
                    balls.push_back({next_id++, action.target, ship.id, travel, origin, travel});
                    ship.fire_cooldown = 2;
                }
            }
        }
        for (int stage = 1; stage <= 2; ++stage) {
            const auto before = ships;
            std::vector<bool> moving(ships.size(), false);
            for (std::size_t index = 0; index < ships.size(); ++index) {
                if (ships[index].speed < stage) continue;
                const Cell proposed = neighbor(ships[index].position, ships[index].direction);
                if (inside(proposed)) { ships[index].position = proposed; moving[index] = true; }
                else ships[index].speed = 0;
            }
            bool changed;
            do {
                changed = false;
                std::vector<bool> cancel(ships.size(), false);
                for (std::size_t index = 0; index < ships.size(); ++index) {
                    if (ships[index].speed == 0) continue;
                    for (std::size_t other = 0; other < ships.size(); ++other) {
                        if (other != index && distance_to(ships[other], neighbor(ships[index].position, ships[index].direction)) == 0)
                            cancel[index] = true;
                    }
                }
                for (std::size_t index = 0; index < ships.size(); ++index) if (cancel[index]) {
                    ships[index].position = before[index].position;
                    ships[index].speed = 0;
                    moving[index] = false;
                    changed = true;
                }
            } while (changed);
            contacts();
        }
        const auto before = ships;
        for (std::size_t index = 0; index < ships.size(); ++index)
            ships[index].direction = (ships[index].direction + rotations[index] + 6) % 6;
        bool changed;
        do {
            changed = false;
            std::vector<bool> cancel(ships.size(), false);
            for (std::size_t index = 0; index < ships.size(); ++index) {
                for (std::size_t other = index + 1; other < ships.size(); ++other) if (overlaps(ships[index], ships[other])) {
                    cancel[index] = true;
                    cancel[other] = true;
                }
            }
            for (std::size_t index = 0; index < ships.size(); ++index) if (cancel[index]) {
                changed = changed || ships[index].direction != before[index].direction;
                ships[index].direction = before[index].direction;
                ships[index].speed = 0;
            }
        } while (changed);
        contacts();
        for (Cell impact : impacts) {
            for (Ship& ship : ships) {
                const int damage = ship.position == impact ? 50 : (distance_to(ship, impact) == 0 ? 25 : 0);
                ship.rum = std::max(0, ship.rum - damage);
            }
            for (auto mine = mines.begin(); mine != mines.end();) {
                if (mine->position == impact) { explode(impact); mine = mines.erase(mine); }
                else ++mine;
            }
            barrels.erase(std::remove_if(barrels.begin(), barrels.end(), [&](const Barrel& barrel) {
                return barrel.position == impact;
            }), barrels.end());
        }
        for (std::size_t index = 0; index < ships.size(); ++index) if (ships[index].rum <= 0) {
            const int amount = std::min(30, initial_rum[index] - 1);
            if (amount > 0 && !(disqualified & (1 << ships[index].owner))) barrels.push_back({next_id++, ships[index].position, amount});
        }
        ++turn;
    }
};
}