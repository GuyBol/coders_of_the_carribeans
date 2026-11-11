const byId = id => document.getElementById(id);
const renderers = {"coders-of-the-caribbean": () => import("./coders_of_the_caribbean/view.mjs")};
let tournament = null;
let runId = "";
let selectedId = null;
let view = null;
let frame = 0;
let timer = null;
let generation = 0;
const icons = () => window.lucide?.createIcons();

async function api(path, query = {}) {
  const response = await fetch(`${path}?${new URLSearchParams(query)}`);
  const value = await response.json();
  if (!response.ok) throw new Error(value.error ?? `Request failed (${response.status})`);
  return value;
}

function empty(message) {
  byId("game-host").replaceChildren();
  const text = document.createElement("div");
  text.className = "empty-state";
  text.setAttribute("role", "status");
  text.textContent = message;
  byId("game-host").append(text);
}

function enabled(value) {
  for (const id of ["first", "previous", "play", "next", "last", "timeline", "frame"]) byId(id).disabled = !value;
}

function pause() {
  clearInterval(timer);
  timer = null;
  byId("play").innerHTML = '<i data-lucide="play" aria-hidden="true"></i>';
  byId("play").setAttribute("aria-label", "Play");
  byId("play").setAttribute("aria-pressed", "false");
  byId("play").title = "Play";
  icons();
}

function resetGame(message) {
  pause();
  enabled(false);
  view?.destroy();
  view = null;
  selectedId = null;
  for (const id of ["timeline", "frame"]) { byId(id).value = 0; byId(id).max = 0; }
  byId("frame-total").textContent = "/ 0";
  byId("notice").hidden = true;
  byId("game-title").textContent = "Replay Room";
  byId("game-subtitle").textContent = "";
  byId("game-result").textContent = "";
  empty(message);
}

function setFrame(next) {
  if (!view) return;
  frame = Math.max(0, Math.min(view.frames.length - 1, Number.isFinite(Number(next)) ? Math.trunc(Number(next)) : 0));
  view.setFrame(frame);
  byId("timeline").value = frame;
  byId("frame").value = frame;
  const query = new URLSearchParams({run: runId, match: selectedId, turn: frame});
  history.replaceState(null, "", `?${query}`);
  if (frame === view.frames.length - 1 && timer) pause();
}

function play() {
  if (!view || view.frames.length < 2) return;
  if (timer) { pause(); return; }
  if (frame === view.frames.length - 1) setFrame(0);
  timer = setInterval(() => setFrame(frame + 1), 650 / Number(byId("speed").value));
  byId("play").innerHTML = '<i data-lucide="pause" aria-hidden="true"></i>';
  byId("play").setAttribute("aria-label", "Pause");
  byId("play").setAttribute("aria-pressed", "true");
  byId("play").title = "Pause";
  icons();
}

function renderMatches() {
  const filter = byId("search").value.toLowerCase();
  byId("matches").replaceChildren();
  for (const match of tournament?.matches ?? []) {
    if (!`${match.id} ${match.players?.join(" ")} ${match.seed}`.toLowerCase().includes(filter)) continue;
    const button = document.createElement("button");
    button.className = `match-row${String(match.id) === selectedId ? " active" : ""}`;
    button.setAttribute("aria-pressed", String(String(match.id) === selectedId));
    button.setAttribute("aria-label", `Game ${match.id}: ${match.players?.join(" versus ")}`);
    const caption = document.createElement("div");
    caption.className = "match-caption";
    const number = document.createElement("span");
    number.textContent = `GAME ${String(match.id).padStart(2, "0")}`;
    const result = document.createElement("span");
    result.textContent = match.error ? "ERROR" : match.forfeits?.length ? "FORFEIT" : match.winner == null ? "DRAW" : "FINAL";
    if (match.error || match.forfeits?.length) result.className = "match-error";
    caption.append(number, result);
    const players = document.createElement("div");
    players.className = "match-players";
    (match.players ?? []).forEach((name, seat) => {
      const label = document.createElement("span");
      label.textContent = name;
      const score = document.createElement("b");
      score.textContent = match.scores?.[seat] ?? "—";
      players.append(label, score);
    });
    button.append(caption, players);
    button.addEventListener("click", () => loadGame(match));
    byId("matches").append(button);
  }
}

function renderRankings() {
  byId("rankings").replaceChildren();
  for (const row of tournament.rankings) {
    const element = document.createElement("tr");
    for (const text of [row.bot, `${row.wins}–${row.draws}–${row.losses}`, Number(row.rating).toFixed(1)]) {
      const cell = document.createElement("td");
      cell.textContent = text;
      element.append(cell);
    }
    byId("rankings").append(element);
  }
}

async function loadGame(match, requestedFrame = 0) {
  const version = ++generation;
  pause();
  enabled(false);
  view?.destroy();
  view = null;
  selectedId = String(match.id);
  renderMatches();
  byId("notice").hidden = true;
  byId("game-title").textContent = `Game ${String(match.id).padStart(2, "0")}`;
  byId("game-subtitle").textContent = match.players.join(" vs ");
  byId("game-result").textContent = match.error ? "Engine error" : match.winner == null ? "Draw" : `${match.players[match.winner]} won`;
  empty("Loading game…");
  try {
    if (match.error) throw new Error(match.error);
    const data = await api("/api/game", {run: runId, match: match.id});
    const loader = renderers[data.game];
    if (!loader) throw new Error(`No renderer registered for ${data.game}`);
    const renderer = await loader();
    if (version !== generation) return;
    view = renderer.createGameView(byId("game-host"), data);
    byId("game-category").textContent = data.game === "coders-of-the-caribbean" ? "CODERS OF THE CARIBBEAN" : data.game;
    byId("timeline").max = view.frames.length - 1;
    byId("frame").max = view.frames.length - 1;
    byId("frame-total").textContent = `/ ${view.frames.length - 1}`;
    enabled(true);
    setFrame(requestedFrame);
    icons();
  } catch (error) {
    if (version !== generation) return;
    empty("Game unavailable");
    byId("notice").textContent = error.message;
    byId("notice").hidden = false;
  }
}

async function loadRun(id, requestedMatch, requestedFrame = 0) {
  const version = ++generation;
  pause();
  enabled(false);
  try {
    const report = await api("/api/run", {id});
    if (version !== generation) return;
    runId = id;
    tournament = report;
    byId("game-count").textContent = `${report.completed_games ?? report.matches.length}/${report.planned_games ?? report.matches.length}`;
    renderRankings();
    renderMatches();
    const match = report.matches.find(entry => String(entry.id) === requestedMatch) ?? report.matches.find(entry => !entry.error) ?? report.matches[0];
    if (match) await loadGame(match, requestedFrame);
    else resetGame("No completed games");
  } catch (error) { if (version === generation) resetGame(error.message); }
}

async function loadRuns() {
  byId("refresh").disabled = true;
  try {
    const runs = await api("/api/runs");
    const query = new URLSearchParams(location.search);
    byId("run-select").replaceChildren();
    for (const run of runs) {
      const option = document.createElement("option");
      option.value = run.id;
      option.textContent = `${run.name} · ${run.completed_games ?? "?"} games`;
      byId("run-select").append(option);
    }
    if (!runs.length) {
      generation += 1;
      tournament = null;
      byId("matches").replaceChildren();
      byId("rankings").replaceChildren();
      byId("game-count").textContent = "0/0";
      resetGame("No tournaments found");
      return;
    }
    const chosen = runs.find(run => run.id === query.get("run")) ?? runs[0];
    byId("run-select").value = chosen.id;
    await loadRun(chosen.id, query.get("match"), Number(query.get("turn") ?? 0));
  } catch (error) { generation += 1; resetGame(error.message); }
  finally { byId("refresh").disabled = false; }
}

byId("refresh").addEventListener("click", loadRuns);
byId("run-select").addEventListener("change", event => loadRun(event.target.value));
byId("search").addEventListener("input", renderMatches);
byId("first").addEventListener("click", () => { pause(); setFrame(0); });
byId("last").addEventListener("click", () => { pause(); setFrame(view.frames.length - 1); });
byId("previous").addEventListener("click", () => { pause(); setFrame(frame - 1); });
byId("next").addEventListener("click", () => { pause(); setFrame(frame + 1); });
byId("play").addEventListener("click", play);
byId("timeline").addEventListener("input", event => { pause(); setFrame(event.target.value); });
byId("frame").addEventListener("change", event => { pause(); setFrame(event.target.value); });
byId("speed").addEventListener("change", () => { if (timer) { pause(); play(); } });
document.addEventListener("visibilitychange", () => { if (document.hidden) pause(); });
document.addEventListener("keydown", event => {
  if (!view || event.target.closest("input, select, textarea, button")) return;
  if (event.code === "Space") { event.preventDefault(); play(); }
  if (["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) {
    event.preventDefault(); pause();
    setFrame(event.key === "Home" ? 0 : event.key === "End" ? view.frames.length - 1 : frame + (event.key === "ArrowLeft" ? -1 : 1));
  }
});
icons();
const narrowScreen = matchMedia("(max-width: 700px)");
const resizeStandings = () => { document.querySelector(".standings").open = !narrowScreen.matches; };
narrowScreen.addEventListener("change", resizeStandings);
resizeStandings();
loadRuns();
