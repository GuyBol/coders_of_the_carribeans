require 'json'
require 'fileutils'
require 'tmpdir'
require 'time'
require 'digest'
require 'securerandom'

module Arena
  class Error < StandardError; end

  def self.schedule(names, rounds: 1, seed: 1)
    raise Error, 'At least two uniquely named bots are required' unless names.length >= 2 && names.uniq.length == names.length
    raise Error, 'Rounds must be a positive integer' unless rounds.is_a?(Integer) && rounds > 0
    raise Error, 'Seed must be an integer' unless seed.is_a?(Integer)
    matches = []
    rounds.times do |round|
      names.combination(2).each_with_index do |pair, pair_index|
        map_seed = seed + round * names.length * (names.length - 1) / 2 + pair_index
        [pair, pair.reverse].each do |players|
          matches << {id: matches.length + 1, round: round + 1, seed: map_seed, players: players}
        end
      end
    end
    matches
  end

  def self.rankings(names, matches, initial: 1500.0, k: 32.0)
    unless initial.is_a?(Numeric) && initial.finite? && k.is_a?(Numeric) && k.finite? && k > 0
      raise Error, 'Initial rating must be finite and Elo K must be positive and finite'
    end
    rows = names.each_with_object({}) do |name, table|
      table[name] = {bot: name, rating: initial.to_f, games: 0, wins: 0, draws: 0, losses: 0, forfeits: 0, seats: [0, 0]}
    end
    matches.sort_by { |match| match[:id] }.each do |match|
      next if match[:error]
      first, second = match[:players].map { |name| rows.fetch(name) }
      expected = 1.0 / (1.0 + 10.0**((second[:rating] - first[:rating]) / 400.0))
      actual = match[:winner].nil? ? 0.5 : (match[:winner].zero? ? 1.0 : 0.0)
      change = k * (actual - expected)
      first[:rating] += change
      second[:rating] -= change
      [first, second].each_with_index do |row, seat|
        row[:games] += 1
        row[:seats][seat] += 1
        outcome = match[:winner].nil? ? :draws : (match[:winner] == seat ? :wins : :losses)
        row[outcome] += 1
        row[:forfeits] += 1 if match.fetch(:forfeits, []).any? { |entry| entry[:player] == seat }
      end
    end
    rows.values.sort_by { |row| [-row[:rating], row[:bot]] }.each_with_index.map do |row, index|
      row.merge(rank: index + 1, rating: row[:rating].round(3))
    end
  end

  def self.write_json(path, value)
    temporary = path + '.tmp'
    File.write(temporary, JSON.pretty_generate(value) + "\n")
    File.rename(temporary, path)
  end

  def self.load_plugin(path)
    path = File.expand_path(path)
    namespace = Module.new
    namespace.module_eval(File.read(path), path)
    plugin = namespace.const_get(:Plugin, false).new
    unless [:game, :prepare, :play].all? { |method| plugin.respond_to?(method) }
      raise Error, 'Plugin must implement game, prepare, and play'
    end
    raise Error, 'Plugin game must be a filesystem-safe identifier' unless /\A[a-z0-9][a-z0-9_-]*\z/.match(plugin.game.to_s)
    plugin
  rescue NameError => error
    raise Error, "Invalid plugin: #{error.message}"
  end

  class Tournament
    def initialize(plugin:, bots:, output:, rounds: 1, seed: 1, workers: 2,
                   options: {}, initial_rating: 1500.0, k: 32.0, progress: nil, single: false)
      raise Error, 'Workers must be an integer between 1 and 64' unless workers.is_a?(Integer) && (1..64).cover?(workers)
      raise Error, 'Plugin options must be an object' unless options.is_a?(Hash)
      @plugin, @bots, @output = plugin, bots, File.expand_path(output)
      @schedule = Arena.schedule(bots.keys, rounds: rounds, seed: seed)
      if single
        raise Error, 'A single match requires exactly two bots and one round' unless bots.length == 2 && rounds == 1
        @schedule = @schedule.first(1)
      end
      Arena.rankings(bots.keys, [], initial: initial_rating, k: k)
      @workers, @options, @initial_rating, @k, @progress = workers, options, initial_rating, k, progress
      @results = Array.new(@schedule.length)
      @mutex = Mutex.new
      @run_id = SecureRandom.uuid
      @started_at = Time.now.utc.iso8601
    end

    def run
      @bots.each_value { |path| raise Error, "Bot does not exist: #{path}" unless File.file?(path) }
      raise Error, "Output already exists; choose a new run directory: #{@output}" if File.exist?(@output)
      FileUtils.mkdir_p(File.dirname(@output))
      Dir.mkdir(@output)
      @status = 'running'
      snapshot
      begin
        Dir.mktmpdir('caribbean-arena-') do |directory|
          @plugin.prepare(bots: @bots, directory: directory, options: @options)
          queue = Queue.new
          @schedule.each_with_index { |match, index| queue << [match, index] }
          threads = Array.new([@workers, @schedule.length].min) do
            Thread.new do
              loop do
                begin
                  match, index = queue.pop(true)
                rescue ThreadError
                  break
                end
                result = execute(match)
                @mutex.synchronize do
                  @results[index] = result
                  snapshot
                  @progress.call(result, @results.compact.length, @schedule.length) if @progress
                end
              end
            end
          end
          begin
            threads.each(&:value)
          ensure
            threads.each(&:join)
          end
        end
        @status = @results.any? { |match| match[:error] } ? 'completed_with_errors' : 'completed'
      rescue StandardError => error
        @status = 'failed'
        @error = error.message
        raise
      ensure
        @finished_at = Time.now.utc.iso8601
        snapshot
      end
      summary
    end

    private

    def execute(match)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = @plugin.play(players: match[:players], seed: match[:seed], match_id: match[:id])
      unless result.is_a?(Hash) && result[:scores].is_a?(Array) && result[:scores].length == 2 &&
             result[:scores].all? { |score| score.is_a?(Numeric) && score.finite? } &&
             [nil, 0, 1].include?(result[:winner]) && result[:replay].is_a?(Hash) &&
             result[:replay]['frames'].is_a?(Array) && !result[:replay]['frames'].empty? &&
             result[:metadata].is_a?(Hash) && result.fetch(:forfeits, []).is_a?(Array) &&
             result.fetch(:forfeits, []).all? { |entry| entry.is_a?(Hash) && [0, 1].include?(entry[:player]) }
        raise Error, 'Plugin returned an invalid match result'
      end
      directory = File.join(@plugin.game, 'games', match[:id].to_s)
      destination = File.join(@output, directory)
      FileUtils.mkdir_p(File.dirname(destination))
      temporary = Dir.mktmpdir('.capture-', File.dirname(destination))
      begin
        replay = result[:replay].merge('origin' => 'local', 'tournament_id' => @run_id)
        metadata = result[:metadata].merge('origin' => 'local', 'tournament_id' => @run_id)
        Arena.write_json(File.join(temporary, 'replay.json'), replay)
        Arena.write_json(File.join(temporary, 'metadata.json'), metadata)
        Arena.write_json(File.join(temporary, 'match.json'), result.fetch(:details, {}))
        File.rename(temporary, destination)
      ensure
        FileUtils.remove_entry(temporary) if File.exist?(temporary)
      end
      match.merge(scores: result[:scores], winner: result[:winner], reason: result[:reason],
                  forfeits: result.fetch(:forfeits, []),
                  elapsed_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000,
                  view: {interface_version: 1, game: @plugin.game,
                         replay: File.join(directory, 'replay.json'),
                         metadata: File.join(directory, 'metadata.json'),
                         details: File.join(directory, 'match.json')})
    rescue StandardError => error
      match.merge(error: "#{error.class}: #{error.message}")
    end

    def summary
      matches = @results.compact
      {schema_version: 1, origin: 'local', tournament_id: @run_id, game: @plugin.game,
       status: @status, error: @error, started_at: @started_at, finished_at: @finished_at,
       output: @output, workers: @workers, options: @options,
       elo: {initial: @initial_rating, k: @k},
       bots: @bots.map { |name, path| {name: name, path: File.expand_path(path), sha256: Digest::SHA256.file(path).hexdigest} },
       planned_games: @schedule.length, completed_games: matches.length,
       failed_games: matches.count { |match| match[:error] },
       forfeit_games: matches.count { |match| !match.fetch(:forfeits, []).empty? },
       schedule: @schedule, matches: matches,
       rankings: Arena.rankings(@bots.keys, matches, initial: @initial_rating, k: @k)}
    end

    def snapshot
      Arena.write_json(File.join(@output, 'tournament.json'), summary)
    end
  end
end