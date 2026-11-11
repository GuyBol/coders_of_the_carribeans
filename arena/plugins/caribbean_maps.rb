require 'digest'
require 'fileutils'
require 'optparse'
require_relative '../../simulator/replay'

module CaribbeanMaps
  DEFAULT_PATH = File.expand_path('../maps/caribbean.json', __dir__)
  STATE_FIELDS = [:turn, :next_id, :ships, :barrels, :mines, :balls].freeze

  def self.state_id(initial)
    Digest::SHA256.hexdigest(JSON.generate(STATE_FIELDS.each_with_object({}) { |key, state| state[key] = initial.fetch(key) }))
  end

  def self.build(archive, output)
    root = File.expand_path(archive)
    paths = File.file?(root) ? [root] : Dir.glob(File.join(root, '**', 'replay.json')).sort
    raise Simulator::Error, 'No captured replay.json files found' if paths.empty?
    maps = {}
    games = {}
    paths.each do |path|
      replay = Simulator::Replay.new(path)
      raise Simulator::Error, "Local replay cannot supply a CodinGame map: #{path}" if replay.data['origin'] == 'local'
      game_id = replay.data['gameId']
      raise Simulator::Error, "Invalid source game ID: #{path}" unless game_id.is_a?(Integer) && game_id > 0
      capture_hash = Digest::SHA256.file(path).hexdigest
      if games.key?(game_id)
        raise Simulator::Error, "Conflicting captures for game #{game_id}" unless games[game_id] == capture_hash
        next
      end
      games[game_id] = capture_hash
      initial = STATE_FIELDS.each_with_object({}) { |key, state| state[key] = replay.initial.fetch(key) }
      id = state_id(initial)
      frame = replay.data['frames'].find { |entry| entry['keyframe'] && entry['view'].to_s.lines.length > 2 }
      header = frame.fetch('view').lines.fetch(3).split.map { |value| Integer(value, 10) }
      maps[id] ||= {id: id, ships: initial[:ships].count { |ship| ship[1].zero? },
                    header: header, initial: initial, sources: []}
      maps[id][:sources] << {game_id: game_id, capture_sha256: capture_hash, map_seed: header.last}
    end
    catalog = {schema_version: 1, game: 'coders-of-the-caribbean', origin: 'codingame',
               captured_games: games.length, maps: maps.values.sort_by { |map| map[:id] }}
    Catalog.validate(catalog)
    FileUtils.mkdir_p(File.dirname(File.expand_path(output)))
    temporary = output + '.tmp'
    File.write(temporary, JSON.generate(catalog) + "\n")
    File.rename(temporary, output)
    {captured_games: games.length, unique_maps: maps.length,
     ships: (1..3).each_with_object({}) { |ships, counts| counts[ships] = maps.values.count { |map| map[:ships] == ships } },
     output: File.expand_path(output)}
  end

  class Catalog
    attr_reader :maps, :sha256

    def self.validate(catalog)
      unless catalog.is_a?(Hash) && catalog[:schema_version] == 1 && catalog[:origin] == 'codingame' &&
             catalog[:game] == 'coders-of-the-caribbean' && catalog[:maps].is_a?(Array) && !catalog[:maps].empty?
        raise Simulator::Error, 'Invalid or empty captured-map catalog'
      end
      catalog[:maps].each do |map|
        initial = map.fetch(:initial)
        arrays = {ships: 9, barrels: 4, mines: 3, balls: 8}
        valid_entities = arrays.all? do |kind, size|
          initial[kind].is_a?(Array) && initial[kind].all? do |entity|
            entity.is_a?(Array) && entity.length == size && entity.all? { |value| value.is_a?(Integer) }
          end
        end
        raise Simulator::Error, 'Invalid captured-map entities' unless valid_entities
        counts = [0, 1].map { |owner| initial[:ships].count { |ship| ship[1] == owner } }
        ids = arrays.keys.flat_map { |kind| initial[kind].map(&:first) }
        unless (1..3).cover?(map[:ships]) && counts == [map[:ships], map[:ships]] &&
               initial[:turn] == 0 && initial[:balls].empty? && ids.uniq.length == ids.length &&
               initial[:next_id] == ids.max + 1 && map[:id] == CaribbeanMaps.state_id(initial) &&
               initial[:ships].all? { |ship| [0, 1].include?(ship[1]) && (0..5).cover?(ship[4]) && ship[5, 4] == [0, 100, 0, 0] } &&
               map[:header].is_a?(Array) && map[:header].length == 5 && map[:header].all? { |value| value.is_a?(Integer) } &&
               map[:header].first(3) == [23, 21, map[:ships]] &&
               map[:sources].is_a?(Array) && !map[:sources].empty? &&
               map[:sources].all? { |source| source[:game_id].is_a?(Integer) && source[:game_id] > 0 && /\A[0-9a-f]{64}\z/.match(source[:capture_sha256].to_s) }
          raise Simulator::Error, 'Invalid captured-map state or provenance'
        end
      end
      unless catalog[:maps].map { |map| map[:id] }.uniq.length == catalog[:maps].length &&
             catalog[:captured_games] == catalog[:maps].sum { |map| map[:sources].length }
        raise Simulator::Error, 'Duplicate maps or incorrect source-game count'
      end
      true
    rescue KeyError, TypeError, NoMethodError => error
      raise Simulator::Error, "Malformed captured-map catalog: #{error.message}"
    end

    def initialize(path = DEFAULT_PATH)
      content = File.read(path)
      catalog = JSON.parse(content, symbolize_names: true)
      self.class.validate(catalog)
      @maps = catalog[:maps]
      @sha256 = Digest::SHA256.hexdigest(content)
      @by_ships = (1..3).each_with_object({}) { |ships, entries| entries[ships] = @maps.select { |map| map[:ships] == ships } }
    rescue JSON::ParserError, SystemCallError => error
      raise Simulator::Error, "Cannot load captured-map catalog #{path}: #{error.message}"
    end

    def select(seed:, ships: nil)
      random = Random.new(seed)
      ships ||= random.rand(1..3)
      candidates = @by_ships.fetch(ships)
      raise Simulator::Error, "No captured maps with #{ships} ships per player" if candidates.empty?
      candidates.fetch(random.rand(candidates.length))
    end

    def initial_state(map)
      map.fetch(:initial).each_with_object({}) do |(key, value), state|
        state[key] = value.is_a?(Array) ? value.map(&:dup) : value
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {output: CaribbeanMaps::DEFAULT_PATH}
    parser = OptionParser.new do |flags|
      flags.banner = 'Usage: ruby arena/plugins/caribbean_maps.rb --archive PATH [--output FILE]'
      flags.on('--archive PATH', 'Public CodinGame replay archive') { |value| options[:archive] = value }
      flags.on('--output FILE', 'Map catalog output (default: arena/maps/caribbean.json)') { |value| options[:output] = value }
      flags.on('-h', '--help') { puts flags; exit 0 }
    end
    parser.parse!
    raise Simulator::Error, 'Specify --archive PATH with no extra arguments' unless options[:archive] && ARGV.empty?
    puts JSON.pretty_generate(CaribbeanMaps.build(options[:archive], options[:output]))
  rescue Simulator::Error, OptionParser::ParseError, SystemCallError, ArgumentError => error
    warn "Error: #{error.message}"
    exit 1
  end
end
