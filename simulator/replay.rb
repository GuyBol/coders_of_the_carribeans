require 'json'
require 'open3'
require 'timeout'

module Simulator
  class Error < StandardError; end

  def self.ranks(scores)
    order = scores.each_index.sort_by { |index| [-scores[index], index] }
    scores.each_index.map { |index| order.index(index) }
  end

  def self.build(source, output)
    compiler = ENV.fetch('CXX', 'clang++')
    _stdout, stderr, status = Open3.capture3(compiler, '-std=c++17', '-O2', '-Wall', '-Wextra', '-pedantic', source, '-o', output)
    raise Error, "Compilation failed: #{stderr}" unless status.success?
  end

  class Engine
    attr_reader :state

    def initialize(binary, initial)
      @input, @output, @error, @process = Open3.popen3(binary)
      reset(initial)
    end

    def reset(initial)
      @input.puts "RESET #{initial.fetch(:turn)} #{initial.fetch(:next_id)}"
      [:ships, :barrels, :mines, :balls].each do |kind|
        @input.puts initial.fetch(kind).length
        initial.fetch(kind).each { |entity| @input.puts entity.join(' ') }
      end
      @input.flush
      receive
    end

    def step(actions, disqualified = 0)
      @input.puts "STEP #{actions.length} #{disqualified}"
      actions.each { |id, action| @input.puts "#{id} #{action}" }
      @input.flush
      receive
    end

    def close
      @input.close unless @input.closed?
      @output.close unless @output.closed?
      @error.close unless @error.closed?
      @process.value
    end

    private

    def line
      text = @output.gets
      raise Error, "Simulator exited before returning its state: #{@error.read.strip}" unless text
      text.split.map { |value| Integer(value, 10) }
    end

    def receive
      Timeout.timeout(10) do
        turn, next_id = line
        @state = {turn: turn, next_id: next_id}
        [:ships, :barrels, :mines, :balls].each do |kind|
          @state[kind] = Array.new(line.fetch(0)) { line }
        end
      end
      @state
    rescue Timeout::Error
      raise Error, 'Simulator state response timed out'
    end
  end

  class Replay
    attr_reader :data, :initial, :transitions

    def initialize(path)
      @data = JSON.parse(File.read(path))
      unless @data.is_a?(Hash) && @data['frames'].is_a?(Array) && @data['frames'].all? { |frame| frame.is_a?(Hash) }
        raise Error, "#{path}: missing or invalid replay frames"
      end
      @transitions = []
      actions = {}
      disqualified = 0
      previous = nil
      @data['frames'].each do |frame|
        owner = frame['agentId']
        if owner.is_a?(Integer) && owner >= 0
          raise Error, 'Only two-player replays are supported' unless owner < 2
          actions[owner] = frame.fetch('stdout', '').lines.map(&:strip)
          if frame.fetch('gameInformation', '').match(/timeout|no longer be active|invalid/i)
            disqualified |= 1 << owner
          end
        end
        next unless frame['keyframe'] && frame['view'].to_s.lines.length > 2
        current = decode(frame['view'], previous.nil?)
        if previous
          commands = previous[:ships].select { |ship| ship[6] > 0 }.map do |ship|
            owner_actions = actions.fetch(ship[1]) { raise Error, "Missing actions for player #{ship[1]}" }
            command = owner_actions.shift
            unless command || (disqualified & (1 << ship[1])) != 0
              raise Error, "Missing ship #{ship[0]} command at turn #{previous[:turn]}"
            end
            [ship[0], (disqualified & (1 << ship[1])) != 0 ? 'WAIT' : command]
          end
          resolved = commands.map do |id, command|
            [id, command.split.first.to_s.upcase == 'MOVE' ? current.fetch(:effective_actions).fetch(id) : command]
          end
          @transitions << {state: current, actions: commands, resolved_actions: resolved, disqualified: disqualified}
          actions = {}
          disqualified = 0
        else
          @initial = current
        end
        previous = current
      end
      raise Error, 'Replay contains no playable initial state' unless @initial
    rescue JSON::ParserError, ArgumentError, IndexError, TypeError, KeyError => error
      raise Error, "Invalid replay #{path}: #{error.message}"
    end

    def move_cases
      previous = initial
      cases = []
      transitions.each do |transition|
        transition[:actions].each do |id, command|
          fields = command.split
          next unless fields.first.to_s.upcase == 'MOVE'
          ship = previous[:ships].find { |entry| entry.first == id }
          cases << {game_id: data['gameId'], turn: previous[:turn], ship_id: id,
                    input: ship[2, 4] + fields[1, 2].map { |value| Integer(value, 10) },
                    expected: transition[:state][:effective_actions].fetch(id)}
        end
        previous = transition[:state]
      end
      cases
    end

    def validate(binary, resolved_moves: false)
      engine = Engine.new(binary, initial)
      checked = 0
      @transitions.each do |transition|
        actual = engine.step(resolved_moves ? transition[:resolved_actions] : transition[:actions], transition[:disqualified])
        expected = transition[:state]
        [:ships, :barrels, :mines, :balls].each do |kind|
          actual_entities = actual[kind].map { |entity| kind == :ships ? entity.first(7) : entity }.sort
          expected_entities = expected[kind].map { |entity| kind == :ships ? entity.first(7) : entity }.sort
          next if actual_entities == expected_entities
          return {game_id: data['gameId'], passed: false, checked_turns: checked,
                  mismatch_turn: expected[:turn], entity: kind,
                  missing: expected_entities - actual_entities, unexpected: actual_entities - expected_entities,
                  actions: transition[:actions]}
        end
        checked += 1
      end
      totals = [0, 0]
      engine.state[:ships].each { |ship| totals[ship[1]] += [ship[6], 0].max }
      expected_scores = data['scores']
      unless expected_scores.is_a?(Array) && expected_scores == totals
        return {game_id: data['gameId'], passed: false, checked_turns: checked,
                entity: 'final_scores', expected: expected_scores, actual: totals}
      end
      expected_ranks = Simulator.ranks(totals)
      unless data['ranks'] == expected_ranks
        return {game_id: data['gameId'], passed: false, checked_turns: checked,
                entity: 'final_ranks', expected: data['ranks'], actual: expected_ranks}
      end
      {game_id: data['gameId'], passed: true, checked_turns: checked, scores: totals}
    ensure
      engine.close if engine
    end

    private

    def decode(view, first)
      lines = view.lines.map(&:strip)
      take = -> { lines.shift || (raise Error, 'Truncated replay view') }
      numbers = lambda do |count|
        values = take.call.split.map { |value| Integer(value, 10) }
        raise Error, "Expected #{count} replay fields" unless values.length == count
        values
      end
      frame_number = Integer(take.call.split.first, 10)
      if first
        raise Error, 'Unexpected game name in replay' unless take.call == 'CodersOfTheCaribbean'
        raise Error, 'Expected two players' unless take.call == '2'
        config = numbers.call(5)
        raise Error, 'Expected a 23 by 21 map' unless config.first(2) == [23, 21]
      end
      state = {turn: frame_number / 2, ships: [], barrels: [], mines: [], balls: [], effective_actions: {}}
      2.times do |owner|
        raise Error, "Missing player section #{owner}" unless take.call == owner.to_s
        while lines.first && lines.first.split.length > 1
          fields = take.call.split
          raise Error, 'Truncated replay ship' unless fields.length >= 7
          id, row, column, direction, rum, speed = fields.first(6).map { |value| Integer(value, 10) }
          state[:ships] << [id, owner, column, row, direction, speed, rum, 0, 0]
          state[:effective_actions][id] = fields.fetch(6)
        end
      end
      numbers.call(1).first.times do
        id, row, column, origin_row, origin_column, initial, remaining, owner = numbers.call(8)
        state[:balls] << [id, column, row, owner, remaining, origin_column, origin_row, initial]
      end
      numbers.call(1).first.times do
        id, row, column = numbers.call(3)
        state[:mines] << [id, column, row]
      end
      numbers.call(1).first.times do
        id, row, column, rum = numbers.call(4)
        state[:barrels] << [id, column, row, rum]
      end
      state[:next_id] = ([:ships, :barrels, :mines, :balls].flat_map { |kind| state[kind].map(&:first) }.max || -1) + 1
      state
    end
  end
end