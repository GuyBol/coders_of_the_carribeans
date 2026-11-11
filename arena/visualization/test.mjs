import assert from "node:assert/strict";
import {readFileSync, readdirSync, existsSync} from "node:fs";
import {fileURLToPath} from "node:url";
import {decodeReplay, neighbor} from "./coders_of_the_caribbean/replay.mjs";

const root = fileURLToPath(new URL("../runs/", import.meta.url));
const fixtureView = (frame, rum) => `${frame === 0 ? "0\nCodersOfTheCaribbean\n2\n23 21 1 5 1" : "2 endReached"}\n0\n0 5 5 0 ${rum} 0 SLOWER\n1\n1 15 17 3 ${rum} 0 WAIT\n1\n8 4 7 15 17 3 2 1\n1\n5 9 2\n1\n6 11 8 17\n0\n`;
const fixture = {frames: [
  {agentId: -1, keyframe: true, view: fixtureView(0, 1)},
  {agentId: 0, keyframe: false, view: "1\n", stdout: "MOVE 5 5\n"},
  {agentId: 1, keyframe: true, view: fixtureView(2, 0), stdout: "WAIT\n"}
]};
const decoded = decodeReplay(fixture);
assert.equal(decoded.length, 2);
assert.deepEqual(decoded[0].ships[1], [1, 1, 17, 15, 3, 0, 1]);
assert.deepEqual(decoded[0].balls[0], [8, 7, 4, 1, 2, 17, 15, 3]);
assert.deepEqual(decoded[0].mines[0], [5, 2, 9]);
assert.deepEqual(decoded[0].barrels[0], [6, 8, 11, 17]);
assert.equal(decoded[1].actions[0].command, "MOVE 5 5");
assert.equal(decoded[1].actions[0].effective, "SLOWER");
let checked = 0;
for (const run of existsSync(root) ? readdirSync(root) : []) {
  let tournament;
  try { tournament = JSON.parse(readFileSync(`${root}/${run}/tournament.json`, "utf8")); }
  catch { continue; }
  for (const match of tournament.matches ?? []) {
    if (!match.view || match.view.game !== "coders-of-the-caribbean") continue;
    const replay = JSON.parse(readFileSync(`${root}/${run}/${match.view.replay}`, "utf8"));
    const details = JSON.parse(readFileSync(`${root}/${run}/${match.view.details}`, "utf8"));
    const frames = decodeReplay(replay, details);
    assert.equal(frames.length, details.turns.length + 1);
    for (const [index, frame] of frames.entries()) {
      const expected = index === 0 ? details.initial : details.turns[index - 1].state;
      for (const kind of ["ships", "barrels", "mines", "balls"]) {
        const canonical = entities => entities.map(entity => kind === "ships" ? entity.slice(0, 7) : entity).sort((first, second) => first[0] - second[0]);
        assert.deepEqual(canonical(frame[kind]), canonical(expected[kind]), `${run}/${match.id} frame ${index}: ${kind}`);
      }
      if (index > 0) {
        assert.deepEqual(frame.actions.map(action => [action.id, action.command]).sort((first, second) => first[0] - second[0]),
          details.turns[index - 1].actions.slice().sort((first, second) => first[0] - second[0]));
      }
    }
    checked += 1;
  }
}
assert.deepEqual(neighbor([5, 5], 1), [6, 4]);
assert.throws(() => decodeReplay({frames: []}), /no playable states/);
assert.throws(() => decodeReplay({frames: [{keyframe: true, view: "0\nbroken\n2\n23 21 1 5 1"}]}), /Unsupported replay/);
console.log(`PASS browser replay decoder fixtures and exact states/commands across ${checked} available saved games`);
