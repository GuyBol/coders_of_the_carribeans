#include <algorithm>
#include <array>
#include <cmath>
#include <iostream>
#include <limits>
#include <string>
#include <unordered_map>
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
    int ship_count;
    std::vector<Ship> ships;
    std::vector<Ship> opponents;
    std::vector<Barrel> barrels;
    std::vector<Mine> mines;
    std::vector<Cannonball> cannonballs;
};

struct Strategy {
    double turn_cost = 1.25;
    double target_bonus = 1.12;
    double contested_multiplier = 0.35;
    double travel_overhead = 2.0;
    double damage_cost = 4.0;
    double minimum_shot_value = 22.0;
    double fleet_urgency = 30.0;
};

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

bool same_cell(Cell first, Cell second)
{
    return first.x == second.x && first.y == second.y;
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
    const Cell bow = neighbor(ship.position, ship.direction);
    const Cell stern = neighbor(ship.position, (ship.direction + 3) % 6);
    const int distance = std::min({hex_distance(ship.position, target),
                                   hex_distance(bow, target),
                                   hex_distance(stern, target)});
    if (distance == 0) {
        return 1.0;
    }

    int turns_to_face = 3;
    const int center_distance = hex_distance(ship.position, target);
    for (int direction = 0; direction < 6; ++direction) {
        if (hex_distance(neighbor(ship.position, direction), target) < center_distance) {
            turns_to_face = std::min(turns_to_face,
                                     rotation_distance(ship.direction, direction));
        }
    }

    const double travel = std::ceil(distance / 2.0);
    const double acceleration = ship.speed == 0 ? 0.5 : 0.0;
    const double momentum = turns_to_face >= 2 ? ship.speed * 0.75 : 0.0;
    return std::max(1.0, travel + strategy.turn_cost * turns_to_face
                         + acceleration + momentum);
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
            Ship ship{entity_id, position, arg1, arg2, arg3};
            if (arg4 == 1) {
                turn.ships.push_back(ship);
            } else {
                turn.opponents.push_back(ship);
            }
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

double barrel_score(const Ship& ship, const Barrel& barrel, const Turn& turn,
                    int previous_target, const Strategy& strategy)
{
    const double arrival = estimated_turns(ship, barrel.position, strategy);
    const double capacity = std::max(0.0, 100.0 - ship.rum + arrival);
    const double useful_rum = std::min(static_cast<double>(barrel.rum), capacity);
    double score = useful_rum / (arrival + strategy.travel_overhead);

    double opponent_arrival = std::numeric_limits<double>::infinity();
    for (const Ship& opponent : turn.opponents) {
        opponent_arrival = std::min(opponent_arrival,
            estimated_turns(opponent, barrel.position, strategy));
    }
    if (opponent_arrival + 1.0 < arrival) {
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
    for (const Cannonball& cannonball : turn.cannonballs) {
        if (hex_distance(barrel.position, cannonball.target) <= 1 &&
            std::abs(arrival - cannonball.countdown) <= 1.0) {
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

struct Action {
    std::string command;
    int speed;
    int rotation;
};

using FleetPlan = std::unordered_map<int, Action>;

bool ships_overlap(const Ship& first, const Ship& second)
{
    for (Cell occupied : footprint(first)) {
        if (distance_to_ship(second, occupied) == 0) {
            return true;
        }
    }
    return false;
}

Action move_action(const Ship& ship, Cell target)
{
    const int distance = hex_distance(ship.position, target);
    int desired = ship.direction;
    int best_distance = 100;
    for (int direction = 0; direction < 6; ++direction) {
        const int remaining = hex_distance(neighbor(ship.position, direction), target);
        if (remaining < best_distance ||
            (remaining == best_distance && rotation_distance(ship.direction, direction)
                                          < rotation_distance(ship.direction, desired))) {
            best_distance = remaining;
            desired = direction;
        }
    }
    const int difference = (desired - ship.direction + 6) % 6;
    const int rotation = difference == 0 ? 0 : (difference <= 3 ? 1 : -1);
    int speed = ship.speed;
    if (distance == 0 || rotation_distance(ship.direction, desired) >= 2) {
        speed = std::max(0, speed - 1);
    } else if (rotation == 0 && distance > speed + 1) {
        speed = std::min(2, speed + 1);
    }
    return {"MOVE " + std::to_string(target.x) + " " + std::to_string(target.y),
            speed, distance == 0 ? 0 : rotation};
}

double cannon_damage(const Ship& ship, Cell target)
{
    if (same_cell(ship.position, target)) {
        return 50.0;
    }
    return distance_to_ship(ship, target) == 0 ? 25.0 : 0.0;
}

double action_risk(const Ship& ship, const Action& action, const Turn& turn,
                   const FleetPlan* plans = nullptr)
{
    const Ship final = advance_ship(ship, action.speed, action.rotation);
    double risk = 0.0;
    for (const Mine& mine : turn.mines) {
        bool touched = distance_to_ship(final, mine.position) == 0;
        for (int step = 1; step <= action.speed; ++step) {
            touched = touched || distance_to_ship(advance_ship(ship, step, 0), mine.position) == 0;
        }
        bool detonated = touched;
        for (const Cannonball& ball : turn.cannonballs) {
            detonated = detonated || (ball.countdown == 1 && same_cell(ball.target, mine.position));
        }
        if (touched) {
            risk += 25.0;
        } else if (detonated && distance_to_ship(final, mine.position) <= 1) {
            risk += 10.0;
        }
    }
    for (const Cannonball& ball : turn.cannonballs) {
        if (ball.countdown == 1) {
            risk += cannon_damage(final, ball.target);
        } else if (ball.countdown == 2) {
            risk += 0.2 * cannon_damage(advance_ship(final, final.speed, 0), ball.target);
        }
    }
    for (const Ship& opponent : turn.opponents) {
        const Ship predicted = advance_ship(opponent, opponent.speed, 0);
        if (distance_to_ship(predicted, neighbor(final.position, final.direction)) == 0) {
            risk += 8.0;
        }
    }
    for (const Ship& friendly : turn.ships) {
        if (friendly.id == ship.id) {
            continue;
        }
        Action other{"WAIT", friendly.speed, 0};
        if (plans != nullptr) {
            const auto planned = plans->find(friendly.id);
            if (planned != plans->end()) {
                other = planned->second;
            }
        }
        bool collision = ships_overlap(final, advance_ship(friendly, other.speed, other.rotation));
        for (int step = 1; step <= std::max(action.speed, other.speed); ++step) {
            collision = collision || ships_overlap(
                advance_ship(ship, std::min(step, action.speed), 0),
                advance_ship(friendly, std::min(step, other.speed), 0));
        }
        if (collision) {
            risk += 20.0;
        }
    }
    if (action.speed > 0 && final.speed == 0) {
        risk += 3.0;
    }
    return risk;
}

Action navigate(const Ship& ship, const Barrel* target, const Turn& turn, const Strategy& strategy,
                const FleetPlan* plans = nullptr)
{
    Action best = target != nullptr ? move_action(ship, target->position)
                                   : Action{ship.speed > 0 ? "SLOWER" : "WAIT",
                                            std::max(0, ship.speed - 1), 0};
    if (action_risk(ship, best, turn, plans) == 0.0) {
        return best;
    }
    std::vector<Action> candidates = {best, {"SLOWER", std::max(0, ship.speed - 1), 0},
                                      {"WAIT", ship.speed, 0}};
    for (int direction = 0; direction < 6; ++direction) {
        Cell waypoint = ship.position;
        for (int step = 0; step < 3; ++step) {
            const Cell next = neighbor(waypoint, direction);
            if (!inside_map(next)) {
                break;
            }
            waypoint = next;
        }
        candidates.push_back(move_action(ship, waypoint));
    }
    double best_cost = std::numeric_limits<double>::infinity();
    for (const Action& candidate : candidates) {
        const Ship projected = advance_ship(ship, candidate.speed, candidate.rotation);
        double cost = strategy.damage_cost * action_risk(ship, candidate, turn, plans);
        if (target != nullptr) {
            cost += estimated_turns(projected, target->position, strategy);
        } else {
            cost += projected.speed * 0.25;
        }
        if (cost < best_cost) {
            best_cost = cost;
            best = candidate;
        }
    }
    return best;
}

Ship predict_ship(Ship ship, int turns, int scenario)
{
    for (int future = 0; future < turns; ++future) {
        const int speed = scenario == 1 ? std::max(0, ship.speed - 1) : ship.speed;
        const int rotation = future == 0 && ship.speed > 0
                           ? (scenario == 2 ? 1 : (scenario == 3 ? -1 : 0)) : 0;
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
            const Ship predicted = predict_ship(opponent, ball.countdown, scenario);
            damage += cannon_damage(predicted, ball.target);
            for (const Mine& mine : turn.mines) {
                if (same_cell(mine.position, ball.target)) {
                    const int distance = distance_to_ship(predicted, mine.position);
                    damage += distance == 0 ? 25.0 : (distance == 1 ? 10.0 : 0.0);
                }
            }
        }
    }
    return damage;
}

struct Shot {
    Cell target;
    double value = 0.0;
};

Shot choose_shot(const Ship& ship, const Turn& turn, const FleetPlan* plans = nullptr)
{
    Shot best{{0, 0}, 0.0};
    const Cell bow = neighbor(ship.position, ship.direction);
    const std::array<double, 4> weights = {{0.65, 0.15, 0.10, 0.10}};
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
                for (int scenario = 0; scenario < 4; ++scenario) {
                    const Ship predicted = friendly.id == ship.id
                        ? predict_ship(advance_ship(friendly, friendly.speed, 0), flight - 1, scenario)
                        : predict_friendly(friendly, flight, scenario, plans);
                    friendly_fire = friendly_fire || cannon_damage(predicted, target) > 0;
                    for (const Mine& mine : turn.mines) {
                        if (same_cell(mine.position, target) &&
                            distance_to_ship(predicted, target) <= 1) {
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
                for (int scenario = 0; scenario < 4; ++scenario) {
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

bool useful_mine(const Ship& ship, const Turn& turn, const FleetPlan* plans = nullptr)
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
            const Ship predicted = friendly.id == ship.id
                ? predict_ship(friendly, future, 0)
                : predict_friendly(friendly, future, 0, plans);
            if (distance_to_ship(predicted, position) <= 1) {
                return false;
            }
        }
    }
    bool threatened = false;
    for (const Ship& opponent : turn.opponents) {
        if (distance_to_ship(opponent, position) == 0) {
            return false;
        }
        for (int future = 1; future <= 2; ++future) {
            threatened = threatened || distance_to_ship(predict_ship(opponent, future, 0), position) == 0;
        }
    }
    return threatened;
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
        const std::vector<const Barrel*> targets = assign_targets(turn, previous_targets, strategy);
        FleetPlan plans;
        for (const Ship& ship : turn.ships) {
            plans[ship.id] = {"WAIT", ship.speed, 0};
        }
        for (int pass = 0; pass < 3; ++pass) {
            for (std::size_t ship_index = 0; ship_index < turn.ships.size(); ++ship_index) {
                const Ship& ship = turn.ships[ship_index];
                plans[ship.id] = navigate(ship, targets[ship_index], turn, strategy, &plans);
            }
        }
        for (int ship_index = 0; ship_index < turn.ship_count; ++ship_index) {
            if (ship_index >= static_cast<int>(turn.ships.size())) {
                std::cout << "WAIT" << std::endl;
                continue;
            }

            const Ship& ship = turn.ships[ship_index];
            const Barrel* target = targets[ship_index];
            const Action navigation = navigate(ship, target, turn, strategy, &plans);
            plans[ship.id] = navigation;
            if (target != nullptr) {
                previous_targets[ship.id] = target->id;
            } else {
                previous_targets.erase(ship.id);
            }
            const Action coast{"WAIT", ship.speed, 0};
            const Ship coasting = advance_ship(ship, ship.speed, 0);
            const bool can_coast = action_risk(ship, coast, turn, &plans) == 0.0 &&
                (target == nullptr || (ship.speed > 0 &&
                 estimated_turns(coasting, target->position, strategy) <
                 estimated_turns(ship, target->position, strategy)));
            std::string command = navigation.command;
            if (can_coast && turn_number >= next_fire[ship.id]) {
                const Shot shot = choose_shot(ship, turn, &plans);
                if (shot.value >= strategy.minimum_shot_value) {
                    command = "FIRE " + std::to_string(shot.target.x) + " " + std::to_string(shot.target.y);
                    next_fire[ship.id] = turn_number + 2;
                    const int distance = hex_distance(neighbor(ship.position, ship.direction), shot.target);
                    const int flight = 1 + static_cast<int>(std::round(distance / 3.0));
                    turn.cannonballs.push_back({shot.target, ship.id, flight});
                }
            }
            if (command == navigation.command && can_coast &&
                turn_number >= next_mine[ship.id] && useful_mine(ship, turn, &plans)) {
                command = "MINE";
                next_mine[ship.id] = turn_number + 5;
                const Cell position = neighbor(neighbor(ship.position, (ship.direction + 3) % 6),
                                               (ship.direction + 3) % 6);
                const Mine placed{-ship.id - 1, position};
                turn.mines.push_back(placed);
                remembered_mines.push_back(placed);
            }
            plans[ship.id] = command == navigation.command ? navigation : Action{command, ship.speed, 0};
            std::cout << command << std::endl;
        }
        ++turn_number;
    }
    return 0;
}
