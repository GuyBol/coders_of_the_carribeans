import {decodeReplay} from "./replay.mjs";
import {createBoard} from "./renderer.mjs";

const directions = ["E", "NE", "NW", "W", "SW", "SE"];

export function createGameView(host, data) {
  if (!document.getElementById("caribbean-style")) {
    const style = document.createElement("link");
    style.id = "caribbean-style"; style.rel = "stylesheet";
    style.href = new URL("./style.css", import.meta.url).href;
    document.head.append(style);
  }
  const frames = decodeReplay(data.replay, data.details);
  const root = document.createElement("div");
  root.className = "caribbean";
  root.innerHTML = `<section class="sea-column"><div class="scoreboard"><div class="team-score team-0"><span class="team-swatch"></span><div><h2></h2><p></p></div><strong></strong></div><span class="versus">vs</span><div class="team-score team-1"><span class="team-swatch"></span><div><h2></h2><p></p></div><strong></strong></div></div><div class="chart"><canvas tabindex="0" role="img" aria-label="Caribbean hex map"></canvas></div><div class="chart-caption"><span class="map-source"></span><div class="map-legend"><span><b class="legend-barrel"></b>Rum</span><span><b class="legend-mine"></b>Mines</span><span><b class="legend-ball"></b>Fire</span></div></div></section><aside class="inspector"><section class="fleet-panel"><h2>Fleet</h2><div class="fleet-list"></div></section><section class="ship-panel"><h2 class="ship-title">Ship</h2><dl class="ship-data"></dl></section><section class="orders-panel"><h2>Orders <span class="order-turn"></span></h2><div class="orders"></div></section><div class="forfeit-note" hidden></div></aside>`;
  host.replaceChildren(root);
  let index = 0;
  let selected = frames[0].ships.find(ship => ship[6] > 0)?.[0] ?? null;
  const canvas = root.querySelector("canvas");
  const board = createBoard(canvas, id => { selected = id; render(); });
  const source = data.metadata?.source_map ?? data.replay.source_map;
  root.querySelector(".map-source").textContent = source ? `Map ${source.game_id} · ${data.metadata.ships ?? frames[0].ships.length / 2} ships / player` : `Local map · ${frames[0].ships.length / 2} ships / player`;
  const players = data.match.players;

  function render() {
    const state = frames[index];
    for (let owner = 0; owner < 2; owner += 1) {
      const team = root.querySelector(`.team-${owner}`);
      const ships = state.ships.filter(ship => ship[1] === owner && ship[6] > 0);
      team.querySelector("h2").textContent = players[owner];
      team.querySelector("p").textContent = `${ships.length} ${ships.length === 1 ? "ship" : "ships"}`;
      team.querySelector("strong").textContent = ships.reduce((total, ship) => total + Math.max(0, ship[6]), 0);
    }
    const fleet = root.querySelector(".fleet-list");
    fleet.replaceChildren();
    for (const ship of state.ships) {
      const button = document.createElement("button");
      button.className = `fleet-ship team-${ship[1]}${selected === ship[0] ? " selected" : ""}${ship[6] <= 0 ? " sunk" : ""}`;
      button.setAttribute("aria-label", `Inspect ship ${ship[0]}`);
      button.setAttribute("aria-pressed", String(selected === ship[0]));
      const label = document.createElement("span"); label.textContent = `#${ship[0]}`;
      const bar = document.createElement("progress"); bar.max = 100; bar.value = Math.max(0, ship[6]); bar.setAttribute("aria-label", `Ship ${ship[0]} rum`);
      const amount = document.createElement("b"); amount.textContent = ship[6] > 0 ? ship[6] : "Sunk";
      button.append(label, bar, amount);
      button.addEventListener("click", () => { selected = ship[0]; render(); });
      fleet.append(button);
    }
    const ship = state.ships.find(entry => entry[0] === selected);
    root.querySelector(".ship-title").textContent = ship ? `Ship #${ship[0]}` : "Ship";
    const details = root.querySelector(".ship-data"); details.replaceChildren();
    if (ship) {
      for (const [key, value] of [["Captain", players[ship[1]]], ["Position", `${ship[2]}, ${ship[3]}`], ["Heading", directions[ship[4]]], ["Speed", ship[5]], ["Rum", `${ship[6]} / 100`]]) {
        const name = document.createElement("dt"); name.textContent = key;
        const description = document.createElement("dd"); description.textContent = value;
        details.append(name, description);
      }
    }
    root.querySelector(".order-turn").textContent = String(state.turn).padStart(3, "0");
    const orders = root.querySelector(".orders"); orders.replaceChildren();
    if (!state.actions.length) { const text = document.createElement("p"); text.textContent = "Initial deployment"; text.className = "muted"; orders.append(text); }
    for (const action of state.actions) {
      const row = document.createElement("div"); row.className = `order-row team-${action.owner}`;
      const name = document.createElement("span"); name.textContent = `#${action.id}`;
      const command = document.createElement("code"); command.textContent = action.command;
      const effective = document.createElement("small");
      if (action.command.split(/\s+/)[0].toUpperCase() === "MOVE") effective.textContent = action.effective;
      row.append(name, command, effective); orders.append(row);
    }
    const note = root.querySelector(".forfeit-note");
    note.hidden = state.forfeits.length === 0;
    note.textContent = state.forfeits.map(entry => `${players[entry.player]}: ${entry.error}`).join(" · ");
    board.setState(state, selected);
  }
  return {frames, setFrame(next) { index = next; render(); }, destroy() { board.destroy(); root.remove(); }};
}
