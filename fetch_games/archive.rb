require 'fileutils'
require 'tmpdir'
require_relative 'api'

module FetchGames
  class Archive
    def initialize(root, client)
      @root = File.expand_path(root)
      @client = client
    end

    def save(game_id, battle: nil, requested_by: nil, refresh: false)
      game_id = FetchGames.positive_id(game_id)
      games = File.join(@root, PUZZLE, 'games')
      destination = File.join(games, game_id.to_s)
      if File.exist?(destination) && !refresh
        validate_existing(destination, game_id)
        return :skipped
      end
      replay = @client.game(game_id)
      agents = replay['agents']
      unless agents.is_a?(Array) && !agents.empty? && agents.all? { |agent| agent.is_a?(Hash) }
        raise Error, "Game #{game_id}: replay does not contain player metadata"
      end
      opponents = battle && battle['players'].is_a?(Array) ? battle['players'] : []
      players = agents.each_with_index.map do |agent, fallback_index|
        index = agent.fetch('index', fallback_index)
        unless index.is_a?(Integer) && index >= 0 && index < agents.length
          raise Error, "Game #{game_id}: invalid replay agent index"
        end
        details = opponents.find { |player| player['playerAgentId'] == agent['agentId'] } || {}
        profile = agent['codingamer'].is_a?(Hash) ? agent['codingamer'] : {}
        {
          'index' => index, 'agent_id' => agent['agentId'],
          'user_id' => profile['userId'] || details['userId'],
          'nickname' => profile['pseudo'] || details['nickname'],
          'public_handle' => profile['publicHandle'] || details['publicHandle'],
          'rank' => replay['ranks'].is_a?(Array) ? replay['ranks'][index] : nil,
          'score' => replay['scores'].is_a?(Array) ? replay['scores'][index] : nil
        }
      end
      metadata = {
        'schema_version' => 1, 'puzzle' => PUZZLE, 'game_id' => game_id,
        'fetched_at' => Time.now.utc.iso8601, 'requested_by' => requested_by,
        'replay_url' => "https://www.codingame.com/replay/#{game_id}",
        'frame_count' => replay['frames'].length, 'players' => players,
        'referee_input' => replay['refereeInput'], 'battle' => battle
      }
      FileUtils.mkdir_p(games)
      temporary = Dir.mktmpdir('.capture-', games)
      begin
        File.write(File.join(temporary, 'replay.json'), JSON.pretty_generate(replay) + "\n")
        File.write(File.join(temporary, 'metadata.json'), JSON.pretty_generate(metadata) + "\n")
        if File.exist?(destination)
          unless refresh
            validate_existing(destination, game_id)
            return :skipped
          end
          backup = temporary + '-previous'
          File.rename(destination, backup)
          begin
            File.rename(temporary, destination)
          rescue StandardError
            File.rename(backup, destination)
            raise
          end
          FileUtils.remove_entry(backup)
        else
          File.rename(temporary, destination)
        end
      ensure
        FileUtils.remove_entry(temporary) if File.exist?(temporary)
      end
      :saved
    end

    private

    def validate_existing(directory, game_id)
      metadata = JSON.parse(File.read(File.join(directory, 'metadata.json')))
      replay = JSON.parse(File.read(File.join(directory, 'replay.json')))
      unless metadata.is_a?(Hash) && replay.is_a?(Hash) && metadata['schema_version'] == 1 &&
             metadata['puzzle'] == PUZZLE && metadata['game_id'] == game_id &&
             metadata['players'].is_a?(Array) && !metadata['players'].empty? &&
             replay['gameId'] == game_id && replay['frames'].is_a?(Array)
        raise Error, "Incomplete or invalid capture #{directory}; use --refresh to replace it"
      end
    rescue JSON::ParserError, Errno::ENOENT, Errno::ENOTDIR
      raise Error, "Incomplete or invalid capture #{directory}; use --refresh to replace it"
    end
  end
end
