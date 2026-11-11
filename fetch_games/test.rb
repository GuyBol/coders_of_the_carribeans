require 'tmpdir'
require 'stringio'
require_relative 'fetch'

Response = Struct.new(:code, :body, :headers) do
  def [](key)
    (headers || {})[key]
  end
end

def assert(condition, message = 'Assertion failed')
  raise message unless condition
end

def assert_error(text)
  begin
    yield
  rescue FetchGames::Error => error
    assert(error.message.include?(text), error.message)
    return
  end
  raise "Expected an error containing #{text.inspect}"
end

def fixture_client(responses, requests = [], sleeps = [])
  FetchGames::Client.new(
    interval: 0, sleeper: ->(seconds) { sleeps << seconds },
    transport: lambda do |uri, body|
      requests << [uri.to_s, JSON.parse(body)]
      response = responses.shift
      raise 'Unexpected API request' unless response
      response
    end
  )
end

requests = []
client = fixture_client([
  Response.new('200', JSON.generate('users' => [], 'count' => 4986)),
  Response.new('200', JSON.generate([{'gameId' => 42, 'done' => true}])),
  Response.new('200', JSON.generate('gameId' => 42, 'frames' => []))
], requests)
assert(client.leaderboard['count'] == 4986)
assert(client.battles(17).first['gameId'] == 42)
assert(client.game(42)['frames'] == [])
assert(requests.map(&:last) == [[FetchGames::PUZZLE, nil, 'global', {}], [17, nil], [42, nil]])
assert(requests[1][0].end_with?('/gamesPlayersRanking/findLastBattlesByAgentId'))
puts 'PASS verified RPC paths and payloads'

sleeps = []
client = fixture_client([
  Response.new('429', 'not logged', 'Retry-After' => '9999'),
  Response.new('503', 'not logged'),
  Response.new('200', '[]')
], [], sleeps)
assert(client.battles(17) == [])
assert(sleeps == [30, 2])
puts 'PASS bounded rate-limit and server-error retries'

assert_error('HTTP 403') { fixture_client([Response.new('403', 'secret body')]).battles(17) }
assert_error('valid JSON') { fixture_client([Response.new('200', '<html>blocked</html>')]).battles(17) }
assert_error('Unexpected battles') { fixture_client([Response.new('200', '{}')]).battles(17) }
assert_error('Unexpected leaderboard') { fixture_client([Response.new('200', 'null')]).leaderboard }
assert_error('mismatched game ID') do
  fixture_client([Response.new('200', '{"gameId":43,"frames":[]}')]).game(42)
end
assert_error('positive integers') { FetchGames.positive_id('../42') }
assert_error('positive integers') { FetchGames.positive_id(0) }
puts 'PASS invalid IDs, access errors, and malformed API responses'

handle = '189ceb936f80d641d8245553f46fdac72742541'
profile = {'userId' => 1452472, 'pseudo' => 'Daporan', 'publicHandle' => handle}
rank = {'agentId' => 6797473, 'globalRank' => 1500, 'codingamer' => profile}
board = {'users' => [], 'count' => 4986, 'codingamerUserRank' => rank}
response = ->(value) { Response.new('200', JSON.generate(value)) }
requests = []
client = fixture_client([
  response.call([{'type' => 'USER', 'name' => 'DaporanFan', 'id' => 'b' * 39},
                 {'type' => 'USER', 'name' => 'Daporan', 'id' => handle}]),
  response.call('codingamer' => profile), response.call(board)
], requests)
player = client.player(nickname: 'daporan')
assert(player['agent_id'] == 6797473 && player['rank'] == 1500)
assert(requests[0][1] == ['daporan', 'en', nil])
assert(requests[1][0].end_with?('/CodinGamer/findCodingamePointsStatsByHandle'))
assert(requests[2][1] == [FetchGames::PUZZLE, handle, 'global', {}])
client = fixture_client([response.call(profile), response.call('codingamer' => profile), response.call(board)], requests)
assert(client.player(user_id: 1452472)['user_id'] == 1452472)
assert(requests[3][0].end_with?('/CodinGamer/findCodinGamerPublicInformations'))
assert(requests[3][1] == [1452472])
client = fixture_client([response.call('codingamer' => profile), response.call('users' => [])])
assert(client.player(handle: handle)['agent_id'].nil?)
assert_error('No exact player match') do
  fixture_client([response.call([{'type' => 'USER', 'name' => 'DaporanFan'}])]).player(nickname: 'Daporan')
end
assert_error('Ambiguous nickname') do
  fixture_client([response.call(Array.new(2) { {'type' => 'USER', 'name' => 'Daporan'} })]).player(nickname: 'Daporan')
end
assert_error('exactly one') { fixture_client([]).player(nickname: 'name', user_id: 1) }
assert_error('public profile handle') { fixture_client([]).player(handle: '../../outside') }
puts 'PASS exact player lookup, profile RPCs, and personalized ranking outside the top list'

replay = {
  'gameId' => 42, 'frames' => [{'view' => 'raw keyframe', 'stdout' => 'WAIT', 'stderr' => 'debug output'}],
  'refereeInput' => "seed=123\nshipsPerPlayer=3\n", 'scores' => [7, 12], 'ranks' => [1, 0],
  'agents' => [
    {'index' => 1, 'agentId' => 200, 'codingamer' => {'userId' => 20, 'pseudo' => 'Second'}},
    {'index' => 0, 'agentId' => 100, 'codingamer' => {'userId' => 10, 'pseudo' => 'First'}}
  ]
}
battle = {'gameId' => 42, 'done' => true, 'players' => [
  {'playerAgentId' => 100, 'userId' => 10, 'nickname' => 'First', 'publicHandle' => 'a' * 39},
  {'playerAgentId' => 200, 'userId' => 20, 'nickname' => 'Second', 'publicHandle' => 'b' * 39}
]}
Dir.mktmpdir('fetch-games-test-') do |directory|
  requests = []
  updated = replay.merge('frames' => replay['frames'] + [{'view' => 'second frame'}])
  client = fixture_client([response.call(replay), Response.new('404', '{}'), response.call(updated)], requests)
  archive = FetchGames::Archive.new(directory, client)
  assert(archive.save(42, battle: battle, requested_by: player) == :saved)
  location = File.join(directory, FetchGames::PUZZLE, 'games', '42')
  raw = File.join(location, 'replay.json')
  info = File.join(location, 'metadata.json')
  assert(JSON.parse(File.read(raw)) == replay, 'Replay must be preserved without dropping frames or fields')
  metadata = JSON.parse(File.read(info))
  assert(metadata['battle'] == battle && metadata['requested_by'] == player)
  assert(metadata['referee_input'] == replay['refereeInput'])
  assert(metadata['players'].first == {
    'index' => 1, 'agent_id' => 200, 'user_id' => 20, 'nickname' => 'Second',
    'public_handle' => 'b' * 39, 'rank' => 0, 'score' => 12
  }, 'Players must be joined by agent ID, with results indexed by replay agent index')
  assert(archive.save(42) == :skipped && requests.length == 1)
  assert_error('HTTP 404') { archive.save(42, refresh: true) }
  assert(JSON.parse(File.read(raw)) == replay, 'Failed refresh must not replace a good capture')
  File.write(info, 'broken')
  assert_error('--refresh') { archive.save(42) }
  assert(requests.length == 2, 'Corrupt local captures must not silently trigger downloads')
  assert(archive.save(42, refresh: true) == :saved)
  assert(JSON.parse(File.read(raw)) == updated)
  assert(Dir.children(File.dirname(location)) == ['42'], 'Temporary capture directories must be cleaned up')
end
puts 'PASS lossless archive, player identity mapping, resume, corruption detection, and safe refresh'

Dir.mktmpdir('fetch-games-cli-test-') do |directory|
  requests = []
  second_battle = battle.merge('gameId' => 43)
  client = fixture_client([
    response.call('users' => [rank, rank.merge('agentId' => 200)]),
    response.call([battle, battle, second_battle, battle.merge('gameId' => 44, 'done' => false)]),
    response.call(replay), Response.new('404', '{}'),
    response.call([battle])
  ], requests)
  out = StringIO.new
  err = StringIO.new
  result = FetchGames::CLI.run(['fetch', '--top', '2', '--output', directory], out: out, err: err, client: client)
  summary = JSON.parse(out.string)
  assert(result == 1 && summary.values_at('saved', 'skipped', 'failed') == [1, 0, 1])
  assert(requests.length == 5, 'Duplicate and unfinished games must not be downloaded')
  assert(summary['errors'].first.include?('Game 43') && err.string.include?('HTTP 404'))
  out = StringIO.new
  result = FetchGames::CLI.run(['fetch', '--game-id', '42', '--output', directory],
                              out: out, err: StringIO.new, client: fixture_client([]))
  assert(result.zero? && JSON.parse(out.string)['skipped'] == 1)
end
puts 'PASS tournament-player selection, game de-duplication, partial failures, and CLI resume'

[
  ['fetch', '--agent-id', '1'],
  ['fetch', '--agent-id', '../1', '--output', '/unused'],
  ['fetch', '--player', 'name', '--agent-id', '1', '--output', '/unused'],
  ['lookup', '--agent-id', '1'],
  ['leaderboard', '--player', 'name'],
  ['leaderboard', '--interval', '-1'],
  ['leaderboard', 'unexpected'],
  ['unknown']
].each do |arguments|
  assert(FetchGames::CLI.run(arguments, out: StringIO.new, err: StringIO.new, client: fixture_client([])) == 1)
end
out = StringIO.new
assert(FetchGames::CLI.run(['--help'], out: out, err: StringIO.new, client: fixture_client([])).zero?)
assert(out.string.include?('--output PATH'))
puts 'PASS CLI argument validation and help without network requests'

