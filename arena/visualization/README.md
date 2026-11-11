# Arena Visualization

Read-only browser viewer for locally captured arena games. The generic library
and playback controls are separate from the Coders of the Caribbean renderer.
No simulator or bot process is started when viewing a replay.

## Run

From the project root:

```sh
ruby arena/visualization/server.rb
```

Open the printed URL, normally <http://127.0.0.1:8765>. The server binds only to
`127.0.0.1`. If the requested port is occupied, it tries the next 20 ports.
Stop it with Ctrl+C.

Requires Ruby 2.6 or newer with WEBrick, and a modern browser supporting native
JavaScript modules, Canvas 2D, and ResizeObserver. WEBrick ships with older Ruby
versions; on installations without it, run `gem install webrick`. No frontend
build, npm install, external fonts, or network access is needed. Lucide icons
are bundled locally with their license in `vendor/lucide.LICENSE`.

By default, the server searches recursively for `tournament.json` inside
`arena/runs` and the sibling `../local-arena-games` archive. Select other archive
or individual run directories with repeatable `--root` flags; explicit roots
replace the defaults:

```sh
ruby arena/visualization/server.rb \
  --root arena/runs/50-games \
  --root ../local-arena-games \
  --port 8800
```

Missing roots are skipped at startup. Create missing directories before starting
the server. Refresh the tournament library to discover newly completed games in
existing roots; playback does not automatically follow an ongoing match.

## Playback

Choose a tournament and game. The library shows final scores and Elo standings;
its filter matches game IDs, bot names, and seeds. Standings are collapsible on
mobile.

- Play/pause, step backward/forward, or jump to the first/last frame.
- Scrub the timeline or enter a turn number; turn 0 is the initial state.
- Select playback speed from 0.5x to 4x. Playback pauses at the end.
- Select a ship on the board or in the fleet list to inspect its state.
- Inspect the orders that produced the current frame, including resolved MOVE
  commands and recorded forfeits.
- Copy the browser URL to retain the selected tournament, game, and turn on
  the same machine and archive location.

Space toggles playback, Left/Right step frames, and Home/End jump to the bounds
when focus is outside form controls. Playback pauses when the tab is hidden.

The Caribbean board displays ships, hull footprints, rum, barrels, mines, and
cannonball countdowns. The map caption identifies the original captured map,
not the locally played game's public origin. Frames display saved states with
simplified graphics: there is no physics resimulation, interpolation, or claim
of byte-for-byte compatibility with the official CodinGame viewer.

## Renderer Contract

The server reads schema-version-1 tournament reports and each successful
match's `view` object with `interface_version: 1`. It exposes:

- `GET /api/runs`: discovered runs with opaque IDs.
- `GET /api/run?id=ID`: the tournament report.
- `GET /api/game?run=ID&match=N`: `{game, match, replay, metadata, details}`.

`details` defaults to an empty object when the match has no details reference.
Capture paths must resolve to JSON files within their own run directory;
traversal and escaping symlinks are rejected. Only configured local archives
should be trusted. The server is not intended for public hosting.

To support another game, add its renderer in a dedicated subfolder and register
its game identifier in the `renderers` table in `app.mjs`. Export
`createGameView(host, data)`, returning:

```js
{
  frames,                 // Array of decoded timeline states.
  setFrame(index) {},      // Render a zero-based timeline index.
  destroy() {}             // Remove the view and release observers/listeners.
}
```

The controller owns playback, selection, and URLs. The renderer owns decoding,
game graphics, and inspection. The generic server and arena scheduler do not
need to import game rules. An unsupported game produces an explicit error
instead of being interpreted as Caribbean data.

## Tests

```sh
ruby arena/visualization/test.rb
node arena/visualization/test.mjs
node --check arena/visualization/app.mjs
```

Ruby tests cover discovery, generic capture loading, optional details, missing
games, engine failures, and path/symlink containment. Node is needed only for
tests: fixtures check replay decoding and coordinate conversion; when saved
runs exist under `arena/runs`, every decoded state and command is also compared
against its corresponding match log. Browser checks cover desktop/mobile
layouts, nonblank canvas output, playback, frame navigation, and ship selection.
