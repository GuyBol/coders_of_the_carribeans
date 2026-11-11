require 'tmpdir'
require_relative 'match'

def assert(condition, message = 'Assertion failed')
  raise message unless condition
end

def assert_error(fragment)
  begin
    yield
  rescue Simulator::Error => error
    assert(error.message.include?(fragment), error.message)
    return
  end
  raise "Expected an error containing #{fragment.inspect}"
end

Dir.mktmpdir('caribbean-simulator-tests-') do |directory|
  tests = File.join(directory, 'tests')
  binary = File.join(directory, 'engine')
  Simulator.build(File.join(__dir__, 'test.cpp'), tests)
  Simulator.build(File.join(__dir__, 'main.cpp'), binary)
  assert(system(tests), 'Native physics regression tests failed')

  initial = Simulator.generate(42, 3)
  assert(initial == Simulator.generate(42, 3), 'Seeded maps must be reproducible')
  assert(initial != Simulator.generate(43, 3), 'Different seeds should produce different maps')
  assert(initial[:ships].count { |ship| ship[1].zero? } == 3)
  ids = [:ships, :barrels, :mines, :balls].flat_map { |kind| initial[kind].map(&:first) }
  assert(ids.uniq.length == ids.length && initial[:next_id] == ids.max + 1)
  [:barrels, :mines].each do |kind|
    assert(initial[kind].all? { |entity| initial[kind].any? { |other| entity[1] == other[1] && entity[2] == 20 - other[2] } })
  end
  puts 'PASS reproducible symmetric maps, fleets, and global entity IDs'

  state = {turn: 0, next_id: 12, ships: [[4, 0, 5, 5, 0, 1, 80, 0, 0], [1, 1, 17, 15, 3, 0, 90, 0, 0]],
           barrels: [[6, 10, 10, 15]], mines: [[7, 5, 5], [8, 5, 9], [9, 5, 10]],
           balls: [[10, 7, 7, 1, 0, 17, 15, 3], [11, 8, 8, 1, 1, 17, 15, 3]]}
  friendly_ids, input = Simulator.bot_input(state, 0)
  lines = input.lines.map(&:strip)
  assert(friendly_ids == [4] && lines[0] == '1' && lines[1].to_i == lines.length - 2)
  assert(lines[2] == '4 SHIP 5 5 0 1 80 1' && lines[3] == '1 SHIP 17 15 3 0 90 0')
  assert(input.include?('7 MINE') && input.include?('8 MINE') && !input.include?('9 MINE'))
  assert(input.include?('11 CANNONBALL') && !input.include?('10 CANNONBALL'))
  puts 'PASS bot input ownership, ordering, shared mine visibility, and cannon countdowns'

  engine = Simulator::Engine.new(binary, initial)
  assert(engine.state[:ships] == initial[:ships])
  engine.step([])
  assert(engine.state[:turn] == 1 && engine.state[:ships].all? { |ship| ship[6] == 99 })
  engine.reset(initial)
  assert(engine.state[:turn].zero? && engine.state[:ships].all? { |ship| ship[6] == 100 })
  engine.close
  puts 'PASS persistent engine protocol, reset, and turn advancement'

  view = lambda do |frame, rum|
    header = frame.zero? ? "0\nCodersOfTheCaribbean\n2\n23 21 1 5 123\n" : "2 endReached\n"
    header + "0\n0 5 5 0 #{rum} 0 WAIT 5 6 5 4 ;\n1\n1 15 17 3 #{rum} 0 WAIT 15 16 15 18 ;\n0\n0\n0\n0\n"
  end
  capture = {
    'gameId' => 123, 'scores' => [0, 0], 'ranks' => [0, 1], 'frames' => [
      {'agentId' => -1, 'keyframe' => true, 'view' => view.call(0, 1)},
      {'agentId' => 0, 'keyframe' => false, 'view' => "1\n", 'stdout' => "WAIT\n"},
      {'agentId' => 1, 'keyframe' => true, 'view' => view.call(2, 0), 'stdout' => "WAIT\n"}
    ]
  }
  path = File.join(directory, 'replay.json')
  File.write(path, JSON.generate(capture))
  replay = Simulator::Replay.new(path)
  assert(replay.initial[:ships].last[2, 2] == [17, 15], 'Replay coordinates must be transposed')
  assert(replay.validate(binary)[:passed])
  assert(replay.validate(binary, resolved_moves: true)[:passed])
  capture['frames'][1]['stdout'] = "move 5 5\n"
  capture['frames'].last['view'] = view.call(2, 0).sub('0 WAIT 5 6 5 4', '0 SLOWER 5 6 5 4')
  File.write(path, JSON.generate(capture))
  replay = Simulator::Replay.new(path)
  assert(replay.move_cases == [{game_id: 123, turn: 0, ship_id: 0,
                               input: [5, 5, 0, 0, 5, 5], expected: 'SLOWER'}])
  assert(replay.validate(binary)[:passed] && replay.validate(binary, resolved_moves: true)[:passed])
  capture['frames'][1]['stdout'] = "WAIT\n"
  capture['frames'].last['view'] = view.call(2, 5)
  File.write(path, JSON.generate(capture))
  result = Simulator::Replay.new(path).validate(binary)
  assert(!result[:passed] && result[:mismatch_turn] == 1 && result[:entity] == :ships)
  capture['frames'][1]['stdout'] = ''
  File.write(path, JSON.generate(capture))
  assert_error('Missing ship') { Simulator::Replay.new(path) }
  File.write(path, '[]')
  assert_error('replay frames') { Simulator::Replay.new(path) }
  puts 'PASS offline replay decoding, complete-state comparison, discrepancies, and malformed captures'

  wait_bot = [tests, '--wait-bot']
  match = Simulator.match(binary, Simulator.generate(7, 1), [wait_bot, wait_bot])
  assert(match[:forfeits].empty? && match[:turns].length == 100)
  assert(match[:scores] == [0, 0] && match[:ranks] == [0, 1] && match[:winner].nil?)
  assert(Simulator.ranks([20, 20]) == [0, 1] && Simulator.ranks([5, 10]) == [1, 0])
  assert(match[:turns].all? { |turn| turn[:actions].length == 2 && turn[:elapsed_ms].length == 2 })
  puts 'PASS complete persistent-bot match, turn logs, draw scoring, and cleanup'

  ['--invalid-bot', '--exit-bot', '--silent-bot'].each do |mode|
    result = Simulator.match(binary, Simulator.generate(8, 1), [[tests, mode], wait_bot],
                             turn_ms: 50, first_turn_ms: mode == '--silent-bot' ? 20 : 1000)
    assert(result[:forfeits].length == 1 && result[:forfeits].first[:player].zero?)
    assert(result[:reason] == 'forfeit' && result[:winner] == 1 && result[:scores][0].zero?)
    assert(result[:forfeits].first[:error].include?('timed out')) if mode == '--silent-bot'
  end
  puts 'PASS malformed output, early EOF, timeout forfeits, and process cleanup'
end