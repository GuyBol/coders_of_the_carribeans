require_relative 'run'

module Simulator
  def self.analyze_moves(arguments)
    options = {subset: 'training', manifest: File.join(__dir__, 'corpus.json')}
    parser = OptionParser.new do |flags|
      flags.banner = 'Usage: ruby simulator/analyze.rb --archive PATH [options]'
      flags.on('--archive PATH', 'Capture repository or one replay JSON') { |value| options[:archive] = value }
      flags.on('--subset NAME', %w[training holdout all], 'Default: training') { |value| options[:subset] = value }
      flags.on('--manifest PATH', 'Persistent game-level split manifest') { |value| options[:manifest] = value }
      flags.on('--report PATH', 'Write complete MOVE discrepancies') { |value| options[:report] = value }
      flags.on('-h', '--help') { options[:help] = true }
    end
    parser.parse!(arguments)
    if options[:help]
      puts parser
      return 0
    end
    raise Error, 'Specify --archive PATH with no positional arguments' unless options[:archive] && arguments.empty?
    archive = File.expand_path(options[:archive])
    paths = File.file?(archive) ? [archive] : Dir.glob(File.join(archive, '**', 'replay.json')).sort
    raise Error, 'No replay files found' if paths.empty?
    manifest = if File.exist?(options[:manifest])
                 JSON.parse(File.read(options[:manifest]))
               else
                 baseline = File.join(__dir__, 'validation.json')
                 previous = File.exist?(baseline) ? JSON.parse(File.read(baseline)).fetch('results', []).map { |entry| entry['game_id'] }.compact.uniq : []
                 {'schema_version' => 1, 'policy' => 'Original development games train; new games use SHA256(game_id) modulo 5 == 0 for holdout',
                  'development_games' => previous, 'games' => {}}
               end
    cases = []
    errors = []
    game_counts = Hash.new(0)
    paths.each do |path|
      begin
        replay = Replay.new(path)
        id = replay.data.fetch('gameId').to_s
        digest = Digest::SHA256.file(path).hexdigest
        entry = manifest['games'][id]
        raise Error, "Capture #{id} changed after its split was assigned" if entry && entry['sha256'] != digest
        unless entry
          holdout = !manifest['development_games'].include?(id.to_i) && Digest::SHA256.hexdigest(id).to_i(16) % 5 == 0
          entry = {'subset' => holdout ? 'holdout' : 'training', 'sha256' => digest}
          manifest['games'][id] = entry
        end
        game_counts[entry['subset']] += 1
        next unless options[:subset] == 'all' || options[:subset] == entry['subset']
        cases.concat(replay.move_cases.map { |sample| sample.merge(subset: entry['subset']) })
      rescue Error, SystemCallError => error
        errors << {capture: path, error: error.message}
      end
    end
    write_json(options[:manifest], manifest)
    outputs = nil
    Dir.mktmpdir('caribbean-move-probe-') do |directory|
      binary = File.join(directory, 'probe')
      build(File.join(__dir__, 'test.cpp'), binary)
      stdout, stderr, status = Open3.capture3(binary, '--move-cases', stdin_data: cases.map { |sample| sample[:input].join(' ') + "\n" }.join)
      raise Error, "MOVE probe failed: #{stderr}" unless status.success?
      outputs = stdout.lines.map(&:strip)
      raise Error, 'MOVE probe returned an incorrect number of commands' unless outputs.length == cases.length
    end
    mismatches = cases.zip(outputs).map do |sample, actual|
      sample.merge(actual: actual) unless sample[:expected] == actual
    end.compact
    conflicting = cases.group_by { |sample| sample[:input] }.select do |_input, samples|
      samples.map { |sample| sample[:expected] }.uniq.length > 1
    end
    report = {
      generated_at: Time.now.utc.iso8601, archive: archive, subset: options[:subset], games: game_counts,
      cases: cases.length, matched: cases.length - mismatches.length, mismatches: mismatches,
      conflicting_inputs: conflicting.map { |input, samples| {input: input, samples: samples} }, errors: errors,
      engine_sha256: Digest::SHA256.file(File.join(__dir__, 'engine.hpp')).hexdigest
    }
    write_json(options[:report], report) if options[:report]
    puts JSON.pretty_generate(report.reject { |key, _value| [:mismatches, :conflicting_inputs].include?(key) }.merge(
      mismatch_count: mismatches.length, conflicting_input_count: conflicting.length))
    mismatches.empty? && errors.empty? ? 0 : 1
  rescue Error, OptionParser::ParseError, SystemCallError, JSON::ParserError => error
    warn "Error: #{error.message}"
    1
  end
end

exit Simulator.analyze_moves(ARGV.dup) if $PROGRAM_NAME == __FILE__
