#include "engine.hpp"
#include <cassert>
#include <chrono>
#include <iostream>
using namespace caribbean;

int main(int argument_count, char** arguments) {
    if (argument_count > 1) {
        const std::string mode = arguments[1];
        if (mode == "--move-cases") {
            State state;
            Ship ship;
            Cell target;
            while (std::cin >> ship.position.x >> ship.position.y >> ship.direction >> ship.speed >> target.x >> target.y)
                std::cout << state.move(ship, target) << '\n';
            return 0;
        }
        if (mode == "--exit-bot") return 0;
        if (mode == "--silent-bot") {
            std::string ignored;
            while (std::getline(std::cin, ignored)) {}
            return 0;
        }
        int fleet_size;
        int entity_count;
        while (std::cin >> fleet_size >> entity_count) {
            std::string entity;
            std::getline(std::cin, entity);
            for (int index = 0; index < entity_count; ++index) std::getline(std::cin, entity);
            for (int index = 0; index < fleet_size; ++index)
                std::cout << (mode == "--invalid-bot" ? "INVALID\n" : "WAIT\n");
            std::cout << std::flush;
        }
        return 0;
    }
    State initial;
    assert(parse_action(0, "Fire 12 10").command == "FIRE");
    assert(parse_action(0, "move 5 5").command == "MOVE");
    initial.ships = {{0, 0, {5, 5}, 0, 0, 100}, {1, 1, {17, 15}, 3, 0, 100}};
    State state = initial;
    state.step({parse_action(0, "FASTER"), parse_action(1, "PORT")});
    assert((state.ships[0].position == Cell{6, 5}) && state.ships[0].speed == 1);
    assert(state.ships[1].direction == 4 && state.ships[1].rum == 99);
    state.step({parse_action(0, "PORT")});
    assert((state.ships[0].position == Cell{7, 5}) && state.ships[0].direction == 1);
    state = initial;
    state.barrels.push_back({2, {7, 5}, 20});
    state.ships[0].rum = 60;
    state.step({parse_action(0, "FASTER")});
    assert(state.barrels.empty() && state.ships[0].rum == 79);
    state = initial;
    state.next_id = 2;
    state.step({parse_action(0, "FIRE 6 5")});
    assert(state.balls.size() == 1 && state.balls[0].remaining == 1);
    state.step({parse_action(0, "FIRE 6 5")});
    assert(state.ships[0].rum == 73 && state.balls.size() == 1);
    state.step({parse_action(0, "FIRE 6 5")});
    assert(state.balls.size() == 1);
    state = initial;
    state.mines.push_back({2, {7, 5}});
    state.step({parse_action(0, "FASTER")});
    assert(state.mines.empty() && state.ships[0].rum == 74);
    for (bool reverse_order : {false, true}) {
        state = State{};
        state.ships = {{2, 0, {13, 13}, 3, 2, 93}, {3, 1, {10, 10}, 4, 1, 100}};
        state.barrels = {{26, {10, 12}, 16}};
        state.mines = {{6, {11, 12}}};
        state.next_id = 27;
        if (reverse_order) std::reverse(state.ships.begin(), state.ships.end());
        state.step({parse_action(2, "STARBOARD"), parse_action(3, "PORT")});
        assert(state.barrels.empty() && state.mines.empty());
        for (const Ship& ship : state.ships) {
            assert(ship.rum == (ship.id == 2 ? 67 : 90));
            assert((ship.position == (ship.id == 2 ? Cell{11, 13} : Cell{9, 11})));
            assert(ship.direction == (ship.id == 2 ? 2 : 5));
        }
    }
    state = initial;
    state.ships[1].position = {9, 5};
    state.step({parse_action(0, "FASTER"), parse_action(1, "FASTER")});
    assert((state.ships[0].position == Cell{5, 5}) && state.ships[0].speed == 0);
    assert((state.ships[1].position == Cell{9, 5}) && state.ships[1].speed == 0);
    state = initial;
    state.ships[0] = {0, 0, {2, 7}, 1, 2, 70};
    state.ships[1] = {2, 1, {5, 6}, 2, 1, 84};
    state.step({parse_action(0, "STARBOARD")});
    assert((state.ships[0].position == Cell{3, 6}) && state.ships[0].speed == 0);
    assert((state.ships[1].position == Cell{4, 5}) && state.ships[1].speed == 0);
    state = initial;
    state.ships[0].position = {1, 5};
    state.ships[0].direction = 3;
    state.ships[0].speed = 1;
    state.step({});
    assert((state.ships[0].position == Cell{0, 5}) && state.ships[0].speed == 1);
    state.step({});
    assert((state.ships[0].position == Cell{0, 5}) && state.ships[0].speed == 0);
    state = initial;
    state.next_id = 2;
    state.step({parse_action(0, "MINE")});
    assert(state.mines.size() == 1 && (state.mines[0].position == Cell{3, 5}));
    for (int cooldown = 0; cooldown < 4; ++cooldown) {
        state.mines.clear();
        state.step({parse_action(0, "MINE")});
        assert(state.mines.empty() && state.next_id == 3);
    }
    state.step({parse_action(0, "MINE")});
    assert(state.mines.size() == 1 && state.next_id == 4);
    state = initial;
    state.next_id = 3;
    state.ships[0].rum = 26;
    state.balls.push_back({2, {5, 5}, 1, 1, {17, 15}, 1});
    state.step({});
    assert(state.ships[0].rum == 0 && state.barrels.size() == 1 && state.barrels[0].rum == 25);
    state.step({});
    assert(state.sunk.size() == 1 && state.ships.size() == 1);
    state = initial;
    state.ships[0].rum = 1;
    state.step({});
    assert(state.ships[0].rum == 0 && state.barrels.empty());
    state = initial;
    state.step({parse_action(0, "FIRE 17 5")});
    assert(state.balls.empty() && state.ships[0].fire_cooldown == 0);
    state.step({parse_action(0, "FIRE 16 5")});
    assert(state.balls.size() == 1 && state.balls[0].remaining == 4);
    state = initial;
    state.ships[0].speed = 2;
    state.ships[0].rum = 50;
    state.barrels.push_back({2, {7, 5}, 20});
    state.mines.push_back({3, {7, 5}});
    state.step({});
    assert((state.ships[0].position == Cell{7, 5}) && state.ships[0].rum == 44);
    assert(state.barrels.empty() && state.mines.empty());
    state = initial;
    state.balls.push_back({2, {6, 4}, 1, 1, {17, 15}, 1});
    state.step({parse_action(0, "PORT")});
    assert(state.ships[0].rum == 74);
    state = initial;
    state.ships[0].position = {0, 8};
    state.ships[0].direction = 3;
    assert(state.move(state.ships[0], {0, 8}) == "SLOWER");
    assert(state.move(state.ships[0], {1, 12}) == "PORT");
    state.ships[0].speed = 1;
    assert(state.move(state.ships[0], {1, 12}) == "SLOWER");
    state.ships[0] = {0, 0, {4, 6}, 3, 1, 100};
    assert(state.move(state.ships[0], {3, 5}) == "SLOWER");
    state.ships[0] = {0, 0, {10, 5}, 0, 0, 100};
    assert(state.move(state.ships[0], {11, 6}) == "FASTER");
    state.ships[0] = {0, 0, {17, 8}, 2, 0, 100};
    assert(state.move(state.ships[0], {18, 10}) == "PORT");
    state.ships[0] = {0, 0, {11, 18}, 3, 0, 100};
    assert(state.move(state.ships[0], {17, 18}) == "STARBOARD");
    state.ships[0] = {0, 0, {19, 1}, 0, 0, 100};
    assert(state.move(state.ships[0], {17, 1}) == "STARBOARD");
    state.ships[0] = {0, 0, {6, 2}, 4, 1, 100};
    assert(state.move(state.ships[0], {6, 19}) == "WAIT");
    state.ships[0] = {0, 0, {4, 6}, 4, 1, 100};
    assert(state.move(state.ships[0], {6, 19}) == "PORT");
    state.ships[0] = {0, 0, {2, 10}, 3, 1, 100};
    assert(state.move(state.ships[0], {12, 10}) == "PORT");
    state.ships[0] = {0, 0, {11, 18}, 3, 1, 100};
    assert(state.move(state.ships[0], {17, 18}) == "STARBOARD");
    state.ships[0] = {0, 0, {9, 8}, 1, 1, 100};
    assert(state.move(state.ships[0], {2, 21}) == "PORT");
    initial.ships.push_back({2, 0, {4, 10}, 0, 0, 100});
    initial.ships.push_back({3, 1, {18, 10}, 3, 0, 100});
    initial.ships.push_back({4, 0, {5, 15}, 0, 0, 100});
    initial.ships.push_back({5, 1, {17, 5}, 3, 0, 100});
    for (int index = 0; index < 12; ++index) initial.barrels.push_back({6 + index, {index + 5, 8}, 15});
    for (int index = 0; index < 6; ++index) initial.mines.push_back({18 + index, {index + 8, 12}});
    initial.next_id = 24;
    const auto start = std::chrono::steady_clock::now();
    for (int iteration = 0; iteration < 100000; ++iteration) {
        state = initial;
        state.step({parse_action(0, "FASTER"), parse_action(1, "MINE")});
    }
    const double seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
    std::cout << "PASS geometry, movement, steering, pickups, combat, cooldowns, collisions, wrecks, borders\n"
              << "Six-ship physics benchmark: " << 100000 / seconds << " turns/second\n";
}