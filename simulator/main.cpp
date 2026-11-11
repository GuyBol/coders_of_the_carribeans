#include "engine.hpp"
#include <iostream>

using namespace caribbean;

void write_state(const State& state) {
    std::cout << state.turn << ' ' << state.next_id << '\n' << state.ships.size() + state.sunk.size() << '\n';
    std::vector<Ship> visible = state.ships;
    visible.insert(visible.end(), state.sunk.begin(), state.sunk.end());
    for (const Ship& ship : visible)
        std::cout << ship.id << ' ' << ship.owner << ' ' << ship.position.x << ' ' << ship.position.y << ' '
                  << ship.direction << ' ' << ship.speed << ' ' << ship.rum << ' '
                  << ship.fire_cooldown << ' ' << ship.mine_cooldown << '\n';
    std::cout << state.barrels.size() << '\n';
    for (const Barrel& barrel : state.barrels)
        std::cout << barrel.id << ' ' << barrel.position.x << ' ' << barrel.position.y << ' ' << barrel.rum << '\n';
    std::cout << state.mines.size() << '\n';
    for (const Mine& mine : state.mines) std::cout << mine.id << ' ' << mine.position.x << ' ' << mine.position.y << '\n';
    std::cout << state.balls.size() << '\n';
    for (const Ball& ball : state.balls)
        std::cout << ball.id << ' ' << ball.position.x << ' ' << ball.position.y << ' ' << ball.owner << ' '
                  << ball.remaining << ' ' << ball.origin.x << ' ' << ball.origin.y << ' ' << ball.initial << '\n';
    std::cout << std::flush;
}

int main() {
    std::ios::sync_with_stdio(false);
    State state;
    std::string command;
    while (std::cin >> command) {
        if (command == "RESET") {
            state = State{};
            std::cin >> state.turn >> state.next_id;
            int count;
            std::cin >> count;
            for (int index = 0; index < count; ++index) {
                Ship ship;
                std::cin >> ship.id >> ship.owner >> ship.position.x >> ship.position.y >> ship.direction
                         >> ship.speed >> ship.rum >> ship.fire_cooldown >> ship.mine_cooldown;
                state.ships.push_back(ship);
            }
            std::cin >> count;
            for (int index = 0; index < count; ++index) {
                Barrel barrel;
                std::cin >> barrel.id >> barrel.position.x >> barrel.position.y >> barrel.rum;
                state.barrels.push_back(barrel);
            }
            std::cin >> count;
            for (int index = 0; index < count; ++index) {
                Mine mine;
                std::cin >> mine.id >> mine.position.x >> mine.position.y;
                state.mines.push_back(mine);
            }
            std::cin >> count;
            for (int index = 0; index < count; ++index) {
                Ball ball;
                std::cin >> ball.id >> ball.position.x >> ball.position.y >> ball.owner >> ball.remaining
                         >> ball.origin.x >> ball.origin.y >> ball.initial;
                state.balls.push_back(ball);
            }
        } else if (command == "STEP") {
            int count;
            int disqualified;
            std::cin >> count >> disqualified;
            std::string line;
            std::getline(std::cin, line);
            std::vector<Action> actions;
            for (int index = 0; index < count; ++index) {
                int id;
                std::cin >> id;
                std::getline(std::cin, line);
                try { actions.push_back(parse_action(id, line)); }
                catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
            }
            state.step(actions, disqualified);
        } else return 1;
        if (!std::cin) return 1;
        write_state(state);
    }
}