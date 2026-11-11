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

def mine(id, x, y)
  "#{id} MINE #{x} #{y} 0 0 0 0"
end

def cannonball(id, x, y, owner: 1, countdown: 1)
  "#{id} CANNONBALL #{x} #{y} #{owner} #{countdown} 0 0"
end

def turn(*entities)
  ship_count = entities.count do |entity|
    fields = entity.split
    fields[1] == 'SHIP' && fields[7] == '1'
  end
  "#{ship_count}\n#{entities.length}\n#{entities.join("\n")}\n"
end

def run_bot(binary, input)
  output = nil
  Open3.popen3(binary) do |stdin, stdout, stderr, process|
    begin
      Timeout.timeout(5) do
        stdin.write(input)
        stdin.close
        output = stdout.read
        diagnostics = stderr.read
        raise "Bot failed: #{diagnostics}" unless process.value.success?
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

cases = [
  ['assign separate barrels to fleet members',
   turn(ship(0, 5, 8), ship(1, 5, 12), barrel(2, 8, 8), barrel(3, 8, 12)),
   "MOVE 8 8\nMOVE 8 12\n"],
  ['prioritize a low-rum ship for a scarce barrel',
   turn(ship(0, 5, 8, rum: 80), ship(1, 5, 12, rum: 5), barrel(2, 8, 10)),
   "WAIT\nMOVE 8 10\n"],
  ['value a 30-unit barrel from a sunken ship',
   turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 9, 10, rum: 30)), "MOVE 9 10\n"],
    ['three ships keep their input order with enemies interleaved',
     turn(ship(0, 5, 4), ship(1, 18, 4, owner: 0), ship(2, 5, 10),
       ship(3, 18, 10, owner: 0), ship(4, 5, 16), ship(5, 18, 16, owner: 0),
       barrel(6, 8, 4), barrel(7, 8, 10), barrel(8, 8, 16)),
     "MOVE 8 4\nMOVE 8 10\nMOVE 8 16\n"],
    ['do not move through a friendly hull',
     turn(ship(0, 5, 10, speed: 1), ship(2, 9, 10, direction: 3), barrel(3, 12, 10)),
     "WAIT\nWAIT\n"],
    ['share shots to avoid excessive damage on one target',
     turn(ship(0, 5, 8), ship(2, 5, 12), ship(1, 12, 10, owner: 0)),
     "FIRE 12 10\nWAIT\n"],
    ['focus fire when two hits are still useful',
     turn(ship(0, 5, 8), ship(2, 5, 12), ship(1, 12, 10, rum: 100, owner: 0)),
     "FIRE 12 10\nFIRE 12 10\n"],
    ['split shots between enemy ships',
     turn(ship(0, 5, 8), ship(2, 5, 12), ship(1, 12, 8, owner: 0), ship(3, 12, 12, owner: 0)),
     "FIRE 12 8\nFIRE 12 12\n"],
    ['a surviving ship keeps its own cooldown after an ally sinks',
     turn(ship(0, 5, 4), ship(2, 5, 16), ship(1, 12, 4, owner: 0), ship(3, 12, 16, owner: 0)) +
     turn(ship(2, 5, 16), ship(3, 12, 16, owner: 0)) * 2,
     "FIRE 12 4\nFIRE 12 16\nWAIT\nFIRE 12 16\n"],
  ['empty input exits', '', ''],
  ['truncated turn exits without a command', "1\n1\n0 SHIP 5", ''],
  ['single barrel', turn(ship(0, 5, 10), barrel(2, 8, 10)), "MOVE 8 10\n"],
  ['closer barrel', turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 18, 10)),
   "MOVE 8 10\n"],
  ['heading breaks a distance tie', turn(ship(0, 10, 10), barrel(2, 6, 10), barrel(3, 14, 10)),
   "MOVE 14 10\n"],
  ['rum value breaks an arrival tie', turn(ship(0, 5, 10), barrel(2, 8, 10, rum: 10), barrel(3, 9, 10)),
   "MOVE 9 10\n"],
  ['avoid a barrel the opponent reaches first',
   turn(ship(0, 10, 10), ship(1, 15, 10, direction: 3, owner: 0),
        barrel(2, 14, 10), barrel(3, 10, 6)), "MOVE 10 6\n"],
  ['urgent rum favors a reachable barrel',
   turn(ship(0, 5, 10, rum: 2), barrel(2, 7, 10, rum: 10), barrel(3, 15, 10)),
   "MOVE 7 10\n"],
  ['slow down without barrels', turn(ship(0, 5, 10, speed: 2)), "SLOWER\n"],
  ['wait when stopped without barrels', turn(ship(0, 5, 10)), "WAIT\n"],
  ['ignore unknown entity types',
   turn(ship(0, 5, 10), '9 UNKNOWN 0 0 0 0 0 0', barrel(2, 8, 10)), "MOVE 8 10\n"],
  ['discard barrels missing from the next turn',
   turn(ship(0, 5, 10), barrel(2, 8, 10)) + turn(ship(0, 6, 10, speed: 1)),
   "MOVE 8 10\nSLOWER\n"],
  ['retarget after a barrel disappears',
   turn(ship(0, 5, 10), barrel(2, 8, 10)) + turn(ship(0, 6, 10), barrel(3, 9, 10)),
   "MOVE 8 10\nMOVE 9 10\n"],
  ['odd-row diagonal target', turn(ship(0, 5, 9, direction: 1), barrel(2, 7, 7)),
   "MOVE 7 7\n"],
  ['edge-of-map target', turn(ship(0, 1, 0, direction: 3), barrel(2, 0, 0)),
    "MOVE 0 0\n"],
    ['avoid a mined barrel',
    turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 5, 6), mine(4, 8, 10)),
       "MOVE 5 6\n"],
      ['avoid a barrel under incoming fire',
       turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 5, 6),
        cannonball(4, 8, 10, countdown: 2)), "MOVE 5 6\n"],
      ['brake before a mine on the movement path',
       turn(ship(0, 5, 10, speed: 1), barrel(2, 12, 10), mine(3, 7, 10)), "SLOWER\n"],
      ['evade a cannonball landing this turn',
       turn(ship(0, 5, 10, speed: 2), barrel(2, 12, 10), cannonball(3, 7, 10)),
       "MOVE 3 7\n"],
      ['fire at a stationary enemy center',
       turn(ship(0, 5, 10), ship(1, 12, 10, direction: 3, owner: 0)), "FIRE 12 10\n"],
      ['lead a moving enemy rather than aiming at its old position',
       turn(ship(0, 5, 10), ship(1, 10, 10, speed: 1, owner: 0)), "FIRE 13 10\n"],
      ['fire while cruising toward rum',
       turn(ship(0, 5, 10, speed: 1), ship(1, 12, 5, direction: 3, owner: 0), barrel(2, 11, 10)),
       "FIRE 12 5\n"],
      ['range is measured from the bow',
       turn(ship(0, 5, 10), ship(1, 16, 10, direction: 3, owner: 0)), "FIRE 16 10\n"],
      ['do not fire beyond range',
       turn(ship(0, 5, 10), ship(1, 18, 10, direction: 3, owner: 0)), "WAIT\n"],
      ['cannon cooldown skips the next turn',
       turn(ship(0, 5, 10), ship(1, 12, 10, direction: 3, owner: 0)) * 3,
       "FIRE 12 10\nWAIT\nFIRE 12 10\n"],
      ['lay a mine in the path of a pursuing enemy',
       turn(ship(0, 5, 10, speed: 1), ship(1, 1, 10, speed: 2, owner: 0)), "MINE\n"],
      ['mine cooldown skips four turns',
       turn(ship(0, 5, 10, speed: 1), ship(1, 1, 10, speed: 2, owner: 0)) * 6,
       "MINE\nSLOWER\nSLOWER\nSLOWER\nSLOWER\nMINE\n"],
      ['do not drop a mine on an existing mine',
       turn(ship(0, 5, 10, speed: 1), ship(1, 1, 10, speed: 2, owner: 0), mine(2, 3, 10)),
       "SLOWER\n"],
      ['remember hidden mines and discard visibly absent ones',
       turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 1, 1), mine(4, 8, 10)) +
       turn(ship(0, 1, 10), barrel(2, 8, 10), barrel(3, 1, 1)) +
       turn(ship(0, 5, 10), barrel(2, 8, 10), barrel(3, 1, 1)),
       "MOVE 1 1\nMOVE 1 1\nMOVE 8 10\n"]
]

Dir.mktmpdir('wood-bot-test-') do |directory|
  binary = File.join(directory, 'wood_bot')
  compiler = Shellwords.split(ENV.fetch('CXX', 'clang++'))
  source = File.join(__dir__, 'main.cpp')
  build_output, build_result = Open3.capture2e(
    *compiler, '-std=c++17', '-O2', '-Wall', '-Wextra', '-Wpedantic', source, '-o', binary
  )
  abort build_output unless build_result.success?
  abort "Compiler warnings: #{build_output}" unless build_output.empty?

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
        assert(hex_distance({6, 8}, {5, 9}) == 1);

        const Ship ship{0, {5, 10}, 0, 0, 60};
        assert(cannon_damage(ship, {5, 10}) == 50.0);
        assert(cannon_damage(ship, {6, 10}) == 25.0);
        assert(cannon_damage(ship, {4, 10}) == 25.0);
        assert(cannon_damage(ship, {7, 10}) == 0.0);

        const Ship edge{0, {20, 10}, 0, 2, 60};
        const Ship stopped = advance_ship(edge, 2, 0);
        assert(same_cell(stopped.position, {21, 10}));
        assert(stopped.speed == 0);
        const Ship top{0, {5, 0}, 0, 0, 60};
        assert(advance_ship(top, 0, 1).direction == 0);

        Turn blast{};
        blast.mines.push_back({2, {7, 10}});
        blast.cannonballs.push_back({{7, 10}, 1, 1});
        assert(action_risk(ship, {"WAIT", 0, 0}, blast) == 10.0);
        blast.cannonballs.clear();
        assert(action_risk(ship, {"WAIT", 0, 0}, blast) == 0.0);
        assert(action_risk(ship, {"WAIT", 1, 0}, blast) == 25.0);

        Turn friendly{};
        friendly.ships.push_back(ship);
        friendly.ships.push_back({2, {10, 10}, 0, 1, 60});
        friendly.opponents.push_back({1, {13, 10}, 0, 0, 60});
        assert(choose_shot(ship, friendly).value == 0.0);

        Turn blocked{};
        blocked.ships.push_back({0, {5, 10}, 0, 1, 60});
        blocked.opponents.push_back({1, {1, 10}, 0, 2, 60});
        assert(useful_mine(blocked.ships.front(), blocked));
        blocked.barrels.push_back({3, {3, 10}, 20});
        assert(!useful_mine(blocked.ships.front(), blocked));

        Turn fleet{};
        fleet.ships.push_back({0, {5, 10}, 0, 1, 60});
        fleet.ships.push_back({2, {9, 10}, 3, 0, 60});
        FleetPlan plans{{0, {"WAIT", 1, 0}}, {2, {"WAIT", 0, 0}}};
        assert(action_risk(fleet.ships.front(), {"MOVE 12 10", 2, 0}, fleet, &plans) >= 20.0);
        const Barrel target{3, {12, 10}, 20};
        const Action safe = navigate(fleet.ships.front(), &target, fleet, Strategy{}, &plans);
        assert(action_risk(fleet.ships.front(), safe, fleet, &plans) == 0.0);

        Turn rotating{};
        rotating.ships.push_back(ship);
        rotating.ships.push_back({2, {10, 10}, 0, 0, 60});
        rotating.opponents.push_back({1, {10, 9}, 0, 0, 60});
        FleetPlan rotation{{2, {"MOVE 10 7", 0, 1}}};
        assert(choose_shot(ship, rotating).value == 50.0);
        assert(choose_shot(ship, rotating, &rotation).value <= 25.0);

        Turn visibility{};
        visibility.ships.push_back({0, {3, 10}, 0, 0, 60});
        std::vector<Mine> memory{{9, {8, 10}}};
        remember_mines(visibility, memory);
        assert(memory.size() == 1);
        visibility.mines.clear();
        visibility.ships.push_back({2, {4, 10}, 0, 0, 60});
        remember_mines(visibility, memory);
        assert(memory.empty());

        Turn allocation{};
        allocation.ships.push_back({0, {5, 8}, 0, 0, 60});
        allocation.ships.push_back({2, {5, 12}, 0, 0, 60});
        allocation.barrels.push_back({4, {8, 10}, 30});
        allocation.barrels.push_back({5, {10, 8}, 20});
        const Strategy strategy{};
        const auto assigned = assign_targets(allocation, {}, strategy);
        assert(assigned[0] != nullptr && assigned[1] != nullptr);
        assert(assigned[0]->id != assigned[1]->id);
        const double chosen = barrel_score(allocation.ships[0], *assigned[0], allocation, -1, strategy)
                + barrel_score(allocation.ships[1], *assigned[1], allocation, -1, strategy);
        const double alternative = barrel_score(allocation.ships[0], *assigned[1], allocation, -1, strategy)
               + barrel_score(allocation.ships[1], *assigned[0], allocation, -1, strategy);
        assert(chosen >= alternative);
        return 0;
    }
  CPP
  unit_binary = File.join(directory, 'unit_tests')
  unit_output, unit_result = Open3.capture2e(
    *compiler, '-std=c++17', '-O2', '-Wall', '-Wextra', '-Wpedantic',
    '-I', __dir__, '-x', 'c++', '-', '-o', unit_binary, stdin_data: unit_source
  )
  abort unit_output unless unit_result.success?
  abort "Compiler warnings: #{unit_output}" unless unit_output.empty?
  run_bot(unit_binary, '')
  puts 'PASS geometry, damage, fleet allocation, collisions, friendly fire, and shared vision assertions'

  cases.each do |name, input, expected|
    actual = run_bot(binary, input)
    raise "#{name}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
    puts "PASS #{name}"
  end

  entities = [ship(0, 5, 10), ship(1, 18, 10, direction: 3, owner: 0)]
  26.times do |index|
    entities << barrel(index + 2, (index * 7) % 23, (index * 3) % 21)
  end
  transcript = turn(*entities) * 200
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  output = run_bot(binary, transcript)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  commands = output.lines
  raise 'Expected exactly 200 commands' unless commands.length == 200
  commands.each do |command|
    match = /\AMOVE (\d+) (\d+)\n\z/.match(command)
    raise "Invalid command: #{command.inspect}" unless match
    unless (0..22).cover?(match[1].to_i) && (0..20).cover?(match[2].to_i)
      raise "Out-of-bounds target: #{command.inspect}"
    end
  end
  puts format('PASS 200-turn protocol/load check (%.3f ms/turn average, including process startup)',
              elapsed * 1000 / 200)

  combat_entities = [ship(0, 5, 10), ship(1, 12, 10, direction: 3, owner: 0)]
  10.times do |index|
    combat_entities << mine(index + 2, 3 + index % 5, 12 + index / 5)
  end
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  commands = run_bot(binary, turn(*combat_entities) * 200).lines
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  expected = ["FIRE 12 10\n", "WAIT\n"] * 100
  raise 'Invalid combat actions or cooldowns in load check' unless commands == expected
  puts format('PASS 200-turn combat load check (%.3f ms/turn average, including process startup)',
              elapsed * 1000 / 200)

  fleet_entities = []
  [4, 10, 16].each_with_index do |row, index|
    fleet_entities << ship(index * 2, 3, row, speed: 1)
    fleet_entities << ship(index * 2 + 1, 19, row, direction: 3, speed: 1, owner: 0)
  end
  26.times do |index|
    fleet_entities << barrel(index + 6, 7 + 3 * (index % 3), 2 + 2 * (index / 3))
  end
  10.times do |index|
    fleet_entities << mine(index + 32, 9 + 3 * (index % 3), 3 + 2 * (index / 3))
  end
  fleet_entities << cannonball(42, 4, 4)
  fleet_entities << cannonball(43, 6, 10, countdown: 2)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  commands = run_bot(binary, turn(*fleet_entities) * 200).lines
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  raise 'Expected 600 fleet commands' unless commands.length == 600
  commands.each do |command|
    next if ["WAIT\n", "SLOWER\n", "MINE\n"].include?(command)
    match = /\A(?:MOVE|FIRE) (\d+) (\d+)\n\z/.match(command)
    unless match && (0..22).cover?(match[1].to_i) && (0..20).cover?(match[2].to_i)
      raise "Invalid fleet command: #{command.inspect}"
    end
  end
  puts format('PASS 200-turn full fleet load check (%.3f ms/turn average, all three ships)',
              elapsed * 1000 / 200)

  fleet_combat = []
  [4, 10, 16].each_with_index do |row, index|
    fleet_combat << ship(index * 2, 5, row)
    fleet_combat << ship(index * 2 + 1, 12, row, direction: 3, rum: 100, owner: 0)
  end
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  commands = run_bot(binary, turn(*fleet_combat) * 200).lines
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  raise 'Expected 600 fleet combat commands' unless commands.length == 600
  commands.each_slice(3).with_index do |actions, turn_index|
    valid = if turn_index.even?
              actions.all? { |command| /\AFIRE \d+ \d+\n\z/.match(command) }
            else
              actions.all? { |command| command == "WAIT\n" }
            end
    raise "Invalid fleet combat cooldowns on turn #{turn_index}" unless valid
  end
  puts format('PASS 200-turn fleet combat load check (%.3f ms/turn average, all three ships)',
              elapsed * 1000 / 200)
  puts "All #{cases.length + 5} checks passed."
end
