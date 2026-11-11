require 'json'
require 'net/http'
require 'time'
require 'uri'

module FetchGames
  PUZZLE = 'coders-of-the-caribbean'.freeze

  class Error < StandardError; end

  def self.positive_id(value)
    text = value.to_s
    raise Error, 'IDs must be positive integers' unless /\A[1-9]\d*\z/.match(text)
    text.to_i
  end

  class Client
    BASE_URL = 'https://www.codingame.com/services/'.freeze

    def initialize(interval: 0.5, retries: 2, transport: nil, sleeper: nil)
      @interval = interval
      @retries = retries
      @transport = transport || method(:request)
      @sleeper = sleeper || ->(seconds) { Kernel.sleep(seconds) }
      @last_request = nil
    end

    def call(service, arguments)
      attempts = 0
      loop do
        throttle
        response = @transport.call(URI.join(BASE_URL, service), JSON.generate(arguments))
        code = response.code.to_i
        if (code == 429 || (500..599).cover?(code)) && attempts < @retries
          retry_after = Float(response['Retry-After']) rescue nil
          delay = retry_after || 2**attempts
          @sleeper.call([[delay, 0].max, 30].min)
          attempts += 1
          next
        end
        unless (200..299).cover?(code)
          detail = if [401, 403].include?(code)
                     'access denied; this resource may not be public'
                   elsif code == 429
                     'rate limited; retry later'
                   else
                     'request failed'
                   end
          raise Error, "#{service}: HTTP #{code} (#{detail})"
        end
        begin
          return JSON.parse(response.body)
        rescue JSON::ParserError
          raise Error, "#{service}: response was not valid JSON"
        end
      end
    rescue IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
      raise Error, "#{service}: connection failed (#{error.class}); check network and TLS certificates"
    end

    def leaderboard(handle: nil)
      result = call('Leaderboards/getFilteredPuzzleLeaderboard', [PUZZLE, handle, 'global', {}])
      unless result.is_a?(Hash) && result['users'].is_a?(Array) &&
             result['users'].all? { |user| user.is_a?(Hash) }
        raise Error, 'Unexpected leaderboard response: expected an object with a users array'
      end
      result
    end

    def player(nickname: nil, user_id: nil, handle: nil)
      unless [nickname, user_id, handle].compact.length == 1
        raise Error, 'Specify exactly one nickname, user ID, or public handle'
      end
      if nickname
        results = call('Search/search', [nickname, 'en', nil])
        raise Error, 'Unexpected search response' unless results.is_a?(Array)
        matches = results.select do |entry|
          entry.is_a?(Hash) && entry['type'] == 'USER' && entry['name'].to_s.casecmp(nickname).zero?
        end
        raise Error, "No exact player match for #{nickname.inspect}; try a user ID or public handle" if matches.empty?
        raise Error, 'Ambiguous nickname; use a user ID or public handle' if matches.length > 1
        handle = matches.first['id']
      elsif user_id
        profile = call('CodinGamer/findCodinGamerPublicInformations', [FetchGames.positive_id(user_id)])
        unless profile.is_a?(Hash) && profile['userId'] == FetchGames.positive_id(user_id)
          raise Error, 'Unexpected public profile response'
        end
        handle = profile['publicHandle']
      end
      unless handle.is_a?(String) && /\A[0-9a-f]{20,64}\z/i.match(handle)
        raise Error, 'Invalid or missing public profile handle'
      end
      result = call('CodinGamer/findCodingamePointsStatsByHandle', [handle])
      profile = result.is_a?(Hash) ? result['codingamer'] : nil
      unless profile.is_a?(Hash) && profile['userId'] && profile['pseudo']
        raise Error, 'Player profile not found or unexpected profile response'
      end
      board = leaderboard(handle: handle)
      candidates = [board['codingamerUserRank'], *board['users']].compact
      rank = candidates.find do |entry|
        entry.is_a?(Hash) && entry.dig('codingamer', 'userId') == profile['userId']
      end
      {
        'nickname' => profile['pseudo'], 'user_id' => profile['userId'],
        'public_handle' => handle, 'agent_id' => rank && rank['agentId'],
        'rank' => rank && (rank['globalRank'] || rank['rank']), 'league' => rank && rank['league']
      }
    end

    def battles(agent_id)
      result = call('gamesPlayersRanking/findLastBattlesByAgentId', [FetchGames.positive_id(agent_id), nil])
      unless result.is_a?(Array) && result.all? { |battle| battle.is_a?(Hash) && battle['gameId'] }
        raise Error, 'Unexpected battles response: expected an array of games'
      end
      result
    end

    def game(game_id)
      game_id = FetchGames.positive_id(game_id)
      result = call('gameResult/findByGameId', [game_id, nil])
      unless result.is_a?(Hash) && result['gameId'] == game_id && result['frames'].is_a?(Array)
        raise Error, 'Unexpected replay response: missing frames or mismatched game ID'
      end
      result
    end

    private

    def throttle
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      if @last_request
        remaining = @interval - (now - @last_request)
        @sleeper.call(remaining) if remaining > 0
      end
      @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 10
      http.read_timeout = 30
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'application/json'
      request['User-Agent'] = 'coders-of-the-caribbean-game-archive/1.0'
      request.body = body
      http.request(request)
    end
  end
end
