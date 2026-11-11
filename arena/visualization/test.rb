require 'tmpdir'
require 'fileutils'
require_relative 'server'

def assert(condition)
  raise 'Assertion failed' unless condition
end

def rejects(status)
  yield
  raise 'Expected rejection'
rescue ArenaViewer::Error => error
  assert(error.status == status)
end

Dir.mktmpdir('arena-viewer-tests-') do |root|
  run = File.join(root, 'run')
  FileUtils.mkdir_p(run)
  File.write(File.join(run, 'replay.json'), JSON.generate('frames' => []))
  File.write(File.join(run, 'metadata.json'), JSON.generate('origin' => 'local'))
  report = {'schema_version' => 1, 'game' => 'example', 'rankings' => [],
            'matches' => [{'id' => 1, 'view' => {'interface_version' => 1, 'game' => 'example',
                          'replay' => 'replay.json', 'metadata' => 'metadata.json'}},
                          {'id' => 2, 'error' => 'engine failure'}]}
  path = File.join(run, 'tournament.json')
  File.write(path, JSON.generate(report))
  store = ArenaViewer::Store.new([root])
  id = store.runs.first[:id]
  assert(store.tournament(id)['matches'].length == 2)
  assert(store.game(id, 1)[:replay]['frames'] == [])
  assert(store.game(id, 1)[:details] == {})
  rejects(404) { store.tournament('missing') }
  rejects(409) { store.game(id, 2) }
  rejects(404) { store.game(id, 999) }
  File.write(File.join(root, 'secret.json'), '{}')
  report['matches'][0]['view']['metadata'] = '../secret.json'
  File.write(path, JSON.generate(report))
  rejects(403) { store.game(id, 1) }
  File.symlink(File.join(root, 'secret.json'), File.join(run, 'linked.json'))
  report['matches'][0]['view']['metadata'] = 'linked.json'
  File.write(path, JSON.generate(report))
  rejects(403) { store.game(id, 1) }
end
puts 'PASS viewer discovery, generic replay API, optional details, missing games, engine errors, traversal and symlink protection'
