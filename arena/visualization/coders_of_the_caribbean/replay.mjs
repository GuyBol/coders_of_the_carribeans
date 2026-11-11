function decodeView(text, first) {
  const lines = text.trim().split(/\r?\n/).map(line => line.trim());
  let cursor = 0;
  const take = () => {
    if (cursor >= lines.length) throw new Error("Truncated replay frame");
    return lines[cursor++];
  };
  const numbers = count => {
    const values = take().split(/\s+/).map(Number);
    if (values.length !== count || !values.every(Number.isInteger)) throw new Error("Invalid replay entity");
    return values;
  };
  const frame = Number(take().split(/\s+/)[0]);
  if (!Number.isInteger(frame) || frame < 0) throw new Error("Invalid replay frame number");
  if (first) {
    if (take() !== "CodersOfTheCaribbean" || take() !== "2") throw new Error("Unsupported replay format");
    const header = numbers(5);
    if (header[0] !== 23 || header[1] !== 21) throw new Error("Unsupported map dimensions");
  }
  const state = {turn: frame / 2, ships: [], barrels: [], mines: [], balls: [], effective: {}};
  for (let owner = 0; owner < 2; owner += 1) {
    if (take() !== String(owner)) throw new Error("Missing player section");
    while (cursor < lines.length && lines[cursor].split(/\s+/).length > 1) {
      const fields = take().split(/\s+/);
      const values = fields.slice(0, 6).map(Number);
      if (fields.length < 7 || !values.every(Number.isInteger)) throw new Error("Invalid replay ship");
      const [id, row, column, direction, rum, speed] = values;
      state.ships.push([id, owner, column, row, direction, speed, rum]);
      state.effective[id] = fields[6];
    }
  }
  const entities = (kind, size, convert) => {
    const count = numbers(1)[0];
    if (count < 0 || count > 10000) throw new Error("Invalid replay entity count");
    for (let index = 0; index < count; index += 1) state[kind].push(convert(numbers(size)));
  };
  entities("balls", 8, ([id, row, column, originRow, originColumn, initial, remaining, owner]) =>
    [id, column, row, owner, remaining, originColumn, originRow, initial]);
  entities("mines", 3, ([id, row, column]) => [id, column, row]);
  entities("barrels", 4, ([id, row, column, rum]) => [id, column, row, rum]);
  return state;
}

export function decodeReplay(replay, details = {}) {
  if (!replay || !Array.isArray(replay.frames)) throw new Error("Replay has no frames");
  const states = [];
  const pending = new Map();
  for (const frame of replay.frames) {
    if (frame.agentId === 0 || frame.agentId === 1) {
      pending.set(frame.agentId, String(frame.stdout ?? "").trim().split(/\r?\n/).filter(Boolean));
    }
    if (!frame.keyframe || typeof frame.view !== "string" || frame.view.trim().split(/\r?\n/).length <= 2) continue;
    const state = decodeView(frame.view, states.length === 0);
    const previous = states[states.length - 1];
    state.actions = [];
    if (previous) {
      for (const ship of previous.ships.filter(entry => entry[6] > 0)) {
        state.actions.push({id: ship[0], owner: ship[1], command: pending.get(ship[1])?.shift() ?? "WAIT",
          effective: state.effective[ship[0]] ?? "WAIT"});
      }
      pending.clear();
    }
    const logged = details?.turns?.find(turn => turn.turn === state.turn);
    state.elapsed = logged?.elapsed_ms ?? [];
    state.forfeits = (details?.forfeits ?? []).filter(entry => entry.turn + 1 === state.turn);
    states.push(state);
  }
  if (!states.length) throw new Error("Replay has no playable states");
  return states;
}

export function neighbor([column, row], direction) {
  const offsets = [[1, 0], [row & 1, -1], [(row & 1) - 1, -1], [-1, 0], [(row & 1) - 1, 1], [row & 1, 1]];
  return [column + offsets[direction][0], row + offsets[direction][1]];
}