const canvas = document.getElementById('board');
const ctx = canvas.getContext('2d');

const playPauseBtn = document.getElementById('playPause');
const stepBackBtn = document.getElementById('stepBack');
const stepForwardBtn = document.getElementById('stepForward');
const resetBtn = document.getElementById('reset');
const speedInput = document.getElementById('speed');
const scrubber = document.getElementById('scrubber');
const fileInput = document.getElementById('fileInput');
const scenarioEl = document.getElementById('scenario');
const statusEl = document.getElementById('status');
const selectionEl = document.getElementById('selection');

const EDGE_TO_BIT = { north: 0, east: 1, south: 2, west: 3 };
const EDGE_VECTORS = {
  north: [0, 1],
  east: [1, 0],
  south: [0, -1],
  west: [-1, 0],
};

let playback = null;
let isPlaying = false;
let currentTickIndex = 0;
let selectedChip = null;
let lastFrameMs = 0;
let accumulator = 0;

function resize() {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  canvas.width = Math.floor(window.innerWidth * dpr);
  canvas.height = Math.floor(window.innerHeight * dpr);
  canvas.style.width = `${window.innerWidth}px`;
  canvas.style.height = `${window.innerHeight}px`;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}

window.addEventListener('resize', resize);

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

function buildStateAt(index) {
  if (!playback) return null;
  const base = new Map();
  for (const chip of playback.initial_chips || []) {
    base.set(`${chip.x},${chip.y}`, deepClone(chip));
  }
  for (const update of playback.chip_updates || []) {
    if ((update.tick ?? 0) > index) continue;
    const key = `${update.x},${update.y}`;
    const prev = base.get(key) || { x: update.x, y: update.y, chip_id: 1, up_mask: 0, down_mask: 0 };
    base.set(key, { ...prev, ...deepClone(update) });
  }
  return base;
}

function tickData() {
  if (!playback) return { state: null, packetEvents: [], chipEvents: [], fpgaEvent: null };
  const clamped = Math.max(0, Math.min(currentTickIndex, playback.total_ticks || 0));
  const packetEvents = (playback.packet_spans || []).filter((span) => span.start_tick <= clamped && clamped < span.end_tick);
  const chipEvents = (playback.chip_updates || []).filter((update) => (update.tick ?? 0) === clamped);
  const fpgaEvent = (playback.fpga_spans || []).find((span) => span.start_tick <= clamped && clamped < span.end_tick) || null;
  return {
    state: buildStateAt(clamped),
    packetEvents,
    chipEvents,
    fpgaEvent,
  };
}

function updateHud() {
  if (!playback) {
    scenarioEl.textContent = 'Scenario: none';
    statusEl.textContent = 'Tick: 0 / 0';
    selectionEl.textContent = 'Selection: none';
    return;
  }
  scenarioEl.textContent = `Scenario: ${playback.name || 'unnamed'}`;
  const { state, chipEvents, fpgaEvent } = tickData();
  const parts = [`Tick: ${currentTickIndex} / ${Math.max(0, playback.total_ticks || 0)}`];
  if (fpgaEvent) parts.push(`FPGA TX: ${fpgaEvent.label || fpgaEvent.packet_type || 'frame'}`);
  if (chipEvents.length > 0) parts.push(`chip updates: ${chipEvents.length}`);
  statusEl.textContent = parts.join(' | ');
  if (selectedChip) {
    const chip = state?.get(`${selectedChip.x},${selectedChip.y}`);
    if (chip) {
      const activeUpdate = chipEvents.find((update) => update.x === selectedChip.x && update.y === selectedChip.y);
      let line = `Selection: chip ${chip.chip_id} at (${chip.x},${chip.y}) U${(chip.up_mask || 0).toString(2).padStart(4, '0')} D${(chip.down_mask || 0).toString(2).padStart(4, '0')}`;
      if (activeUpdate) {
        line += ` | applied reg ${activeUpdate.register_addr} = 0x${Number(activeUpdate.register_data || 0).toString(16).toUpperCase().padStart(2, '0')}`;
      }
      selectionEl.textContent = line;
      return;
    }
  }
  if (chipEvents.length > 0) {
    const update = chipEvents[0];
    selectionEl.textContent = `Selection: config applied at chip (${update.x},${update.y}) reg ${update.register_addr} = 0x${Number(update.register_data || 0).toString(16).toUpperCase().padStart(2, '0')}`;
    return;
  }
  selectionEl.textContent = 'Selection: none';
}

function laneEnabled(mask, edge) {
  return ((mask >> EDGE_TO_BIT[edge]) & 1) === 1;
}

function drawLane(cx, cy, cell, edge, color, active = false) {
  const half = cell * 0.42;
  let x2 = cx;
  let y2 = cy;
  if (edge === 'north') y2 -= half;
  if (edge === 'south') y2 += half;
  if (edge === 'east') x2 += half;
  if (edge === 'west') x2 -= half;

  const dx = x2 - cx;
  const dy = y2 - cy;
  const len = Math.hypot(dx, dy) || 1;
  const ux = dx / len;
  const uy = dy / len;
  const px = -uy;
  const py = ux;
  const headLen = Math.max(8, cell * 0.12);
  const headWidth = Math.max(5, cell * 0.07);
  const shaftEndX = x2 - ux * headLen;
  const shaftEndY = y2 - uy * headLen;

  ctx.strokeStyle = color;
  ctx.lineWidth = active ? 6 : 3;
  ctx.beginPath();
  ctx.moveTo(cx, cy);
  ctx.lineTo(shaftEndX, shaftEndY);
  ctx.stroke();

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x2, y2);
  ctx.lineTo(shaftEndX + px * headWidth, shaftEndY + py * headWidth);
  ctx.lineTo(shaftEndX - px * headWidth, shaftEndY - py * headWidth);
  ctx.closePath();
  ctx.fill();
}

function drawPacket(event, layout) {
  const src = layout.cellCenter(event.src[0], event.src[1]);
  const dst = layout.cellCenter(event.dst[0], event.dst[1]);
  const duration = Math.max(1, (event.end_tick || 0) - (event.start_tick || 0));
  const t = Math.max(0, Math.min(1, (currentTickIndex - (event.start_tick || 0)) / duration));
  const x = src.x + (dst.x - src.x) * t;
  const y = src.y + (dst.y - src.y) * t;
  const color = {
    config_write: '#7cff7c',
    config_read_request: '#4db0ff',
    config_read_reply: '#ffb04d',
    event_data: '#ff5e87',
  }[event.packet_type] || '#d7f06a';
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, Math.max(5, layout.cell * 0.1), 0, Math.PI * 2);
  ctx.fill();
  if (event.label) {
    ctx.fillStyle = '#e8edf8';
    ctx.font = '11px ui-monospace, monospace';
    ctx.fillText(event.label, x + 10, y - 10);
  }
}

function drawFpga(layout, activeSpan) {
  if (!playback?.source) return;
  const src = layout.cellCenter(playback.source.x, playback.source.y);
  const boxW = layout.cell * 0.64;
  const boxH = layout.cell * 0.24;
  const gap = layout.cell * 0.16;
  const left = src.x - boxW * 0.5;
  const top = src.y + layout.cell * 0.42 + gap;

  ctx.fillStyle = '#121925';
  ctx.strokeStyle = '#4b5a73';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.roundRect(left, top, boxW, boxH, 8);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = '#eef4ff';
  ctx.font = `${Math.max(10, layout.cell * 0.12)}px ui-monospace, monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('FPGA', src.x, top + boxH * 0.5);
  ctx.textBaseline = 'alphabetic';

  const arrowColor = activeSpan ? '#4db0ff' : '#394455';
  drawLane(src.x, top, layout.cell * 0.7, 'north', arrowColor, Boolean(activeSpan));
}

function draw() {
  const width = window.innerWidth;
  const height = window.innerHeight;
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = '#0a0d12';
  ctx.fillRect(0, 0, width, height);

  if (!playback) {
    updateHud();
    return;
  }

  const rows = playback.rows;
  const cols = playback.cols;
  const marginLeft = 360;
  const margin = 30;
  const availW = Math.max(200, width - marginLeft - margin);
  const availH = Math.max(200, height - margin * 2);
  const cell = Math.min(availW / cols, availH / rows);
  const gridW = cell * cols;
  const gridH = cell * rows;
  const originX = marginLeft + (availW - gridW) * 0.5;
  const originY = margin + (availH - gridH) * 0.5;

  const layout = {
    cell,
    cellCenter(x, y) {
      return {
        x: originX + x * cell + cell * 0.5,
        y: originY + (rows - 1 - y) * cell + cell * 0.5,
      };
    },
  };

  const { state, packetEvents, chipEvents, fpgaEvent } = tickData();

  drawFpga(layout, fpgaEvent);

  for (let gy = rows - 1; gy >= 0; gy -= 1) {
    for (let gx = 0; gx < cols; gx += 1) {
      const chip = state.get(`${gx},${gy}`) || { x: gx, y: gy, chip_id: 1, up_mask: 0, down_mask: 0 };
      const { x: cx, y: cy } = layout.cellCenter(gx, gy);
      const left = cx - cell * 0.42;
      const top = cy - cell * 0.42;
      const isSelected = selectedChip && selectedChip.x === gx && selectedChip.y === gy;

      const activeUpdate = chipEvents.find((update) => update.x === gx && update.y === gy);
      ctx.fillStyle = activeUpdate ? '#1c2f25' : (isSelected ? '#172131' : '#111722');
      ctx.strokeStyle = activeUpdate ? '#7cff7c' : (isSelected ? '#d8f3ff' : '#2c3748');
      ctx.lineWidth = isSelected ? 2.5 : 1.5;
      ctx.beginPath();
      ctx.roundRect(left, top, cell * 0.84, cell * 0.84, 10);
      ctx.fill();
      ctx.stroke();

      for (const edge of ['north', 'east', 'south', 'west']) {
        drawLane(cx, cy, cell, edge, '#394455', false);
      }
      for (const edge of ['north', 'east', 'south', 'west']) {
        if (laneEnabled(chip.up_mask || 0, edge)) drawLane(cx, cy, cell, edge, '#4db0ff', false);
        if (laneEnabled(chip.down_mask || 0, edge)) drawLane(cx, cy, cell, edge, '#ffb04d', false);
      }

      ctx.fillStyle = '#eef4ff';
      ctx.font = `${Math.max(13, cell * 0.16)}px ui-monospace, monospace`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(String(chip.chip_id), left + 8, top + 6);
      ctx.textBaseline = 'alphabetic';
    }
  }

  for (const event of packetEvents || []) {
    if (event.type === 'packet_move') {
      drawPacket(event, layout);
      const src = layout.cellCenter(event.src[0], event.src[1]);
      const dst = layout.cellCenter(event.dst[0], event.dst[1]);
      ctx.strokeStyle = 'rgba(124,255,124,0.20)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(src.x, src.y);
      ctx.lineTo(dst.x, dst.y);
      ctx.stroke();
    }
  }

  updateHud();
}

function setTick(index) {
  if (!playback) return;
  currentTickIndex = Math.max(0, Math.min(index, playback.total_ticks || 0));
  scrubber.value = String(currentTickIndex);
  draw();
}

function togglePlay() {
  isPlaying = !isPlaying;
  playPauseBtn.textContent = isPlaying ? 'Pause' : 'Play';
}

function step(delta) {
  if (!playback) return;
  setTick(currentTickIndex + delta);
}

function handleCanvasClick(event) {
  if (!playback) return;
  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const rows = playback.rows;
  const cols = playback.cols;
  const marginLeft = 360;
  const margin = 30;
  const availW = Math.max(200, window.innerWidth - marginLeft - margin);
  const availH = Math.max(200, window.innerHeight - margin * 2);
  const cell = Math.min(availW / cols, availH / rows);
  const gridW = cell * cols;
  const gridH = cell * rows;
  const originX = marginLeft + (availW - gridW) * 0.5;
  const originY = margin + (availH - gridH) * 0.5;
  if (x < originX || x > originX + gridW || y < originY || y > originY + gridH) {
    selectedChip = null;
    draw();
    return;
  }
  const gx = Math.floor((x - originX) / cell);
  const gyFromTop = Math.floor((y - originY) / cell);
  const gy = rows - 1 - gyFromTop;
  selectedChip = { x: gx, y: gy };
  draw();
}

async function loadPlaybackFromObject(obj) {
  playback = obj;
  currentTickIndex = 0;
  selectedChip = null;
  scrubber.max = String(Math.max(0, playback.total_ticks || 0));
  scrubber.value = '0';
  draw();
}

async function loadPlaybackFromUrl(url) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`failed to load ${url}`);
  const obj = await response.json();
  await loadPlaybackFromObject(obj);
}

playPauseBtn.addEventListener('click', togglePlay);
stepBackBtn.addEventListener('click', () => step(-1));
stepForwardBtn.addEventListener('click', () => step(1));
resetBtn.addEventListener('click', () => setTick(0));
scrubber.addEventListener('input', () => setTick(Number(scrubber.value)));
canvas.addEventListener('click', handleCanvasClick);
fileInput.addEventListener('change', async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  const text = await file.text();
  await loadPlaybackFromObject(JSON.parse(text));
});

window.addEventListener('keydown', (event) => {
  if (event.code === 'Space') {
    event.preventDefault();
    togglePlay();
  } else if (event.key === 's' || event.key === 'S') {
    step(1);
  } else if (event.key === 'z' || event.key === 'Z') {
    step(-1);
  } else if (event.key === 'r' || event.key === 'R') {
    setTick(0);
  }
});

function animate(ts) {
  if (!lastFrameMs) lastFrameMs = ts;
  const dt = ts - lastFrameMs;
  lastFrameMs = ts;
  if (isPlaying && playback) {
    accumulator += dt;
    const interval = 1000 / Number(speedInput.value || 6);
    while (accumulator >= interval) {
      accumulator -= interval;
      if (currentTickIndex >= (playback.total_ticks || 0)) {
        isPlaying = false;
        playPauseBtn.textContent = 'Play';
        break;
      }
      setTick(currentTickIndex + 1);
    }
  }
  requestAnimationFrame(animate);
}

resize();
loadPlaybackFromUrl('./data/live_bootstrap_3x5.json').catch((error) => {
  scenarioEl.textContent = `Scenario: failed to load sample`;
  selectionEl.textContent = error.message;
});
requestAnimationFrame(animate);
