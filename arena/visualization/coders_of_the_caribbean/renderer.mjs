import {neighbor} from "./replay.mjs";

const colors = ["#07818d", "#c9513c"];

export function createBoard(canvas, onSelect) {
  const context = canvas.getContext("2d");
  let state = null;
  let selected = null;
  let radius = 10;
  let offset = [0, 0];
  const point = ([column, row]) => [offset[0] + (column + (row & 1) * 0.5) * Math.sqrt(3) * radius, offset[1] + row * 1.5 * radius];
  const path = (points, close = true) => {
    context.beginPath();
    points.forEach(([horizontal, vertical], index) => index ? context.lineTo(horizontal, vertical) : context.moveTo(horizontal, vertical));
    if (close) context.closePath();
  };
  const hex = cell => {
    const [horizontal, vertical] = point(cell);
    path(Array.from({length: 6}, (_, index) => {
      const angle = (index * 60 - 30) * Math.PI / 180;
      return [horizontal + radius * Math.cos(angle), vertical + radius * Math.sin(angle)];
    }));
  };

  function draw() {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) return;
    const ratio = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    radius = Math.max(2, Math.min((width - 48) / (23.5 * Math.sqrt(3)), (height - 43) / 32));
    offset = [(width - 23.5 * Math.sqrt(3) * radius) / 2 + Math.sqrt(3) * radius / 2, (height - 32 * radius) / 2 + radius];
    context.fillStyle = "#e3eeea";
    context.fillRect(0, 0, width, height);
    for (let row = 0; row < 21; row += 1) {
      for (let column = 0; column < 23; column += 1) {
        hex([column, row]);
        context.fillStyle = (column + row) % 3 === 0 ? "#dfebe6" : "#e8f1ec";
        context.fill();
        context.strokeStyle = "#bfd3c9";
        context.lineWidth = 0.55;
        context.stroke();
      }
    }
    context.font = "9px Menlo, monospace";
    context.fillStyle = "#7b9487";
    context.textAlign = "center";
    for (let column = 0; column < 23; column += 2) context.fillText(column, point([column, 0])[0], offset[1] - radius - 7);
    for (let row = 0; row < 21; row += 2) context.fillText(row, offset[0] - radius - 10, point([0, row])[1] + 3);
    if (!state) return;
    for (const [id, column, row, rum] of state.barrels) {
      const [horizontal, vertical] = point([column, row]);
      context.save(); context.translate(horizontal, vertical);
      context.fillStyle = "#c59b57"; context.strokeStyle = "#7d6238"; context.lineWidth = 1;
      context.beginPath(); context.roundRect(-radius * .35, -radius * .47, radius * .7, radius * .94, radius * .16); context.fill(); context.stroke();
      context.strokeStyle = "#665f4e";
      for (const level of [-.23, .23]) { context.beginPath(); context.moveTo(-radius * .35, radius * level); context.lineTo(radius * .35, radius * level); context.stroke(); }
      context.restore();
    }
    for (const [id, column, row] of state.mines) {
      const [horizontal, vertical] = point([column, row]);
      context.strokeStyle = "#52645e"; context.lineWidth = 1.4;
      for (let index = 0; index < 8; index += 1) {
        const angle = index * Math.PI / 4;
        path([[horizontal, vertical], [horizontal + Math.cos(angle) * radius * .48, vertical + Math.sin(angle) * radius * .48]], false); context.stroke();
      }
      context.fillStyle = "#56655f"; context.beginPath(); context.arc(horizontal, vertical, radius * .3, 0, Math.PI * 2); context.fill();
      context.fillStyle = "#e9b77f"; context.beginPath(); context.arc(horizontal - radius * .08, vertical - radius * .08, radius * .08, 0, Math.PI * 2); context.fill();
    }
    for (const ship of state.ships) {
      const [id, owner, column, row, direction, speed, rum] = ship;
      const [horizontal, vertical] = point([column, row]);
      const bow = point(neighbor([column, row], direction));
      if (id === selected) {
        context.save();
        context.strokeStyle = colors[owner]; context.lineWidth = 1.6; context.setLineDash([3, 3]);
        for (const cell of [[column, row], neighbor([column, row], direction), neighbor([column, row], (direction + 3) % 6)]) { hex(cell); context.stroke(); }
        context.restore();
      }
      context.save();
      context.translate(horizontal, vertical);
      context.rotate(Math.atan2(bow[1] - vertical, bow[0] - horizontal));
      context.globalAlpha = rum > 0 ? 1 : .22;
      const length = radius * 2.32;
      context.beginPath(); context.moveTo(length, 0);
      context.bezierCurveTo(length * .5, -radius * .73, -length * .6, -radius * .73, -length, -radius * .3);
      context.lineTo(-length, radius * .3);
      context.bezierCurveTo(-length * .6, radius * .73, length * .5, radius * .73, length, 0);
      context.fillStyle = colors[owner]; context.fill();
      context.strokeStyle = owner === 0 ? "#07545e" : "#87372b"; context.lineWidth = 1.2; context.stroke();
      path([[-radius * .5, -.43 * radius], [radius * .8, -.43 * radius], [radius * .75, .4 * radius], [-radius * .55, .4 * radius]]);
      context.fillStyle = "#fffbef"; context.fill();
      path([[0, -radius * .6], [0, radius * .6]], false); context.strokeStyle = "#655c48"; context.lineWidth = 1; context.stroke();
      context.restore();
      context.fillStyle = "#1c3833"; context.textAlign = "center"; context.font = `bold ${Math.max(8, radius * .63)}px Menlo, monospace`;
      context.fillText(id, horizontal, vertical + radius * .23);
      if (rum > 0) {
        context.fillStyle = "#ffffffd9"; context.fillRect(horizontal - radius, vertical + radius * .96, radius * 2, 3);
        context.fillStyle = colors[owner]; context.fillRect(horizontal - radius, vertical + radius * .96, radius * 2 * rum / 100, 3);
      }
    }
    for (const [id, column, row, owner, remaining] of state.balls) {
      const [horizontal, vertical] = point([column, row]);
      context.strokeStyle = "#be623f"; context.lineWidth = 1.4;
      context.beginPath(); context.arc(horizontal, vertical, radius * (remaining === 0 ? .8 : .58), 0, Math.PI * 2); context.stroke();
      for (const [deltaX, deltaY] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
        path([[horizontal + deltaX * radius * .35, vertical + deltaY * radius * .35], [horizontal + deltaX * radius * .9, vertical + deltaY * radius * .9]], false); context.stroke();
      }
      context.fillStyle = "#8d422b"; context.font = `bold ${Math.max(8, radius * .7)}px Menlo, monospace`;
      context.textAlign = "center"; context.fillText(remaining === 0 ? "×" : remaining, horizontal, vertical + 3);
    }
  }

  function pick(event) {
    if (!state) return null;
    const rect = canvas.getBoundingClientRect();
    const pointer = [event.clientX - rect.left, event.clientY - rect.top];
    let best = null;
    let separation = radius * 1.1;
    for (const ship of state.ships) {
      for (const cell of [ship.slice(2, 4), neighbor(ship.slice(2, 4), ship[4]), neighbor(ship.slice(2, 4), (ship[4] + 3) % 6)]) {
        const target = point(cell);
        const distance = Math.hypot(target[0] - pointer[0], target[1] - pointer[1]);
        if (distance < separation) { best = ship; separation = distance; }
      }
    }
    return best;
  }
  const click = event => { const ship = pick(event); if (ship) onSelect(ship[0]); };
  const hover = event => { const ship = pick(event); canvas.title = ship ? `Ship #${ship[0]} · ${ship[6]} rum · speed ${ship[5]} · (${ship[2]}, ${ship[3]})` : ""; };
  canvas.addEventListener("click", click);
  canvas.addEventListener("pointermove", hover);
  const observer = new ResizeObserver(draw);
  observer.observe(canvas);
  return {
    setState(next, id) { state = next; selected = id; canvas.setAttribute("aria-label", `Hex map at turn ${state.turn}, ${state.ships.filter(ship => ship[6] > 0).length} live ships`); draw(); },
    destroy() { observer.disconnect(); canvas.removeEventListener("click", click); canvas.removeEventListener("pointermove", hover); }
  };
}
