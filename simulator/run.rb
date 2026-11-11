require 'optparse'
require 'tmpdir'
require 'digest'
require 'time'
require_relative 'match'

module Simulator
  def self.run(arguments)
    options = {mode: 'raw', seed: 1, ships: 3, turn_ms: 50, first_turn_ms: 1000}
    parser = OptionParser.new do |flags|
      flags.banner = 'Usage: ruby simulator/run.rb COMMAND [options]'
      flags.separator 'Commands: validate, match'
      flags.on('--archive PATH', 'Capture repository, games directory, or one replay.json') { |value| options[:archive] = value }
      flags.on('--mode MODE', %w[raw resolved both], 'Validation: raw (default), resolved, or both') { |value| options[:mode] = value }
      flags.on('--report PATH', 'Write complete validation results as JSON') { |value| options[:report] = value }
      flags.on('--bot0 PATH', 'Player 0 executable or C++ source') { |value| options[:bot0] = value }
      flags.on('--bot1 PATH', 'Player 1 executable or C++ source') { |value| options[:bot1] = value }
      flags.on('--initial PATH', 'Start a match from a captured replay initial state') { |value| options[:initial] = value }
      flags.on('--seed N', Integer, 'Local map seed (default: 1; not CodinGame seed compatible)') { |value| options[:seed] = value }
      flags.on('--ships N', Integer, 'Ships per player for generated maps (1 to 3)') { |value| options[:ships] = value }
      flags.on('--turn-ms N', Float, 'Per-player time budget after the first turn (default: 50)') { |value| options[:turn_ms] = value }
      flags.on('--first-turn-ms N', Float, 'First-turn time budget (default: 1000)') { |value| options[:first_turn_ms] = value }
      flags.on('--output PATH', 'Write a complete local match log') { |value| options[:output] = value }
      flags.on('-h', '--help') { options[:help] = true }
    end
    command = arguments.first && !arguments.first.start_with?('-') ? arguments.shift : nil
    parser.parse!(arguments)
    if options[:help] || command.nil?
      puts parser
      return 0
    end
    raise Error, 'Command must be validate or match' unless %w[validate match].include?(command)
    raise Error, "Unexpected arguments: #{arguments.join(' ')}" unless arguments.empty?
    if command == 'validate'
      raise Error, 'validate requires --archive PATH' unless options[:archive]
    else
      raise Error, 'match requires --bot0 PATH and --bot1 PATH' unless options[:bot0] && options[:bot1]
      [:turn_ms, :first_turn_ms].each do |key|
        raise Error, 'Time budgets must be positive finite numbers' unless options[key].finite? && options[key] > 0
      end
    end
    Dir.mktmpdir('caribbean-simulator-') do |directory|
      binary = File.join(directory, 'engine')
      build(File.join(__dir__, 'main.cpp'), binary)
      if command == 'validate'
        validate_archive(binary, options)
      else
        commands = [:bot0, :bot1].map.with_index do |key, index|
          source = File.expand_path(options[key])
          raise Error, "Bot does not exist: #{source}" unless File.file?(source)
          if File.extname(source) == '.cpp'
            executable = File.join(directory, "bot#{index}")
            build(source, executable)
            [executable]
          else
            [source]
          end
        end
        initial = options[:initial] ? Replay.new(options[:initial]).initial : generate(options[:seed], options[:ships])
        log = match(binary, initial, commands, turn_ms: options[:turn_ms], first_turn_ms: options[:first_turn_ms])
        log[:configuration] = {seed: options[:initial] ? nil : options[:seed], initial_replay: options[:initial],
                               bots: [options[:bot0], options[:bot1]], turn_ms: options[:turn_ms], first_turn_ms: options[:first_turn_ms]}
        write_json(options[:output], log) if options[:output]
        puts JSON.pretty_generate(log.reject { |key, _value| [:initial, :turns, :bot_stderr].include?(key) }.merge(turns: log[:turns].length))
        log[:forfeits].empty? ? 0 : 1
      end
    end
  rescue Error, OptionParser::ParseError, SystemCallError => error
    warn "Error: #{error.message}"
    1
  end

  def self.write_json(path, value)
    FileUtils.mkdir_p(File.dirname(File.expand_path(path)))
    File.write(path, JSON.pretty_generate(value) + "\n")
  end

  def self.validate_archive(binary, options)
    archive = File.expand_path(options[:archive])
    paths = File.file?(archive) ? [archive] : Dir.glob(File.join(archive, '**', 'replay.json')).sort
    raise Error, 'No captured replay.json files found' if paths.empty?
    modes = options[:mode] == 'both' ? ['raw', 'resolved'] : [options[:mode]]
    results = paths.flat_map do |path|
      begin
        replay = Replay.new(path)
        modes.map do |mode|
          result = replay.validate(binary, resolved_moves: mode == 'resolved')
          result[:mode] = mode
          result[:capture_sha256] = Digest::SHA256.file(path).hexdigest
          result[:expected_turns] = replay.transitions.length
          warn "#{result[:passed] ? 'PASS' : 'FAIL'} #{result[:game_id]} #{mode}: #{result[:checked_turns]}/#{result[:expected_turns]} turns"
          result
        end
      rescue Error, SystemCallError => error
        [{passed: false, capture: path, error: error.message}]
      end
    end
    summary = {
      generated_at: Time.now.utc.iso8601, archive: archive, mode: options[:mode], games: paths.length,
      passed: results.all? { |result| result[:passed] },
      raw_passed: results.count { |result| result[:mode] == 'raw' && result[:passed] },
      resolved_passed: results.count { |result| result[:mode] == 'resolved' && result[:passed] },
      checked_turns: results.sum { |result| result.fetch(:checked_turns, 0) },
      engine_sha256: Digest::SHA256.file(File.join(__dir__, 'engine.hpp')).hexdigest,
      results: results
    }
    write_json(options[:report], summary) if options[:report]
    puts JSON.pretty_generate(summary.reject { |key, _value| key == :results })
    summary[:passed] ? 0 : 1
  end
end

exit Simulator.run(ARGV.dup) if $PROGRAM_NAME == __FILE__