require 'optparse'
require_relative 'archive'

module FetchGames
  class CLI
    def self.run(arguments, out: $stdout, err: $stderr, client: nil)
      new(out, err, client).run(arguments.dup)
    rescue Error, OptionParser::ParseError, SystemCallError => error
      err.puts "Error: #{error.message}"
      1
    end

    def initialize(out, err, client)
      @out = out
      @err = err
      @client = client
    end

    def run(arguments)
      options = {limit: 20, interval: 0.5, refresh: false}
      parser = OptionParser.new do |flags|
        flags.banner = 'Usage: ruby fetch_games/fetch.rb COMMAND [options]'
        flags.separator 'Commands: leaderboard, lookup, fetch'
        flags.on('--player NAME', 'Exact nickname, including your own account') { |value| options[:nickname] = value }
        flags.on('--user-id ID', 'Numeric CodinGame user ID') { |value| options[:user_id] = FetchGames.positive_id(value) }
        flags.on('--handle HANDLE', 'Public profile handle') { |value| options[:handle] = value }
        flags.on('--agent-id ID', 'Fetch recent games for an arena agent directly') { |value| options[:agent_id] = FetchGames.positive_id(value) }
        flags.on('--game-id ID', 'Fetch one replay directly') { |value| options[:game_id] = FetchGames.positive_id(value) }
        flags.on('--top N', 'Fetch games from the top N leaderboard players') { |value| options[:top] = FetchGames.positive_id(value) }
        flags.on('--limit N', 'Games per player, or leaderboard rows (default: 20)') { |value| options[:limit] = FetchGames.positive_id(value) }
        flags.on('--output PATH', 'Dedicated local game archive or repository (required for fetch)') { |value| options[:output] = value }
        flags.on('--refresh', 'Replace existing captures only after a successful download') { options[:refresh] = true }
        flags.on('--interval SECONDS', Float, 'Minimum gap between API requests (default: 0.5)') { |value| options[:interval] = value }
        flags.on('-h', '--help') { options[:help] = true }
      end
      command = arguments.first && !arguments.first.start_with?('-') ? arguments.shift : nil
      parser.parse!(arguments)
      if options[:help] || (command.nil? && arguments.empty?)
        @out.puts parser
        return 0
      end
      raise Error, "Unknown command #{command.inspect}; use --help" unless %w[leaderboard lookup fetch].include?(command)
      raise Error, "Unexpected arguments: #{arguments.join(' ')}" unless arguments.empty?
      unless options[:interval].finite? && options[:interval] >= 0
        raise Error, '--interval must be a finite nonnegative number'
      end
      selectors = [:nickname, :user_id, :handle, :agent_id, :game_id, :top].select { |key| options.key?(key) }
      if command == 'leaderboard'
        raise Error, 'leaderboard does not accept player or game selectors' unless selectors.empty?
      else
        raise Error, 'Specify exactly one of --player, --user-id, --handle, --agent-id, --game-id, or --top' unless selectors.length == 1
        if command == 'lookup' && ![:nickname, :user_id, :handle].include?(selectors.first)
          raise Error, 'lookup requires --player, --user-id, or --handle'
        end
      end
      raise Error, 'fetch requires --output PATH' if command == 'fetch' && options[:output].to_s.empty?
      @client ||= Client.new(interval: options[:interval])
      if command == 'leaderboard'
        board = @client.leaderboard
        emit('puzzle' => PUZZLE, 'total_players' => board['count'],
             'returned_players' => board['users'].length, 'users' => board['users'].first(options[:limit]))
        return 0
      end
      if command == 'lookup'
        emit(resolve_player(options))
        return 0
      end
      fetch(options)
    end

    private

    def resolve_player(options)
      @client.player(nickname: options[:nickname], user_id: options[:user_id], handle: options[:handle])
    end

    def emit(value)
      @out.puts JSON.pretty_generate(value)
    end

    def fetch(options)
      archive = Archive.new(options[:output], @client)
      summary = {'saved' => 0, 'skipped' => 0, 'failed' => 0, 'errors' => []}
      seen = {}
      if options[:game_id]
        capture(archive, options[:game_id], nil, nil, options, summary, seen)
      else
        players = if options[:top]
                    board = @client.leaderboard
                    if board['users'].length < options[:top]
                      raise Error, "Requested #{options[:top]} players, but the API returned only #{board['users'].length}"
                    end
                    board['users'].first(options[:top]).map do |entry|
                      {'agent_id' => entry['agentId'], 'user_id' => entry.dig('codingamer', 'userId'),
                       'nickname' => entry['pseudo'], 'rank' => entry['globalRank'] || entry['rank']}
                    end
                  elsif options[:agent_id]
                    [{'agent_id' => options[:agent_id]}]
                  else
                    [resolve_player(options)]
                  end
        players.each do |player|
          begin
            unless player['agent_id']
              raise Error, "No arena agent found for #{player['nickname']}; submit to the arena or supply --agent-id"
            end
            battles = @client.battles(player['agent_id']).select { |battle| battle['done'] == true }
            unique = battles.uniq { |battle| battle['gameId'] }.first(options[:limit])
            @err.puts "Agent #{player['agent_id']}: #{unique.length} completed recent games selected"
            unique.each do |battle|
              capture(archive, battle['gameId'], battle, player, options, summary, seen)
            end
          rescue Error => error
            failure(summary, error.message)
          end
        end
      end
      emit(summary.merge('archive' => File.expand_path(options[:output])))
      summary['failed'].zero? ? 0 : 1
    end

    def capture(archive, game_id, battle, player, options, summary, seen)
      game_id = FetchGames.positive_id(game_id)
      return if seen[game_id]
      seen[game_id] = true
      result = archive.save(game_id, battle: battle, requested_by: player, refresh: options[:refresh])
      summary[result.to_s] += 1
      @err.puts "Game #{game_id}: #{result}"
    rescue Error, SystemCallError => error
      failure(summary, "Game #{game_id}: #{error.message}")
    end

    def failure(summary, message)
      summary['failed'] += 1
      summary['errors'] << message
      @err.puts "Failed: #{message}"
    end
  end
end

exit FetchGames::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
