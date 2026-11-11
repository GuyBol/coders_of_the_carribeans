require 'optparse'
require_relative 'arena'

module Arena
  class CLI
    def self.run(arguments, out: $stdout, err: $stderr)
      options = {bots: File.expand_path('../bots', __dir__), entries: {}, rounds: 1,
                 seed: 1, workers: 2, initial_rating: 1500.0, k: 32.0, settings: {},
                 plugin: File.join(__dir__, 'plugins', 'caribbean.rb')}
      parser = OptionParser.new do |flags|
        flags.banner = 'Usage: ruby arena/run.rb COMMAND [options]'
        flags.separator 'Commands: run (balanced tournament), match (single game), list, results'
        flags.on('--bots DIR', 'Discover each **/main.cpp beneath DIR (default: bots)') { |value| options[:bots] = value }
        flags.on('--bot NAME=PATH', 'Select a C++ source or executable; repeat for each bot') do |value|
          name, path = value.split('=', 2)
          unless name && /\A[a-zA-Z0-9][a-zA-Z0-9_.-]*\z/.match(name) && path && !path.empty?
            raise Error, '--bot requires NAME=PATH with an alphanumeric, dash, underscore, or dot name'
          end
          raise Error, "Duplicate bot name: #{name}" if options[:entries].key?(name)
          options[:entries][name] = File.expand_path(path)
        end
        flags.on('--rounds N', Integer, 'Home/away rounds per pair (default: 1)') { |value| options[:rounds] = value }
        flags.on('--seed N', Integer, 'First map seed (default: 1)') { |value| options[:seed] = value }
        flags.on('--workers N', Integer, 'Concurrent games, 1 to 64 (default: 2)') { |value| options[:workers] = value }
        flags.on('--output DIR', 'New directory for this tournament and its local captures') { |value| options[:output] = value }
        flags.on('--plugin FILE', 'Ruby game adapter (default: plugins/caribbean.rb)') { |value| options[:plugin] = value }
        flags.on('--option KEY=JSON', 'Game adapter option, e.g. ships=3 or turn_ms=100') do |value|
          key, setting = value.split('=', 2)
          raise Error, '--option requires KEY=JSON' if key.to_s.empty? || setting.nil?
          options[:settings][key] = JSON.parse(setting)
        end
        flags.on('--initial-rating N', Float, 'Initial Elo (default: 1500)') { |value| options[:initial_rating] = value }
        flags.on('--k N', Float, 'Elo update factor (default: 32)') { |value| options[:k] = value }
        flags.on('--input PATH', 'Tournament directory or tournament.json for results') { |value| options[:input] = value }
        flags.on('-h', '--help') { options[:help] = true }
      end
      arguments = arguments.dup
      command = arguments.first && !arguments.first.start_with?('-') ? arguments.shift : nil
      parser.parse!(arguments)
      if options[:help] || command.nil?
        out.puts parser
        return 0
      end
      raise Error, 'Command must be run, match, list, or results' unless %w[run match list results].include?(command)
      raise Error, "Unexpected arguments: #{arguments.join(' ')}" unless arguments.empty?
      if command == 'results'
        raise Error, 'results requires --input PATH' unless options[:input]
        path = File.directory?(options[:input]) ? File.join(options[:input], 'tournament.json') : options[:input]
        summary = JSON.parse(File.read(path))
        unless summary.is_a?(Hash) && summary['schema_version'] == 1 && summary['rankings'].is_a?(Array)
          raise Error, 'Not a supported tournament report'
        end
        out.puts JSON.pretty_generate(summary.reject { |key, _value| %w[schedule matches].include?(key) })
        return 0
      end
      bots = options[:entries].empty? ? discover(options[:bots]) : options[:entries]
      if command == 'list'
        out.puts JSON.pretty_generate(bots.map { |name, path| {name: name, path: path} })
        return 0
      end
      output = options[:output] || File.expand_path("../../local-arena-games/run-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(4)}", __dir__)
      plugin = Arena.load_plugin(options[:plugin])
      progress = lambda do |match, completed, total|
        outcome = match[:error] || (match[:winner].nil? ? 'draw' : "winner=#{match[:players][match[:winner]]}")
        err.puts "[#{completed}/#{total}] game #{match[:id]} #{match[:players].join(' vs ')} seed=#{match[:seed]}: #{outcome}"
      end
      summary = Tournament.new(plugin: plugin, bots: bots, output: output,
                               rounds: options[:rounds], seed: options[:seed], workers: options[:workers],
                               options: options[:settings], initial_rating: options[:initial_rating],
                               k: options[:k], progress: progress, single: command == 'match').run
      out.puts JSON.pretty_generate(summary.reject { |key, _value| [:schedule, :matches].include?(key) })
      summary[:failed_games].zero? && summary[:forfeit_games].zero? ? 0 : 1
    rescue Error, OptionParser::ParseError, JSON::ParserError, SystemCallError, ArgumentError => error
      err.puts "Error: #{error.message}"
      1
    rescue StandardError => error
      err.puts "Error: #{error.class}: #{error.message}"
      1
    end

    def self.discover(directory)
      root = File.expand_path(directory)
      raise Error, "Bots directory does not exist: #{root}" unless File.directory?(root)
      Dir.glob(File.join(root, '**', 'main.cpp')).sort.each_with_object({}) do |path, bots|
        relative = File.dirname(path.delete_prefix(root + '/'))
        name = relative == '.' ? File.basename(root) : relative.tr('/', '-')
        raise Error, "Duplicate discovered bot name: #{name}" if bots.key?(name)
        bots[name] = path
      end
    end
  end
end

exit Arena::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
