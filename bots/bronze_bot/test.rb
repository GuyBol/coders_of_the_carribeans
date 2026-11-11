require 'open3'
require 'shellwords'
require 'tmpdir'
require 'timeout'

def ship(id, x, y, direction: 0, speed: 0, rum: 60, owner: 1)
  "#{id} SHIP #{x} #{y} #{direction} #{speed} #{rum} #{owner}"
end

def barrel(id, x, y, rum: 20)
  "#{id} BARREL #{x} #{y} #{rum} 0 0 0"
end

def turn(*entities)
  count = entities.count do |entity|
    fields = entity.split
    fields[1] == 'SHIP' && fields[7] == '1'
  end
  "#{count}\n#{entities.length}\n#{entities.join("\n")}\n"
end

def run_bot(binary, input)
  output = nil
  Open3.popen3(binary) do |stdin, stdout, stderr, process|
    begin
      Timeout.timeout(10) do
        stdin.write(input)
        stdin.close
        output = stdout.read
        diagnostics = stderr.read
        raise "Process failed: #{diagnostics}" unless process.value.success?
        raise "Unexpected diagnostics: #{diagnostics}" unless diagnostics.empty?
      end
    ensure
      if process.alive?
        Process.kill('KILL', process.pid)
        process.join
      end
    end
  end
  output
end

def compile(compiler, source, binary, **options)
  output, result = Open3.capture2e(
    *compiler, '-std=c++17', '-O2', '-Wall', '-Wextra', '-Wpedantic',
    *source, '-o', binary, **options
  )
  raise "Build failed: #{output}" unless result.success?
  raise "Compiler warnings: #{output}" unless output.empty?
end

def stream_turns(binary, frame, ship_count, turns: 40)
  commands = []
  timings = []
  Open3.popen3(binary) do |stdin, stdout, stderr, process|
    begin
      Timeout.timeout(10) do
        turns.times do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stdin.write(frame)
          stdin.flush
          ship_count.times do
            command = stdout.gets
            raise 'Bot exited before producing all ship commands' unless command
            commands << command
          end
          timings << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
        end
        stdin.close
        raise 'Unexpected extra commands' unless stdout.read.empty?
        diagnostics = stderr.read
        raise "Process failed: #{diagnostics}" unless process.value.success?
        raise "Unexpected diagnostics: #{diagnostics}" unless diagnostics.empty?
      end
    ensure
      if process.alive?
        Process.kill('KILL', process.pid)
        process.join
      end
    end
  end
  [commands, timings]
end

def validate_commands(commands, ships)
  commands.each_with_index do |command, index|
    next if ["WAIT\n", "FASTER\n", "SLOWER\n", "PORT\n", "STARBOARD\n", "MINE\n"].include?(command)
    match = /\AFIRE (\d+) (\d+)\n\z/.match(command)
    unless match && (0..22).cover?(match[1].to_i) && (0..20).cover?(match[2].to_i)
      raise "Invalid Bronze command: #{command.inspect}"
    end
    fields = ships[index % ships.length].split
    ship_x = fields[2].to_i
    ship_y = fields[3].to_i
    parity = ship_y & 1
    offsets = [[1, 0], [parity, -1], [parity - 1, -1], [-1, 0], [parity - 1, 1], [parity, 1]]
    offset = offsets[fields[4].to_i]
    bow_x = ship_x + offset[0]
    bow_y = ship_y + offset[1]
    target_x = match[1].to_i
    target_y = match[2].to_i
    delta_q = bow_x - (bow_y - (bow_y & 1)) / 2 - target_x + (target_y - (target_y & 1)) / 2
    delta_r = bow_y - target_y
    distance = (delta_q.abs + delta_r.abs + (delta_q + delta_r).abs) / 2
    raise "Shot outside bow range: #{command.inspect}" if distance > 10
  end
end

cases = [
  ['empty input exits', '', ''],
  ['partial turn exits without output', "1\n1\n0 SHIP 5", ''],
  ['accelerate toward a clear barrel', turn(ship(0, 5, 10), barrel(2, 10, 10)), "FASTER\n"],
  ['wait when stopped without targets', turn(ship(0, 5, 10)), "WAIT\n"],
  ['brake before an unavoidable mine contact',
   turn(ship(0, 5, 10, speed: 1), barrel(2, 12, 10), '3 MINE 7 10 0 0 0 0'), "SLOWER\n"],
  ['fire at a stationary enemy',
   turn(ship(0, 5, 10), ship(1, 12, 10, owner: 0)), "FIRE 12 10\n"],
  ['fire cooldown skips one turn',
   turn(ship(0, 5, 10), ship(1, 12, 10, owner: 0)) * 3,
   "FIRE 12 10\nWAIT\nFIRE 12 10\n"],
  ['defensive mine cooldown skips four turns',
   turn(ship(0, 5, 10, speed: 1), ship(1, 1, 10, speed: 2, owner: 0)) * 6,
    "MINE\nSLOWER\nSLOWER\nSLOWER\nSLOWER\nMINE\n"],
  ['avoid wasting a second cannon shot',
   turn(ship(0, 5, 8), ship(2, 5, 12), ship(1, 12, 10, owner: 0)),
   "FIRE 12 10\nWAIT\n"],
  ['split fire across enemy ships',
   turn(ship(0, 5, 8), ship(2, 5, 12), ship(1, 12, 8, owner: 0), ship(3, 12, 12, owner: 0)),
   "FIRE 12 8\nFIRE 12 12\n"],
  ['three commands in friendly input order',
   turn(ship(0, 5, 4), ship(1, 19, 4, owner: 0), ship(2, 5, 10),
        ship(3, 19, 10, owner: 0), ship(4, 5, 16), ship(5, 19, 16, owner: 0),
        barrel(6, 10, 4), barrel(7, 10, 10), barrel(8, 10, 16)),
   "FASTER\nFASTER\nFASTER\n"],
  ['surviving ship keeps its own cannon cooldown',
   turn(ship(0, 5, 4), ship(2, 5, 16), ship(1, 12, 4, owner: 0), ship(3, 12, 16, owner: 0)) +
   turn(ship(2, 5, 16), ship(3, 12, 16, owner: 0)) * 2,
   "FIRE 12 4\nFIRE 12 16\nWAIT\nFIRE 12 16\n"],
  ['ignore unknown entity types',
   turn(ship(0, 5, 10), barrel(2, 10, 10), '9 UNKNOWN 0 0 0 0 0 0'), "FASTER\n"]
]

Dir.mktmpdir('bronze-bot-test-') do |directory|
  compiler = Shellwords.split(ENV.fetch('CXX', 'clang++'))
  binary = File.join(directory, 'bronze_bot')
  compile(compiler, [File.join(__dir__, 'main.cpp')], binary)

  unit_source = <<~CPP
    #define main submission_main
    #include "main.cpp"
    #undef main
    #include <cassert>

    int main()
    {
        assert(same_cell(neighbor({5, 9}, 1), {6, 8}));
        assert(same_cell(neighbor({5, 8}, 1), {5, 7}));
        assert(hex_distance({5, 9}, {6, 8}) == 1);
        const Ship original{0, {5, 10}, 0, 2, 60};
        const Action port = make_action(original, Command::Port);
        assert(port.speed == 2 && port.rotation == 1);
        assert(make_action(original, Command::Faster).speed == 2);
        assert(make_action(original, Command::Slower).speed == 1);

        Turn initial{};
        initial.ships.push_back(original);
        Turn moved = simulate_turn(initial, {{0, port}});
        assert(same_cell(moved.ships[0].position, {7, 10}));
        assert(moved.ships[0].direction == 1);
        assert(moved.ships[0].speed == 2 && moved.ships[0].rum == 59);

        Ship stopped = original;
        stopped.speed = 0;
        initial.ships[0] = stopped;
        moved = simulate_turn(initial, {{0, make_action(stopped, Command::Starboard)}});
        assert(same_cell(moved.ships[0].position, stopped.position));
        assert(moved.ships[0].direction == 5);
        moved = simulate_turn(initial, {{0, make_action(stopped, Command::Faster)}});
        assert(same_cell(moved.ships[0].position, {6, 10}));

        Turn collision{};
        collision.ships.push_back(original);
        collision.opponents.push_back({1, {8, 10}, 3, 0, 60});
        moved = simulate_turn(collision, {});
        assert(same_cell(moved.ships[0].position, {5, 10}));
        assert(moved.ships[0].speed == 0);
        collision.opponents[0].position = {9, 10};
        moved = simulate_turn(collision, {});
        assert(same_cell(moved.ships[0].position, {6, 10}));
        assert(moved.ships[0].speed == 0);

        Turn chain{};
        chain.ships = {{0, {5, 10}, 0, 1, 60}, {2, {8, 10}, 0, 1, 60}};
        chain.opponents = {{1, {11, 10}, 3, 0, 60}};
        moved = simulate_turn(chain, {});
        assert(same_cell(moved.ships[0].position, {5, 10}));
        assert(same_cell(moved.ships[1].position, {8, 10}));
        assert(moved.ships[0].speed == 0 && moved.ships[1].speed == 0);

        Turn rotation{};
        rotation.ships.push_back(stopped);
        rotation.opponents.push_back({1, {6, 8}, 4, 0, 60});
        moved = simulate_turn(rotation, {{0, make_action(stopped, Command::Port)}});
        assert(moved.ships[0].direction == 0);
        assert(moved.ships[0].speed == 0);

        Turn boundary{};
        boundary.ships.push_back({0, {20, 10}, 0, 2, 60});
        moved = simulate_turn(boundary, {});
        assert(same_cell(moved.ships[0].position, {21, 10}));
        assert(moved.ships[0].speed == 0);
        boundary.ships[0] = {0, {5, 0}, 0, 0, 60};
        moved = simulate_turn(boundary, {{0, make_action(boundary.ships[0], Command::Port)}});
        assert(moved.ships[0].direction == 0);

        Turn pickup{};
        pickup.ships.push_back({0, {5, 10}, 0, 2, 90});
        pickup.barrels.push_back({2, {7, 10}, 20});
        moved = simulate_turn(pickup, {});
        assert(moved.barrels.empty());
        assert(moved.ships[0].rum == 100);
        assert(moved.collected_by.at(2) == 0);
        pickup.ships[0].rum = 1;
        moved = simulate_turn(pickup, {});
        assert(moved.ships.size() == 1 && moved.ships[0].rum == 20);

        Turn mined{};
        mined.ships.push_back(original);
        mined.mines.push_back({2, {7, 10}});
        moved = simulate_turn(mined, {});
        assert(moved.mines.empty());
        assert(moved.ships[0].rum == 34);
        assert(same_cell(moved.ships[0].position, {7, 10}));
        mined.ships[0] = stopped;
        mined.mines[0].position = {5, 9};
        moved = simulate_turn(mined, {{0, make_action(stopped, Command::Port)}});
        assert(moved.mines.empty() && moved.ships[0].rum == 34);

        Turn shell{};
        shell.ships.push_back(original);
        shell.cannonballs.push_back({{7, 10}, 1, 1});
        moved = simulate_turn(shell, {{0, port}});
        assert(moved.ships[0].rum == 9);
        assert(moved.cannonballs.empty());
        shell.ships[0] = stopped;
        shell.cannonballs[0] = {{5, 10}, 1, 2};
        moved = simulate_turn(shell, {});
        assert(moved.ships[0].rum == 59 && moved.cannonballs[0].countdown == 1);
        moved = simulate_turn(moved, {});
        assert(moved.ships[0].rum == 8 && moved.cannonballs.empty());
        shell.cannonballs[0] = {{7, 10}, 1, 1};
        shell.mines.push_back({3, {7, 10}});
        moved = simulate_turn(shell, {});
        assert(moved.ships[0].rum == 49 && moved.mines.empty());

        Turn fleet{};
        fleet.ships = {{0, {5, 8}, 0, 0, 80}, {2, {5, 12}, 0, 0, 5}};
        fleet.barrels = {{4, {8, 10}, 30}};
        const Strategy strategy{};
        const auto targets = assign_targets(fleet, {}, strategy);
        assert(targets[0] == nullptr && targets[1] != nullptr);
        fleet.barrels.push_back({5, {10, 8}, 20});
        const auto distinct = assign_targets(fleet, {}, strategy);
        assert(distinct[0] != nullptr && distinct[1] != nullptr);
        assert(distinct[0]->id != distinct[1]->id);

        Turn completion{};
        completion.ships.push_back(stopped);
        completion.collected_by[4] = 2;
        const Barrel claimed{4, {8, 10}, 20};
        const double teammate = navigation_value(completion, stopped, &claimed, 1, strategy);
        completion.collected_by[4] = stopped.id;
        assert(navigation_value(completion, stopped, &claimed, 1, strategy) == teammate + 12.0);

        Turn steering{};
        steering.ships.push_back(stopped);
        steering.barrels.push_back({2, {5, 6}, 20});
        const Navigation left = navigate(stopped, &steering.barrels[0], steering, strategy, {});
        assert(left.action.command == Command::Port);
        steering.barrels[0].position = {5, 14};
        const Navigation right = navigate(stopped, &steering.barrels[0], steering, strategy, {});
        assert(right.action.command == Command::Starboard);

        const auto check_route = [&](Cell target, const std::vector<Mine>& mines) {
          Turn route{};
          route.ships.push_back({0, {5, 10}, 0, 0, 100});
          route.barrels.push_back({2, target, 20});
          route.mines = mines;
          for (int step = 0; step < 30 && !route.barrels.empty(); ++step) {
            assert(!route.ships.empty());
            const Ship current = route.ships[0];
            const Navigation action = navigate(current, &route.barrels[0], route, strategy, {});
            route = simulate_turn(route, {{current.id, action.action}});
          }
          assert(route.barrels.empty());
          assert(!route.ships.empty());
          assert(route.ships[0].rum >= 70);
        };
        check_route({10, 10}, {});
        check_route({5, 6}, {});
        check_route({5, 14}, {});
        check_route({2, 10}, {});
        check_route({21, 19}, {});
        check_route({12, 10}, {{3, {7, 10}}});

        Turn evasion{};
        evasion.ships.push_back(original);
        evasion.barrels.push_back({2, {7, 6}, 20});
        evasion.cannonballs.push_back({{8, 10}, 1, 1});
        const Navigation dodge = navigate(original, &evasion.barrels[0], evasion, strategy, {});
        moved = simulate_turn(evasion, {{original.id, dodge.action}});
        assert(moved.ships[0].rum == 59);

        Turn drop{};
        drop.ships.push_back({0, {5, 10}, 0, 1, 60});
        drop.opponents.push_back({1, {1, 10}, 0, 2, 60});
        assert(useful_mine(drop.ships[0], drop, {}));
        drop.barrels.push_back({2, {3, 10}, 20});
        assert(!useful_mine(drop.ships[0], drop, {}));
        drop.barrels.clear();
        drop.ships.push_back({2, {2, 8}, 5, 1, 60});
        FleetPlan crossing{{2, make_action(drop.ships[1], Command::Wait)}};
        assert(!useful_mine(drop.ships[0], drop, crossing));

        Turn vision{};
        vision.ships.push_back({0, {3, 10}, 0, 0, 60});
        std::vector<Mine> memory{{9, {8, 10}}};
        remember_mines(vision, memory);
        assert(memory.size() == 1);
        vision.mines.clear();
        vision.ships.push_back({2, {4, 10}, 0, 0, 60});
        remember_mines(vision, memory);
        assert(memory.empty());

        Turn friendly{};
        friendly.ships = {stopped, {2, {10, 10}, 0, 1, 60}};
        friendly.opponents.push_back({1, {13, 10}, 0, 0, 60});
        assert(choose_shot(stopped, friendly, {}).value < strategy.minimum_shot_value);
        return 0;
    }
  CPP
  unit_binary = File.join(directory, 'unit_tests')
  compile(compiler, ['-I', __dir__, '-x', 'c++', '-'], unit_binary, stdin_data: unit_source)
  run_bot(unit_binary, '')
  puts 'PASS Bronze movement, collision, hazard, fleet, and combat assertions'

  cases.each do |name, input, expected|
    actual = run_bot(binary, input)
    raise "#{name}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
    puts "PASS #{name}"
  end

  fleet = []
  friendly_ships = []
  [4, 10, 16].each_with_index do |row, index|
    friendly = ship(index * 2, 3, row, speed: 1)
    friendly_ships << friendly
    fleet << friendly
    fleet << ship(index * 2 + 1, 19, row, direction: 3, speed: 1, owner: 0)
  end
  26.times do |index|
    fleet << barrel(index + 6, 7 + 3 * (index % 3), 2 + 2 * (index / 3))
  end
  10.times do |index|
    fleet << "#{index + 32} MINE #{9 + 3 * (index % 3)} #{3 + 2 * (index / 3)} 0 0 0 0"
  end
  fleet << '42 CANNONBALL 4 4 1 1 0 0'
  fleet << '43 CANNONBALL 6 10 3 2 0 0'
  commands, timings = stream_turns(binary, turn(*fleet), 3)
  validate_commands(commands, friendly_ships)
  ordered = timings.drop(1).sort
  puts format('PASS streaming full fleet: average %.2f ms, p95 %.2f ms, max %.2f ms per turn',
              timings.sum / timings.length, ordered[(ordered.length * 0.95).floor], timings.max)

  combat = []
  friendly_ships = []
  [4, 10, 16].each_with_index do |row, index|
    friendly = ship(index * 2, 5, row)
    friendly_ships << friendly
    combat << friendly
    combat << ship(index * 2 + 1, 12, row, direction: 3, rum: 100, owner: 0)
  end
  commands, timings = stream_turns(binary, turn(*combat), 3)
  validate_commands(commands, friendly_ships)
  commands.each_slice(3).with_index do |actions, turn_index|
    actions.each do |command|
      if turn_index.even?
        raise 'Expected combat-ready fleet to fire' unless command.start_with?('FIRE ')
      else
        raise 'Expected per-ship cannon cooldown' unless command == "WAIT\n"
      end
    end
  end
  ordered = timings.drop(1).sort
  puts format('PASS streaming combat fleet: average %.2f ms, p95 %.2f ms, max %.2f ms per turn',
              timings.sum / timings.length, ordered[(ordered.length * 0.95).floor], timings.max)
  puts "All #{cases.length + 3} checks passed."
end
