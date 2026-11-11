require 'json'
require 'digest'
require 'optparse'
require 'webrick'

module ArenaViewer
  class Error < StandardError
    attr_reader :status
    def initialize(message, status = 400)
      super(message)
      @status = status
    end
  end

  class Store
    def initialize(roots)
      @roots = roots.map { |path| File.expand_path(path) }.select { |path| File.directory?(path) }.map { |path| File.realpath(path) }.uniq
    end

    def paths
      @roots.flat_map do |root|
        Dir.glob(File.join(root, '**', 'tournament.json')).select do |path|
          File.realpath(path).start_with?(root + File::SEPARATOR)
        rescue SystemCallError
          false
        end
      end.uniq
    end

    def id(path)
      Digest::SHA256.hexdigest(File.realpath(path))
    end

    def runs
      paths.map do |path|
        report = read_json(path)
        {id: id(path), name: File.basename(File.dirname(path)), game: report['game'],
         status: report['status'], started_at: report['started_at'],
         completed_games: report['completed_games'], planned_games: report['planned_games']}
      rescue Error
        {id: id(path), name: File.basename(File.dirname(path)), error: 'Invalid tournament report'}
      end.sort_by { |entry| entry[:started_at].to_s }.reverse
    end

    def tournament(run_id)
      path = find(run_id)
      report = read_json(path)
      unless report['schema_version'] == 1 && report['matches'].is_a?(Array) && report['rankings'].is_a?(Array)
        raise Error, 'Unsupported tournament report'
      end
      report.merge('viewer_id' => run_id, 'viewer_name' => File.basename(File.dirname(path)))
    end

    def game(run_id, match_id)
      path = find(run_id)
      report = tournament(run_id)
      match = report['matches'].find { |entry| entry['id'].to_s == match_id.to_s }
      raise Error.new('Game not found', 404) unless match
      raise Error.new(match['error'], 409) if match['error']
      view = match['view']
      raise Error, 'Unsupported replay interface' unless view.is_a?(Hash) && view['interface_version'] == 1
      base = File.dirname(path)
      {game: view['game'], match: match, replay: capture(base, view['replay']),
       metadata: capture(base, view['metadata']), details: view['details'] ? capture(base, view['details']) : {}}
    end

    private

    def find(run_id)
      paths.find { |path| id(path) == run_id } || (raise Error.new('Tournament not found', 404))
    end

    def capture(base, relative)
      raise Error, 'Invalid capture reference' unless relative.is_a?(String) && !relative.include?("\0")
      path = File.realpath(File.expand_path(relative, base))
      unless path.start_with?(File.realpath(base) + File::SEPARATOR) && File.extname(path) == '.json'
        raise Error.new('Capture is outside the tournament directory', 403)
      end
      read_json(path)
    rescue Errno::ENOENT
      raise Error.new('Capture file not found', 404)
    end

    def read_json(path)
      value = JSON.parse(File.read(path))
      raise Error, 'Expected a JSON object' unless value.is_a?(Hash)
      value
    rescue JSON::ParserError
      raise Error, 'Invalid JSON file'
    end
  end

  def self.serve(roots:, port:)
    store = Store.new(roots)
    asset_root = File.realpath(__dir__)
    server = nil
    21.times do |offset|
      begin
        server = WEBrick::HTTPServer.new(BindAddress: '127.0.0.1', Port: port + offset,
          AccessLog: [], Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN))
        break
      rescue Errno::EADDRINUSE
        next
      end
    end
    raise Error, 'No available viewer port' unless server
    server.mount_proc('/') do |request, response|
      response['Cache-Control'] = 'no-store'
      response['X-Content-Type-Options'] = 'nosniff'
      response['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"
      begin
        raise Error.new('Local requests only', 403) unless ['127.0.0.1', 'localhost', '::1'].include?(request.host)
        raise Error.new('Read-only server', 405) unless ['GET', 'HEAD'].include?(request.request_method)
        data = case request.path
               when '/api/runs' then store.runs
               when '/api/run' then store.tournament(request.query['id'])
               when '/api/game' then store.game(request.query['run'], request.query['match'])
               end
        if request.path.start_with?('/api/')
          raise Error.new('Endpoint not found', 404) if data.nil?
          response['Content-Type'] = 'application/json; charset=utf-8'
          response.body = JSON.generate(data)
        elsif request.path == '/favicon.ico'
          response.status = 204
          response.body = ''
        else
          relative = request.path == '/' ? 'index.html' : request.path.delete_prefix('/')
          path = File.realpath(File.join(asset_root, relative))
          types = {'.html' => 'text/html', '.css' => 'text/css', '.mjs' => 'text/javascript', '.js' => 'text/javascript'}
          unless path.start_with?(asset_root + File::SEPARATOR) && types.key?(File.extname(path)) && !File.basename(path).include?('test')
            raise Error.new('Asset not found', 404)
          end
          response['Content-Type'] = types.fetch(File.extname(path)) + '; charset=utf-8'
          response.body = File.binread(path)
        end
      rescue Error => error
        response.status = error.status
        response['Content-Type'] = 'application/json'
        response.body = JSON.generate(error: error.message)
      rescue SystemCallError
        response.status = 404
        response['Content-Type'] = 'application/json'
        response.body = JSON.generate(error: 'File not found')
      end
    end
    trap('INT') { server.shutdown }
    trap('TERM') { server.shutdown }
    puts "Arena viewer: http://127.0.0.1:#{server.config[:Port]}"
    server.start
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  begin
    options = {roots: [], port: 8765}
    parser = OptionParser.new do |flags|
      flags.banner = 'Usage: ruby arena/visualization/server.rb [--root DIR] [--port N]'
      flags.on('--root DIR', 'Tournament archive or run folder; repeat to add roots') { |value| options[:roots] << value }
      flags.on('--port N', Integer, 'Starting port (default: 8765); occupied ports are skipped') { |value| options[:port] = value }
      flags.on('-h', '--help') { puts flags; exit 0 }
    end
    parser.parse!
    raise ArenaViewer::Error, 'Port must be from 1024 to 65515, with no extra arguments' unless ARGV.empty? && (1024..65515).cover?(options[:port])
    options[:roots] = [File.expand_path('../runs', __dir__), File.expand_path('../../../local-arena-games', __dir__)] if options[:roots].empty?
    ArenaViewer.serve(roots: options[:roots], port: options[:port])
  rescue ArenaViewer::Error, OptionParser::ParseError, SystemCallError => error
    warn "Error: #{error.message}"
    exit 1
  end
end
