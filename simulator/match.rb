require 'fileutils'
require_relative 'replay'

module Simulator
  def self.neighbor(cell, direction)
    column, row = cell
    offsets = [[1, 0], [row & 1, -1], [(row & 1) - 1, -1], [-1, 0], [(row & 1) - 1, 1], [row & 1, 1]]
    [column + offsets[direction][0], row + offsets[direction][1]]
  end

  def self.distance(first, second)
    delta = first[0] - (first[1] - (first[1] & 1)) / 2 - second[0] + (second[1] - (second[1] & 1)) / 2
    rows = first[1] - second[1]
    (delta.abs + rows.abs + (delta + rows).abs) / 2
  end

  def self.generate(seed, fleet_size = 3)
    raise Error, 'Fleet size must be between 1 and 3' unless (1..3).cover?(fleet_size)
    random = Random.new(seed)
    state = {turn: 0, ships: [], barrels: [], mines: [], balls: []}
    occupied = []
    2.times do |owner|
      fleet_size.times do |index|
        column = fleet_size == 1 ? 11 : 4 + 14 * index / (fleet_size - 1)
        row = owner.zero? ? 3 : 17
        direction = owner.zero? ? 5 : 1
        state[:ships] << [2 * index + owner, owner, column, row, direction, 0, 100, 0, 0]
        occupied.concat([[column, row], neighbor([column, row], direction), neighbor([column, row], (direction + 3) % 6)])
      end
    end
    next_id = fleet_size * 2
    [:mines, :barrels].each do |kind|
      (kind == :mines ? 3 : 6).times do
        positions = nil
        1000.times do
          column = random.rand(1..21)
          row = random.rand(1..9)
          candidate = [[column, row], [column, 20 - row]]
          unless candidate.any? { |cell| occupied.include?(cell) }
            positions = candidate
            break
          end
        end
        raise Error, 'Could not generate an unoccupied symmetric map' unless positions
        rum = random.rand(10..20) if kind == :barrels
        positions.each do |position|
          state[kind] << [next_id, *position, *([rum] if kind == :barrels)]
          occupied << position
          next_id += 1
        end
      end
    end
    state[:next_id] = next_id
    state
  end

  def self.bot_input(state, owner)
    live = state[:ships].select { |ship| ship[6] > 0 }
    friendly = live.select { |ship| ship[1] == owner }.sort_by(&:first)
    enemies = live.reject { |ship| ship[1] == owner }.sort_by(&:first)
    entities = (friendly + enemies).map do |id, player, column, row, direction, speed, rum, _fire, _mine|
      "#{id} SHIP #{column} #{row} #{direction} #{speed} #{rum} #{player == owner ? 1 : 0}"
    end
    entities.concat(state[:barrels].map { |id, column, row, rum| "#{id} BARREL #{column} #{row} #{rum} 0 0 0" })
    state[:mines].each do |id, column, row|
      if friendly.any? { |ship| distance(ship[2, 2], [column, row]) < 5 }
        entities << "#{id} MINE #{column} #{row} 0 0 0 0"
      end
    end
    state[:balls].each do |id, column, row, shooter, remaining, *_rest|
      entities << "#{id} CANNONBALL #{column} #{row} #{shooter} #{remaining} 0 0" if remaining > 0
    end
    [friendly.map(&:first), "#{friendly.length}\n#{entities.length}\n#{entities.join("\n")}\n"]
  end

  class Bot
    attr_reader :diagnostics

    def initialize(command)
      @input, @output, @error, @process = Open3.popen3(*command, pgroup: true)
      @buffer = ''.dup
      @diagnostics = ''.dup
      @drain = Thread.new do
        begin
          loop do
            @diagnostics << @error.readpartial(4096)
            @diagnostics = @diagnostics[-16384, 16384] if @diagnostics.bytesize > 16384
          end
        rescue EOFError, IOError
          nil
        end
      end
    end

    def play(input, count, seconds)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      commands = []
      Timeout.timeout(seconds) do
        @input.write(input)
        @input.flush
        while commands.length < count
          if (ending = @buffer.index("\n"))
            commands << @buffer.slice!(0, ending + 1).strip
          else
            @buffer << @output.readpartial(4096)
            raise Error, 'Bot output exceeds 64 KiB' if @buffer.bytesize > 65536
          end
        end
      end
      raise Error, 'Bot provided extra output lines' unless @buffer.strip.empty?
      commands.each do |command|
        unless command.match(/\A(?:(?:WAIT|FASTER|SLOWER|PORT|STARBOARD|MINE)(?:\s.*)?|(?:MOVE|FIRE)\s+-?\d+\s+-?\d+(?:\s.*)?)\z/i)
          raise Error, "Invalid bot action: #{command.inspect}"
        end
      end
      [commands, (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000]
    rescue Timeout::Error
      raise Error, "Bot timed out after #{seconds * 1000} ms"
    rescue EOFError, Errno::EPIPE, IOError
      raise Error, 'Bot exited before producing all actions'
    end

    def close
      @input.close unless @input.closed?
      unless @process.join(0.1)
        begin
          Process.kill('TERM', -@process.pid)
          Process.kill('KILL', -@process.pid) unless @process.join(0.5)
        rescue Errno::ESRCH
          nil
        end
      end
      @process.value
      @output.close unless @output.closed?
      @error.close unless @error.closed?
      @drain.join
    end
  end

  def self.match(binary, initial, commands, turn_ms: 50, first_turn_ms: 1000)
    bots = []
    engine = Engine.new(binary, initial)
    commands.each { |command| bots << Bot.new(command) }
    log = {schema_version: 1, initial: initial, turns: [], forfeits: []}
    loop do
      state = engine.state
      totals = [0, 0]
      state[:ships].each { |ship| totals[ship[1]] += [ship[6], 0].max }
      break if state[:turn] >= 200 || totals.include?(0)
      actions = []
      disqualified = 0
      timings = []
      bots.each_with_index do |bot, owner|
        ids, input = bot_input(state, owner)
        begin
          lines, elapsed = bot.play(input, ids.length, (state[:turn].zero? ? first_turn_ms : turn_ms) / 1000.0)
          actions.concat(ids.zip(lines))
          timings << elapsed
        rescue Error => error
          disqualified |= 1 << owner
          log[:forfeits] << {player: owner, turn: state[:turn], error: error.message}
          actions.concat(ids.map { |id| [id, 'WAIT'] })
          timings << nil
        end
      end
      after = engine.step(actions, disqualified)
      log[:turns] << {turn: after[:turn], actions: actions, elapsed_ms: timings, state: after}
      break unless disqualified.zero?
    end
    scores = [0, 0]
    engine.state[:ships].each { |ship| scores[ship[1]] += [ship[6], 0].max }
    log[:forfeits].each { |forfeit| scores[forfeit[:player]] = 0 }
    log[:scores] = scores
    log[:ranks] = Simulator.ranks(scores)
    log[:winner] = scores[0] == scores[1] ? nil : scores.index(scores.max)
    log[:reason] = if !log[:forfeits].empty?
                     'forfeit'
                   elsif engine.state[:turn] >= 200
                     'turn_limit'
                   else
                     'fleet_eliminated'
                   end
    log[:bot_stderr] = bots.map { |bot| bot.diagnostics.encode('UTF-8', invalid: :replace, undef: :replace) }
    log
  ensure
    bots.each(&:close)
    engine.close if engine
  end
end