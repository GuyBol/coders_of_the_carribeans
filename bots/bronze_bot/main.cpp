#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <iterator>
#include <limits>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

struct Cell {
    int x;
    int y;
};

struct Ship {
    int id;
    Cell position;
    int direction;
    int speed;
    int rum;
};

struct Barrel {
    int id;
    Cell position;
    int rum;
};

struct Mine {
    int id;
    Cell position;
};

struct Cannonball {
    Cell target;
    int owner;
    int countdown;
};

struct Turn {
    int ship_count = 0;
    std::vector<Ship> ships;
    std::vector<Ship> opponents;
    std::vector<Barrel> barrels;
    std::vector<Mine> mines;
    std::vector<Cannonball> cannonballs;
    std::unordered_map<int, int> collected_by;
};

struct Strategy {
    double turn_cost = 1.25;
    double target_bonus = 1.12;
    double contested_multiplier = 0.35;
    double travel_overhead = 2.0;
    double fleet_urgency = 30.0;
    double rum_value = 5.0;
    double minimum_shot_value = 20.0;
    double combat_detour = 2.0;
    int search_depth = 4;
    int beam_width = 10;
    int planning_passes = 2;
};

bool same_cell(Cell first, Cell second)
{
    return first.x == second.x && first.y == second.y;
}

Cell neighbor(Cell cell, int direction)
{
    const int parity = cell.y & 1;
    const std::array<Cell, 6> offsets = {{
        {1, 0}, {parity, -1}, {parity - 1, -1},
        {-1, 0}, {parity - 1, 1}, {parity, 1}
    }};
    return {cell.x + offsets[direction].x, cell.y + offsets[direction].y};
}

int hex_distance(Cell first, Cell second)
{
    const int first_q = first.x - (first.y - (first.y & 1)) / 2;
    const int second_q = second.x - (second.y - (second.y & 1)) / 2;
    const int delta_q = first_q - second_q;
    const int delta_r = first.y - second.y;
    return (std::abs(delta_q) + std::abs(delta_r) + std::abs(delta_q + delta_r)) / 2;
}

int rotation_distance(int first, int second)
{
    const int difference = std::abs(first - second);
    return std::min(difference, 6 - difference);
}

bool inside_map(Cell cell)
{
    return cell.x >= 0 && cell.x < 23 && cell.y >= 0 && cell.y < 21;
}

std::array<Cell, 3> footprint(const Ship& ship)
{
    return {{ship.position, neighbor(ship.position, ship.direction),
             neighbor(ship.position, (ship.direction + 3) % 6)}};
}

int distance_to_ship(const Ship& ship, Cell cell)
{
    int distance = 100;
    for (Cell occupied : footprint(ship)) {
        distance = std::min(distance, hex_distance(occupied, cell));
    }
    return distance;
}

bool valid_ship(const Ship& ship)
{
    for (Cell occupied : footprint(ship)) {
        if (!inside_map(occupied)) {
            return false;
        }
    }
    return true;
}

bool ships_overlap(const Ship& first, const Ship& second)
{
    for (Cell occupied : footprint(first)) {
        if (distance_to_ship(second, occupied) == 0) {
            return true;
        }
    }
    return false;
}

const Ship* find_ship(const Turn& turn, int id)
{
    for (const Ship& ship : turn.ships) {
        if (ship.id == id) {
            return &ship;
        }
    }
    return nullptr;
}

bool read_turn(std::istream& input, Turn& turn)
{
    turn = Turn{};
    int entity_count;
    if (!(input >> turn.ship_count >> entity_count)) {
        return false;
    }
    for (int entity_index = 0; entity_index < entity_count; ++entity_index) {
        int entity_id;
        std::string entity_type;
        Cell position;
        int arg1;
        int arg2;
        int arg3;
        int arg4;
        if (!(input >> entity_id >> entity_type >> position.x >> position.y
                    >> arg1 >> arg2 >> arg3 >> arg4)) {
            return false;
        }
        if (entity_type == "SHIP") {
            const Ship ship{entity_id, position, arg1, arg2, arg3};
            (arg4 == 1 ? turn.ships : turn.opponents).push_back(ship);
        } else if (entity_type == "BARREL") {
            turn.barrels.push_back({entity_id, position, arg1});
        } else if (entity_type == "MINE") {
            turn.mines.push_back({entity_id, position});
        } else if (entity_type == "CANNONBALL") {
            turn.cannonballs.push_back({position, arg1, arg2});
        }
    }
    return true;
}

void remember_mines(Turn& turn, std::vector<Mine>& remembered)
{
    for (const Mine& mine : remembered) {
        bool seen = false;
        for (const Mine& visible : turn.mines) {
            seen = seen || same_cell(mine.position, visible.position);
        }
        bool in_vision = false;
        for (const Ship& ship : turn.ships) {
            in_vision = in_vision || hex_distance(ship.position, mine.position) < 5;
        }
        if (!seen && !in_vision) {
            turn.mines.push_back(mine);
        }
    }
    remembered = turn.mines;
}

double estimated_turns(const Ship& ship, Cell target, const Strategy& strategy)
{
    const int distance = distance_to_ship(ship, target);
    if (distance == 0) {
        return 1.0;
    }
    int turns_to_face = 3;
    for (int direction = 0; direction < 6; ++direction) {
        if (hex_distance(neighbor(ship.position, direction), target)
            < hex_distance(ship.position, target)) {
            turns_to_face = std::min(turns_to_face, rotation_distance(ship.direction, direction));
        }
    }
    return std::max(1.0, std::ceil(distance / 2.0) + strategy.turn_cost * turns_to_face
        + (ship.speed == 0 ? 0.5 : 0.0) + (turns_to_face >= 2 ? ship.speed * 0.75 : 0.0));
}

double barrel_score(const Ship& ship, const Barrel& barrel, const Turn& turn,
                    int previous_target, const Strategy& strategy)
{
    const double arrival = estimated_turns(ship, barrel.position, strategy);
    const double useful = std::min(static_cast<double>(barrel.rum),
                                   std::max(0.0, 100.0 - ship.rum + arrival));
    double score = useful / (arrival + strategy.travel_overhead);
    double enemy_arrival = std::numeric_limits<double>::infinity();
    for (const Ship& opponent : turn.opponents) {
        enemy_arrival = std::min(enemy_arrival, estimated_turns(opponent, barrel.position, strategy));
    }
    if (enemy_arrival + 1.0 < arrival) {
        score *= strategy.contested_multiplier;
    }
    if (arrival > ship.rum) {
        score *= 0.05;
    }
    if (barrel.id == previous_target) {
        score *= strategy.target_bonus;
    }
    for (const Mine& mine : turn.mines) {
        const int distance = hex_distance(barrel.position, mine.position);
        if (distance <= 1) {
            score *= distance == 0 ? 0.05 : 0.4;
        }
    }
    for (const Cannonball& ball : turn.cannonballs) {
        if (hex_distance(barrel.position, ball.target) <= 1 &&
            std::abs(arrival - ball.countdown) <= 1.0) {
            score *= 0.3;
        }
    }
    return score;
}

std::vector<const Barrel*> assign_targets(const Turn& turn,
    const std::unordered_map<int, int>& previous_targets, const Strategy& strategy)
{
    const int ship_count = static_cast<int>(turn.ships.size());
    const int barrel_count = static_cast<int>(turn.barrels.size());
    std::vector<std::vector<double>> scores(ship_count, std::vector<double>(barrel_count));
    for (int ship_index = 0; ship_index < ship_count; ++ship_index) {
        const Ship& ship = turn.ships[ship_index];
        const auto previous = previous_targets.find(ship.id);
        const int previous_target = previous == previous_targets.end() ? -1 : previous->second;
        const double urgency = 1.0 + strategy.fleet_urgency / std::max(5, ship.rum);
        for (int barrel_index = 0; barrel_index < barrel_count; ++barrel_index) {
            scores[ship_index][barrel_index] = urgency * barrel_score(
                ship, turn.barrels[barrel_index], turn, previous_target, strategy);
        }
    }
    std::vector<int> order;
    for (int barrel_index = 0; barrel_index < barrel_count; ++barrel_index) {
        order.push_back(barrel_index);
    }
    std::sort(order.begin(), order.end(), [&](int first, int second) {
        return turn.barrels[first].id < turn.barrels[second].id;
    });
    std::vector<bool> used(barrel_count, false);
    std::vector<const Barrel*> current(ship_count, nullptr);
    std::vector<const Barrel*> best = current;
    double best_score = -1.0;
    const auto search = [&](auto& recurse, int ship_index, double score) -> void {
        if (ship_index == ship_count) {
            if (score > best_score) {
                best_score = score;
                best = current;
            }
            return;
        }
        for (int barrel_index : order) {
            if (!used[barrel_index]) {
                used[barrel_index] = true;
                current[ship_index] = &turn.barrels[barrel_index];
                recurse(recurse, ship_index + 1, score + scores[ship_index][barrel_index]);
                used[barrel_index] = false;
            }
        }
        current[ship_index] = nullptr;
        recurse(recurse, ship_index + 1, score);
    };
    search(search, 0, 0.0);
    return best;
}

enum class Command { Wait, Faster, Slower, Port, Starboard };

struct Action {
    Command command = Command::Wait;
    int speed = 0;
    int rotation = 0;
};

using FleetPlan = std::unordered_map<int, Action>;

Action make_action(const Ship& ship, Command command)
{
    int speed = ship.speed;
    if (command == Command::Faster) {
        speed = std::min(2, speed + 1);
    } else if (command == Command::Slower) {
        speed = std::max(0, speed - 1);
    }
    return {command, speed, command == Command::Port ? 1 : (command == Command::Starboard ? -1 : 0)};
}

std::string command_text(Command command)
{
    switch (command) {
    case Command::Faster: return "FASTER";
    case Command::Slower: return "SLOWER";
    case Command::Port: return "PORT";
    case Command::Starboard: return "STARBOARD";
    default: return "WAIT";
    }
}

Ship advance_ship(Ship ship, int speed, int rotation)
{
    ship.speed = speed;
    for (int step = 0; step < speed; ++step) {
        Ship next = ship;
        next.position = neighbor(ship.position, ship.direction);
        if (!valid_ship(next)) {
            ship.speed = 0;
            break;
        }
        ship = next;
    }
    Ship rotated = ship;
    rotated.direction = (ship.direction + rotation + 6) % 6;
    if (valid_ship(rotated)) {
        ship = rotated;
    } else {
        ship.speed = 0;
    }
    return ship;
}

double cannon_damage(const Ship& ship, Cell target)
{
    if (same_cell(ship.position, target)) {
        return 50.0;
    }
    return distance_to_ship(ship, target) == 0 ? 25.0 : 0.0;
}

void explode_mine(std::vector<Ship>& ships, Cell position)
{
    for (Ship& ship : ships) {
        const int distance = distance_to_ship(ship, position);
        ship.rum -= distance == 0 ? 25 : (distance == 1 ? 10 : 0);
    }
}

void collect_and_explode(Turn& turn, std::vector<Ship>& ships)
{
    for (auto barrel = turn.barrels.begin(); barrel != turn.barrels.end();) {
        bool collected = false;
        for (Ship& ship : ships) {
            if (distance_to_ship(ship, barrel->position) == 0) {
                ship.rum = std::min(100, ship.rum + barrel->rum);
                turn.collected_by[barrel->id] = ship.id;
                collected = true;
                break;
            }
        }
        barrel = collected ? turn.barrels.erase(barrel) : std::next(barrel);
    }
    for (auto mine = turn.mines.begin(); mine != turn.mines.end();) {
        bool touched = false;
        for (const Ship& ship : ships) {
            touched = touched || distance_to_ship(ship, mine->position) == 0;
        }
        if (touched) {
            explode_mine(ships, mine->position);
            mine = turn.mines.erase(mine);
        } else {
            ++mine;
        }
    }
}

Turn simulate_turn(Turn turn, const FleetPlan& plans)
{
    std::vector<Ship> ships = turn.ships;
    ships.insert(ships.end(), turn.opponents.begin(), turn.opponents.end());
    const std::size_t friendly_count = turn.ships.size();
    std::vector<int> rotations(ships.size(), 0);
    for (std::size_t index = 0; index < ships.size(); ++index) {
        --ships[index].rum;
        const auto action = plans.find(ships[index].id);
        if (action != plans.end()) {
            ships[index].speed = action->second.speed;
            rotations[index] = action->second.rotation;
        }
    }
    for (int stage = 1; stage <= 2; ++stage) {
        const std::vector<Ship> before = ships;
        std::vector<Ship> proposed = ships;
        std::vector<bool> moving(ships.size(), false);
        for (std::size_t index = 0; index < ships.size(); ++index) {
            if (ships[index].speed >= stage) {
                proposed[index].position = neighbor(ships[index].position, ships[index].direction);
                if (valid_ship(proposed[index])) {
                    moving[index] = true;
                } else {
                    proposed[index] = before[index];
                    proposed[index].speed = 0;
                }
            }
        }
        bool changed;
        do {
            changed = false;
            std::vector<bool> cancel(ships.size(), false);
            for (std::size_t index = 0; index < ships.size(); ++index) {
                if (!moving[index]) {
                    continue;
                }
                const Cell bow = neighbor(proposed[index].position, proposed[index].direction);
                for (std::size_t other = 0; other < ships.size(); ++other) {
                    if (index != other && distance_to_ship(proposed[other], bow) == 0) {
                        cancel[index] = true;
                    }
                }
            }
            for (std::size_t index = 0; index < ships.size(); ++index) {
                if (cancel[index]) {
                    proposed[index] = before[index];
                    proposed[index].speed = 0;
                    moving[index] = false;
                    changed = true;
                }
            }
        } while (changed);
        ships = std::move(proposed);
        collect_and_explode(turn, ships);
    }
    const std::vector<Ship> before_rotation = ships;
    std::vector<bool> rotating(ships.size(), false);
    for (std::size_t index = 0; index < ships.size(); ++index) {
        if (rotations[index] != 0) {
            ships[index].direction = (ships[index].direction + rotations[index] + 6) % 6;
            if (valid_ship(ships[index])) {
                rotating[index] = true;
            } else {
                ships[index] = before_rotation[index];
                ships[index].speed = 0;
            }
        }
    }
    bool changed;
    do {
        changed = false;
        std::vector<bool> cancel(ships.size(), false);
        for (std::size_t index = 0; index < ships.size(); ++index) {
            if (!rotating[index]) {
                continue;
            }
            for (std::size_t other = 0; other < ships.size(); ++other) {
                if (index != other && ships_overlap(ships[index], ships[other])) {
                    cancel[index] = true;
                }
            }
        }
        for (std::size_t index = 0; index < ships.size(); ++index) {
            if (cancel[index]) {
                ships[index] = before_rotation[index];
                ships[index].speed = 0;
                rotating[index] = false;
                changed = true;
            }
        }
    } while (changed);
    collect_and_explode(turn, ships);
    for (auto ball = turn.cannonballs.begin(); ball != turn.cannonballs.end();) {
        --ball->countdown;
        if (ball->countdown <= 0) {
            for (Ship& ship : ships) {
                ship.rum -= static_cast<int>(cannon_damage(ship, ball->target));
            }
            for (auto mine = turn.mines.begin(); mine != turn.mines.end();) {
                if (same_cell(mine->position, ball->target)) {
                    explode_mine(ships, mine->position);
                    mine = turn.mines.erase(mine);
                } else {
                    ++mine;
                }
            }
            ball = turn.cannonballs.erase(ball);
        } else {
            ++ball;
        }
    }
    turn.ships.clear();
    turn.opponents.clear();
    for (std::size_t index = 0; index < ships.size(); ++index) {
        if (ships[index].rum > 0) {
            (index < friendly_count ? turn.ships : turn.opponents).push_back(ships[index]);
        }
    }
    turn.ship_count = static_cast<int>(turn.ships.size());
    return turn;
}

struct Navigation {
    Action action;
    double value;
};

struct SearchNode {
    Turn turn;
    Action first;
    double value;
};

double navigation_value(const Turn& turn, const Ship& original, const Barrel* target,
                         int depth, const Strategy& strategy)
{
    const Ship* ship = find_ship(turn, original.id);
    if (ship == nullptr) {
        return -10000.0;
    }
    double value = strategy.rum_value * (ship->rum - original.rum + depth);
    if (target != nullptr) {
        const Barrel* remaining = nullptr;
        for (const Barrel& barrel : turn.barrels) {
            if (barrel.id == target->id) {
                remaining = &barrel;
            }
        }
        if (remaining != nullptr) {
            value -= 3.0 * estimated_turns(*ship, remaining->position, strategy);
        } else {
            const auto collector = turn.collected_by.find(target->id);
            if (collector != turn.collected_by.end() && collector->second == original.id) {
                value += 12.0;
            }
            double next = 8.0;
            for (const Barrel& barrel : turn.barrels) {
                next = std::min(next, estimated_turns(*ship, barrel.position, strategy));
            }
            value -= 0.5 * next;
        }
    } else {
        value -= 0.5 * ship->speed;
    }
    return value;
}

Navigation navigate(const Ship& ship, const Barrel* target, const Turn& turn,
                    const Strategy& strategy, const FleetPlan& plans, bool force_coast = false)
{
    const Action fallback = make_action(ship, ship.speed > 0 ? Command::Slower : Command::Wait);
    std::vector<SearchNode> beam{{turn, fallback, -10000.0}};
    for (int depth = 1; depth <= strategy.search_depth; ++depth) {
        std::vector<SearchNode> next;
        for (const SearchNode& node : beam) {
            const Ship* current = find_ship(node.turn, ship.id);
            if (current == nullptr) {
                next.push_back(node);
                continue;
            }
            const std::array<Command, 5> commands = {{Command::Wait, Command::Faster,
                Command::Slower, Command::Port, Command::Starboard}};
            for (Command command : commands) {
                if ((force_coast && depth == 1 && command != Command::Wait) ||
                    (command == Command::Faster && current->speed == 2) ||
                    (command == Command::Slower && current->speed == 0)) {
                    continue;
                }
                const Action action = make_action(*current, command);
                FleetPlan projected = depth == 1 ? plans : FleetPlan{};
                projected[ship.id] = action;
                Turn future = simulate_turn(node.turn, projected);
                const double value = navigation_value(future, ship, target, depth, strategy);
                next.push_back({std::move(future), depth == 1 ? action : node.first, value});
            }
        }
        std::stable_sort(next.begin(), next.end(), [](const SearchNode& first, const SearchNode& second) {
            return first.value > second.value;
        });
        if (next.size() > static_cast<std::size_t>(strategy.beam_width)) {
            next.resize(strategy.beam_width);
        }
        beam = std::move(next);
    }
    return beam.empty() ? Navigation{fallback, -10000.0}
                        : Navigation{beam.front().first, beam.front().value};
}

Ship predict_ship(Ship ship, int turns, int scenario)
{
    for (int future = 0; future < turns; ++future) {
        int speed = scenario == 1 ? std::max(0, ship.speed - 1) : ship.speed;
        if (scenario == 4) {
            speed = std::min(2, ship.speed + 1);
        }
        const int rotation = future == 0 ? (scenario == 2 ? 1 : (scenario == 3 ? -1 : 0)) : 0;
        ship = advance_ship(ship, speed, rotation);
    }
    return ship;
}

Ship predict_friendly(Ship ship, int turns, int scenario, const FleetPlan* plans)
{
    if (plans != nullptr && turns > 0) {
        const auto planned = plans->find(ship.id);
        if (planned != plans->end()) {
            ship = advance_ship(ship, planned->second.speed, planned->second.rotation);
            --turns;
        }
    }
    return predict_ship(ship, turns, scenario);
}

double committed_damage(const Ship& opponent, int flight, int scenario, const Turn& turn)
{
    double damage = 0.0;
    for (const Cannonball& ball : turn.cannonballs) {
        if (ball.countdown <= 0 || ball.countdown > flight) {
            continue;
        }
        bool friendly = false;
        for (const Ship& ship : turn.ships) {
            friendly = friendly || ship.id == ball.owner;
        }
        if (friendly) {
            damage += cannon_damage(predict_ship(opponent, ball.countdown, scenario), ball.target);
        }
    }
    return damage;
}

struct Shot {
    Cell target;
    double value = 0.0;
};

Shot choose_shot(const Ship& ship, const Turn& turn, const FleetPlan& plans)
{
    Shot best{{0, 0}, 0.0};
    const Cell bow = neighbor(ship.position, ship.direction);
    const std::array<double, 5> weights = {{0.55, 0.15, 0.12, 0.12, 0.06}};
    for (int row = 0; row < 21; ++row) {
        for (int column = 0; column < 23; ++column) {
            const Cell target{column, row};
            const int distance = hex_distance(bow, target);
            if (distance > 10) {
                continue;
            }
            const int flight = 1 + static_cast<int>(std::round(distance / 3.0));
            bool friendly_fire = false;
            for (const Ship& friendly : turn.ships) {
                for (int scenario = 0; scenario < 5; ++scenario) {
                    const Ship predicted = friendly.id == ship.id
                        ? predict_ship(advance_ship(friendly, friendly.speed, 0), flight - 1, scenario)
                        : predict_friendly(friendly, flight, scenario, &plans);
                    friendly_fire = friendly_fire || cannon_damage(predicted, target) > 0;
                    for (const Mine& mine : turn.mines) {
                        if (same_cell(mine.position, target) && distance_to_ship(predicted, target) <= 1) {
                            friendly_fire = true;
                        }
                    }
                }
            }
            if (friendly_fire) {
                continue;
            }
            double value = 0.0;
            for (const Ship& opponent : turn.opponents) {
                for (int scenario = 0; scenario < 5; ++scenario) {
                    const Ship predicted = predict_ship(opponent, flight, scenario);
                    double damage = cannon_damage(predicted, target);
                    for (const Mine& mine : turn.mines) {
                        if (same_cell(mine.position, target)) {
                            const int separation = distance_to_ship(predicted, target);
                            damage += separation == 0 ? 25.0 : (separation == 1 ? 10.0 : 0.0);
                        }
                    }
                    const double remaining = std::max(0.0, opponent.rum -
                        committed_damage(opponent, flight, scenario, turn));
                    value += weights[scenario] * std::min(damage, remaining);
                }
            }
            if (value > best.value) {
                best = {target, value};
            }
        }
    }
    return best;
}

bool useful_mine(const Ship& ship, const Turn& turn, const FleetPlan& plans)
{
    if (ship.speed == 0) {
        return false;
    }
    const Cell position = neighbor(neighbor(ship.position, (ship.direction + 3) % 6),
                                   (ship.direction + 3) % 6);
    if (!inside_map(position)) {
        return false;
    }
    for (const Mine& mine : turn.mines) {
        if (same_cell(position, mine.position)) {
            return false;
        }
    }
    for (const Barrel& barrel : turn.barrels) {
        if (same_cell(position, barrel.position)) {
            return false;
        }
    }
    for (const Ship& friendly : turn.ships) {
        if (distance_to_ship(friendly, position) == 0) {
            return false;
        }
        for (int future = 1; future <= 2; ++future) {
            const Ship predicted = friendly.id == ship.id ? predict_ship(friendly, future, 0)
                : predict_friendly(friendly, future, 0, &plans);
            if (distance_to_ship(predicted, position) <= 1) {
                return false;
            }
        }
    }
    for (const Ship& opponent : turn.opponents) {
        if (distance_to_ship(opponent, position) == 0) {
            return false;
        }
    }
    for (const Ship& opponent : turn.opponents) {
        for (int future = 1; future <= 2; ++future) {
            if (distance_to_ship(predict_ship(opponent, future, 0), position) == 0) {
                return true;
            }
        }
    }
    return false;
}

int main()
{
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    const Strategy strategy;
    std::unordered_map<int, int> previous_targets;
    std::unordered_map<int, int> next_fire;
    std::unordered_map<int, int> next_mine;
    std::vector<Mine> remembered_mines;
    int turn_number = 0;
    Turn turn;
    while (read_turn(std::cin, turn)) {
        remember_mines(turn, remembered_mines);
        const auto targets = assign_targets(turn, previous_targets, strategy);
        FleetPlan plans;
        for (const Ship& ship : turn.ships) {
            plans[ship.id] = make_action(ship, Command::Wait);
        }
        for (int pass = 0; pass < strategy.planning_passes; ++pass) {
            for (std::size_t index = 0; index < turn.ships.size(); ++index) {
                const Ship& ship = turn.ships[index];
                plans[ship.id] = navigate(ship, targets[index], turn, strategy, plans).action;
            }
        }
        for (int index = 0; index < turn.ship_count; ++index) {
            if (index >= static_cast<int>(turn.ships.size())) {
                std::cout << "WAIT" << std::endl;
                continue;
            }
            const Ship& ship = turn.ships[index];
            const Barrel* target = targets[index];
            const Navigation navigation = navigate(ship, target, turn, strategy, plans);
            plans[ship.id] = navigation.action;
            if (target != nullptr) {
                previous_targets[ship.id] = target->id;
            } else {
                previous_targets.erase(ship.id);
            }
            std::string command = command_text(navigation.action.command);
            const bool fire_ready = turn_number >= next_fire[ship.id];
            const bool mine_ready = turn_number >= next_mine[ship.id];
            const Shot shot = fire_ready ? choose_shot(ship, turn, plans) : Shot{{0, 0}, 0.0};
            const bool mine = mine_ready && useful_mine(ship, turn, plans);
            if (shot.value >= strategy.minimum_shot_value || mine) {
                const Navigation coast = navigate(ship, target, turn, strategy, plans, true);
                if (coast.value >= navigation.value - strategy.combat_detour && coast.value > -1000.0) {
                    plans[ship.id] = make_action(ship, Command::Wait);
                    if (shot.value >= strategy.minimum_shot_value) {
                        command = "FIRE " + std::to_string(shot.target.x) + " " + std::to_string(shot.target.y);
                        next_fire[ship.id] = turn_number + 2;
                        const int distance = hex_distance(neighbor(ship.position, ship.direction), shot.target);
                        turn.cannonballs.push_back({shot.target, ship.id,
                            1 + static_cast<int>(std::round(distance / 3.0))});
                    } else {
                        command = "MINE";
                        next_mine[ship.id] = turn_number + 5;
                        const Cell position = neighbor(neighbor(ship.position, (ship.direction + 3) % 6),
                                                       (ship.direction + 3) % 6);
                        const Mine placed{-ship.id - 1, position};
                        turn.mines.push_back(placed);
                        remembered_mines.push_back(placed);
                    }
                }
            }
            std::cout << command << std::endl;
        }
        ++turn_number;
    }
    return 0;
}
