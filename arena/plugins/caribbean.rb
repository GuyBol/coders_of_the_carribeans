require_relative '../../simulator/match'
require_relative 'caribbean_maps'

class Plugin
  def game
    'coders-of-the-caribbean'
  end

  def prepare(bots:, directory:, options:)
    unknown = options.keys - %w[ships maps turn_ms first_turn_ms]
    raise ArgumentError, "Unknown Caribbean options: #{unknown.join(', ')}" unless unknown.empty?
    @ships = options['ships']
    @turn_ms = options.fetch('turn_ms', 50)
    @first_turn_ms = options.fetch('first_turn_ms', 1000)
    if options.key?('ships') && !(@ships.is_a?(Integer) && (1..3).cover?(@ships))
      raise ArgumentError, 'ships must be an integer from 1 to 3'
    end
    unless [@turn_ms, @first_turn_ms].all? { |value| value.is_a?(Numeric) && value.finite? && value > 0 }
      raise ArgumentError, 'turn_ms and first_turn_ms must be positive finite numbers'
    end
    catalog_path = options.fetch('maps', CaribbeanMaps::DEFAULT_PATH)
    raise ArgumentError, 'maps must be a nonempty catalog path' unless catalog_path.is_a?(String) && !catalog_path.empty?
    @maps = CaribbeanMaps::Catalog.new(catalog_path)
    (@ships ? [@ships] : [1, 2, 3]).each do |ships|
      raise ArgumentError, "No captured maps with #{ships} ships per player" unless @maps.maps.any? { |map| map[:ships] == ships }
    end
    @engine = File.join(directory, 'engine')
    @navigation = File.join(directory, 'navigation')
    Simulator.build(File.expand_path('../../simulator/main.cpp', __dir__), @engine)
    Simulator.build(File.expand_path('../../simulator/test.cpp', __dir__), @navigation)
    @commands = {}
    @sources = bots
    bots.each_with_index do |(name, path), index|
      path = File.expand_path(path)
      if File.extname(path) == '.cpp'
        executable = File.join(directory, "bot#{index}")
        Simulator.build(path, executable)
      else
        raise ArgumentError, "Bot must be executable: #{path}" unless File.executable?(path)
        executable = path
      end
      @commands[name] = [executable]
    end
  end

  def play(players:, seed:, match_id:)
    map = @maps.select(seed: seed, ships: @ships)
    ships = map[:ships]
    initial = @maps.initial_state(map)
    source = map[:sources].first
    source_map = {id: map[:id], game_id: source[:game_id], capture_sha256: source[:capture_sha256],
                  map_seed: map[:header].last, catalog_sha256: @maps.sha256}
    log = Simulator.match(@engine, initial, players.map { |name| @commands.fetch(name) },
                          turn_ms: @turn_ms, first_turn_ms: @first_turn_ms)
    log[:configuration] = {seed: seed, ships: ships, source_map: source_map, bots: players,
                           turn_ms: @turn_ms, first_turn_ms: @first_turn_ms}
    effective = effective_actions(log)
    frames = [{'agentId' => -1, 'keyframe' => true, 'view' => view(initial, map[:header], {})}]
    before = initial
    log[:turns].each_with_index do |turn, index|
      2.times do |owner|
        commands = turn[:actions].to_h
        ids = before[:ships].select { |ship| ship[1] == owner && ship[6] > 0 }.map(&:first).sort
        forfeit = log[:forfeits].find { |entry| entry[:player] == owner && entry[:turn] == before[:turn] }
        frames << {'agentId' => owner, 'keyframe' => owner == 1,
                   'view' => owner.zero? ? "#{turn[:turn] * 2 - 1}\n" : view(turn[:state], map[:header], effective[index]),
                   'stdout' => ids.map { |id| commands.fetch(id) }.join("\n") + "\n",
                   'gameInformation' => forfeit ? "invalid local bot: #{forfeit[:error]}" : ''}
      end
      before = turn[:state]
    end
    agents = players.each_with_index.map do |name, index|
      {'index' => index, 'agentId' => index, 'codingamer' => {'pseudo' => name}}
    end
    replay = {'gameId' => match_id, 'agents' => agents, 'scores' => log[:scores],
              'ranks' => log[:ranks], 'frames' => frames, 'source_map' => source_map,
              'refereeInput' => "local seed=#{seed} ships=#{ships} source_game=#{source[:game_id]}"}
    metadata = {'schema_version' => 1, 'puzzle' => game, 'game_id' => match_id,
                'fetched_at' => Time.now.utc.iso8601, 'requested_by' => nil, 'replay_url' => nil,
                'frame_count' => frames.length, 'referee_input' => replay['refereeInput'], 'battle' => nil,
                'seed' => seed, 'ships' => ships, 'source_map' => source_map,
                'engine_sha256' => Digest::SHA256.file(File.expand_path('../../simulator/engine.hpp', __dir__)).hexdigest,
                'players' => players.each_with_index.map do |name, index|
                  {'index' => index, 'agent_id' => index, 'user_id' => nil, 'nickname' => name,
                   'public_handle' => nil, 'rank' => log[:ranks][index], 'score' => log[:scores][index],
                   'source_sha256' => Digest::SHA256.file(@sources.fetch(name)).hexdigest}
                end}
    {scores: log[:scores], winner: log[:winner], reason: log[:reason], forfeits: log[:forfeits],
     replay: replay, metadata: metadata, details: log}
  end

  private

  def effective_actions(log)
    inputs = []
    locations = []
    before = log[:initial]
    actions = log[:turns].each_with_index.map do |turn, index|
      effective = {}
      turn[:actions].each do |id, command|
        fields = command.split
        effective[id] = fields.first.upcase
        if effective[id] == 'MOVE'
          ship = before[:ships].find { |entry| entry.first == id }
          inputs << (ship[2, 4] + fields[1, 2]).join(' ')
          locations << [index, id]
        end
      end
      before = turn[:state]
      effective
    end
    unless inputs.empty?
      output, error, status = Open3.capture3(@navigation, '--move-cases', stdin_data: inputs.join("\n") + "\n")
      resolved = output.lines.map(&:strip)
      raise Simulator::Error, "MOVE resolution failed: #{error}" unless status.success? && resolved.length == locations.length
      locations.zip(resolved).each { |(index, id), command| actions[index][id] = command }
    end
    actions
  end

  def view(state, header, actions)
    if state[:turn].zero?
      lines = ['0', 'CodersOfTheCaribbean', '2', header.join(' ')]
    else
      lines = ["#{state[:turn] * 2} endReached"]
    end
    2.times do |owner|
      lines << owner.to_s
      state[:ships].select { |ship| ship[1] == owner }.sort_by(&:first).each do |id, _owner, column, row, direction, speed, rum, *_rest|
        bow = Simulator.neighbor([column, row], direction)
        stern = Simulator.neighbor([column, row], (direction + 3) % 6)
        lines << "#{id} #{row} #{column} #{direction} #{rum} #{speed} #{actions.fetch(id, 'WAIT')} #{bow[1]} #{bow[0]} #{stern[1]} #{stern[0]} ;"
      end
    end
    lines << state[:balls].length.to_s
    state[:balls].each do |id, column, row, owner, remaining, origin_column, origin_row, initial|
      lines << [id, row, column, origin_row, origin_column, initial, remaining, owner].join(' ')
    end
    lines << state[:mines].length.to_s
    state[:mines].each { |id, column, row| lines << [id, row, column].join(' ') }
    lines << state[:barrels].length.to_s
    state[:barrels].each { |id, column, row, rum| lines << [id, row, column, rum].join(' ') }
    lines << '0'
    lines.join("\n") + "\n"
  end
end