require_relative 'arena'
require_relative 'run'
require 'stringio'

def assert(condition, message = 'Assertion failed')
  raise message unless condition
end

names = %w[alpha beta gamma]
schedule = Arena.schedule(names, rounds: 2, seed: 41)
assert(schedule.length == 12)
assert(schedule.map { |match| match[:id] } == (1..12).to_a)
schedule.each_slice(2) do |first, second|
  assert(first[:players] == second[:players].reverse && first[:seed] == second[:seed])
end
names.combination(2).each do |pair|
  assert(schedule.count { |match| match[:players] == pair } == 2)
  assert(schedule.count { |match| match[:players] == pair.reverse } == 2)
end
assert(schedule == Arena.schedule(names, rounds: 2, seed: 41))
puts 'PASS balanced pairings, shared home/away seeds, rounds, and deterministic schedules'

results = schedule.map { |match| match.merge(winner: nil, forfeits: []) }
rows = Arena.rankings(names, results)
assert(rows.all? { |row| row[:rating] == 1500 && row[:games] == 8 && row[:seats] == [4, 4] && row[:draws] == 8 })
decisive = [{id: 1, players: %w[alpha beta], winner: 0, forfeits: [{player: 1}]}]
rows = Arena.rankings(%w[alpha beta], decisive)
assert(rows[0][:rating] == 1516 && rows[0][:wins] == 1)
assert(rows[1][:rating] == 1484 && rows[1][:forfeits] == 1 && rows[1][:losses] == 1)
assert(Arena.rankings(names, results.reverse) == Arena.rankings(names, results))
assert(Arena.rankings(names, [{id: 1, error: 'engine failure'}]).all? { |row| row[:games].zero? })
puts 'PASS deterministic Elo, draws, seat counts, forfeits, and exclusion of failed matches'

class FakePlugin
  attr_reader :maximum_active

  def initialize
    @mutex = Mutex.new
    @active = 0
    @maximum_active = 0
    @ready = ConditionVariable.new
  end

  def game
    'fake-game'
  end

  def prepare(bots:, directory:, options:)
    @bots = bots
  end

  def play(players:, seed:, match_id:)
    @mutex.synchronize do
      @active += 1
      @maximum_active = [@maximum_active, @active].max
      @ready.broadcast
      @ready.wait(@mutex, 2) if @active < 2 && match_id <= 2
    end
    raise 'deliberate engine failure' if match_id == 3
    {scores: [0, 0], winner: nil, reason: 'draw', forfeits: [],
     replay: {'frames' => [{}]}, metadata: {}, details: {seed: seed}}
  ensure
    @mutex.synchronize { @active -= 1 }
  end
end

Dir.mktmpdir('arena-core-tests-') do |directory|
  bots = names.each_with_object({}) { |name, entries| entries[name] = __FILE__ }
  plugin = FakePlugin.new
  output = File.join(directory, 'run')
  summary = Arena::Tournament.new(plugin: plugin, bots: bots, output: output, workers: 2).run
  assert(plugin.maximum_active == 2)
  assert(summary[:status] == 'completed_with_errors' && summary[:completed_games] == 6 && summary[:failed_games] == 1)
  assert(summary[:matches].map { |match| match[:id] } == (1..6).to_a)
  assert(summary[:rankings].sum { |row| row[:games] } == 10)
  assert(JSON.parse(File.read(File.join(output, 'tournament.json')))['origin'] == 'local')
  assert(Dir.glob(File.join(output, '**', 'replay.json')).length == 5)
  assert(summary[:matches].reject { |match| match[:error] }.all? do |match|
    view = match[:view]
    view[:interface_version] == 1 && [:replay, :metadata, :details].all? { |key| File.file?(File.join(output, view[key])) }
  end)
  begin
    Arena::Tournament.new(plugin: FakePlugin.new, bots: bots, output: output).run
    raise 'Expected existing-output rejection'
  rescue Arena::Error => error
    assert(error.message.include?('already exists'))
  end
end
puts 'PASS bounded parallel workers, error isolation, atomic archives, UI references, and overwrite protection'

Dir.mktmpdir('arena-caribbean-tests-') do |directory|
  bots = {}
  {'wait' => 'WAIT', 'move' => 'MOVE 11 10', 'invalid' => 'INVALID'}.each do |name, command|
    path = File.join(directory, name)
    File.write(path, "#!/usr/bin/env ruby\nSTDOUT.sync = true\nwhile count = STDIN.gets\n  entities = STDIN.gets.to_i\n  entities.times { STDIN.gets }\n  count.to_i.times { puts #{command.inspect} }\nend\n")
    FileUtils.chmod(0755, path)
    bots[name] = path
  end
  plugin = Arena.load_plugin(File.join(__dir__, 'plugins', 'caribbean.rb'))
  catalog = CaribbeanMaps::Catalog.new
  assert(catalog.maps.length >= 1000, 'The bundled catalog must contain at least 1000 real maps')
  selected = catalog.select(seed: 41)
  assert(selected[:id] == catalog.select(seed: 41)[:id])
  copied = catalog.initial_state(selected)
  copied[:ships].first[6] = 1
  assert(selected[:initial][:ships].first[6] == 100, 'Games must not mutate shared catalog states')
  output = File.join(directory, 'run')
  summary = Arena::Tournament.new(plugin: plugin, bots: bots, output: output, workers: 2,
                                   options: {'ships' => 1, 'turn_ms' => 250, 'first_turn_ms' => 1500}).run
  assert(summary[:status] == 'completed' && summary[:completed_games] == 6 && summary[:failed_games].zero?)
  assert(summary[:forfeit_games] == 4)
  assert(summary[:rankings].find { |row| row[:bot] == 'invalid' }[:forfeits] == 4)
  binary = File.join(directory, 'validation-engine')
  Simulator.build(File.expand_path('../simulator/main.cpp', __dir__), binary)
  summary[:matches].each do |match|
    replay_path = File.join(output, match[:view][:replay])
    replay = Simulator::Replay.new(replay_path)
    assert(replay.data['origin'] == 'local')
    assert(replay.validate(binary)[:passed], "Raw replay mismatch: #{match[:id]}")
    assert(replay.validate(binary, resolved_moves: true)[:passed], "Resolved replay mismatch: #{match[:id]}")
    assert(replay.move_cases.all? { |entry| %w[WAIT FASTER SLOWER PORT STARBOARD].include?(entry[:expected]) })
    metadata = JSON.parse(File.read(File.join(output, match[:view][:metadata])))
    assert(metadata['schema_version'] == 1 && metadata['origin'] == 'local' && metadata['replay_url'].nil?)
    assert(metadata['players'].map { |player| player['nickname'] } == match[:players])
    assert(metadata['ships'] == 1 && replay.initial[:ships].length == 2, 'Explicit ships must override random selection')
    selected = catalog.select(seed: match[:seed], ships: 1)
    assert(CaribbeanMaps.state_id(replay.initial) == selected[:id], 'Fixed-size games must use intact captured maps')
    assert(metadata['source_map']['id'] == selected[:id])
  end
  random_output = File.join(directory, 'random-fleets')
  random_plugin = Arena.load_plugin(File.join(__dir__, 'plugins', 'caribbean.rb'))
  random_summary = Arena::Tournament.new(plugin: random_plugin, bots: bots.reject { |name, _path| name == 'invalid' },
                                          output: random_output, rounds: 3, seed: 1, workers: 2,
                                          options: {'turn_ms' => 250, 'first_turn_ms' => 1500}).run
  assert(random_summary[:failed_games].zero? && random_summary[:forfeit_games].zero?)
  observed = Hash.new { |entries, seed| entries[seed] = [] }
  random_summary[:matches].each do |match|
    replay = Simulator::Replay.new(File.join(random_output, match[:view][:replay]))
    selected = catalog.select(seed: match[:seed])
    expected = selected[:ships]
    assert(expected == Random.new(match[:seed]).rand(1..3))
    counts = [0, 1].map { |owner| replay.initial[:ships].count { |ship| ship[1] == owner } }
    assert(counts == [expected, expected], 'Default fleets must be seeded and equal for both players')
    assert(replay.data['frames'].first['view'].lines[3].split[2].to_i == expected)
    metadata = JSON.parse(File.read(File.join(random_output, match[:view][:metadata])))
    details = JSON.parse(File.read(File.join(random_output, match[:view][:details])))
    assert(metadata['ships'] == expected && details['configuration']['ships'] == expected)
    assert(CaribbeanMaps.state_id(replay.initial) == selected[:id], 'Captured entities must not be generated or altered')
    assert(metadata['source_map'] == replay.data['source_map'])
    assert(metadata['source_map'] == details['configuration']['source_map'])
    assert(metadata['source_map']['game_id'] == selected[:sources].first[:game_id])
    assert(metadata['source_map']['capture_sha256'] == selected[:sources].first[:capture_sha256])
    assert(metadata['source_map']['catalog_sha256'] == catalog.sha256)
    assert(replay.data['frames'].first['view'].lines[3].split.map(&:to_i) == selected[:header])
    assert(replay.data['refereeInput'].include?("ships=#{expected}"))
    assert(replay.validate(binary)[:passed] && replay.validate(binary, resolved_moves: true)[:passed])
    observed[match[:seed]] << selected[:id]
  end
  assert(observed.values.all? { |ids| ids.length == 2 && ids.uniq.length == 1 }, 'Home/away captured maps must match')
  assert(random_summary[:matches].map { |match| catalog.select(seed: match[:seed])[:ships] }.uniq.sort == [1, 2, 3])
  public_fixtures = File.join(directory, 'public-fixtures')
  FileUtils.mkdir_p(public_fixtures)
  frame = JSON.parse(File.read(File.join(output, summary[:matches].first[:view][:replay])))['frames'].first
  [100, 101].each do |game_id|
    game_directory = File.join(public_fixtures, game_id.to_s)
    FileUtils.mkdir_p(game_directory)
    File.write(File.join(game_directory, 'replay.json'), JSON.generate('gameId' => game_id, 'frames' => [frame]))
  end
  fixture_catalog = File.join(directory, 'deduplicated-maps.json')
  built = CaribbeanMaps.build(public_fixtures, fixture_catalog)
  assert(built[:captured_games] == 2 && built[:unique_maps] == 1)
  deduplicated = CaribbeanMaps::Catalog.new(fixture_catalog)
  assert(deduplicated.maps.first[:sources].map { |source| source[:game_id] } == [100, 101])
  begin
    deduplicated.select(seed: 1, ships: 3)
    raise 'A missing fleet-size pool must not generate a map'
  rescue Simulator::Error => error
    assert(error.message.include?('No captured maps'))
  end
  begin
    CaribbeanMaps::Catalog.new(File.join(directory, 'missing-maps.json'))
    raise 'A missing catalog must not generate maps'
  rescue Simulator::Error => error
    assert(error.message.include?('Cannot load'))
  end
  corrupted = JSON.parse(File.read(fixture_catalog))
  corrupted['maps'].first['initial']['ships'].first[2] += 1
  File.write(fixture_catalog, JSON.generate(corrupted))
  begin
    CaribbeanMaps::Catalog.new(fixture_catalog)
    raise 'A corrupted captured state must be rejected'
  rescue Simulator::Error => error
    assert(error.message.include?('Invalid captured-map'))
  end
  begin
    CaribbeanMaps.build(output, File.join(directory, 'not-public.json'))
    raise 'Local arena captures must not enter the real-map catalog'
  rescue Simulator::Error => error
    assert(error.message.include?('Local replay'))
  end
  begin
    random_plugin.prepare(bots: {}, directory: directory, options: {'ships' => nil})
    raise 'Explicit null must not be treated as an omitted ships option'
  rescue ArgumentError => error
    assert(error.message.include?('ships'))
  end
  puts 'PASS real captured maps, seeded fleets, parallel home/away identity, fixed-size filtering, and provenance'
  out, err = StringIO.new, StringIO.new
  assert(Arena::CLI.run(['results', '--input', output], out: out, err: err).zero?, err.string)
  assert(JSON.parse(out.string)['completed_games'] == 6)
  out, err = StringIO.new, StringIO.new
  assert(Arena::CLI.run(['list', '--bot', "wait=#{bots['wait']}", '--bot', "move=#{bots['move']}"], out: out, err: err).zero?)
  assert(JSON.parse(out.string).length == 2)
  out, err = StringIO.new, StringIO.new
  assert(Arena::CLI.run(['run', '--workers', '0'], out: out, err: err) == 1)
  assert(err.string.include?('Workers'))
  out, err = StringIO.new, StringIO.new
  single_output = File.join(directory, 'single')
  arguments = ['match', '--bot', "wait=#{bots['wait']}", '--bot', "invalid=#{bots['invalid']}",
               '--option', 'ships=1', '--option', 'first_turn_ms=1500', '--output', single_output]
  assert(Arena::CLI.run(arguments, out: out, err: err) == 1, 'A bot forfeit must return nonzero')
  single = JSON.parse(out.string)
  assert(single['completed_games'] == 1 && single['forfeit_games'] == 1 && single['failed_games'].zero?)
  assert(single['rankings'].find { |row| row['bot'] == 'wait' }['wins'] == 1)
end
puts 'PASS real persistent bots, MOVE keyframes, forfeit captures, raw/resolved replay round trips, and CLI results'
