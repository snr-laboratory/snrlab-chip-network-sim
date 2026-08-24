const canvas = document.getElementById('board');
const ctx = canvas.getContext('2d');

const playPauseBtn = document.getElementById('playPause');
const stepBackBtn = document.getElementById('stepBack');
const stepForwardBtn = document.getElementById('stepForward');
const resetBtn = document.getElementById('reset');
const showInstructionsBtn = document.getElementById('showInstructions');
const showRunMetricsBtn = document.getElementById('showRunMetrics');
const showNetworkViewBtn = document.getElementById('showNetworkView');
const showChipViewBtn = document.getElementById('showChipView');
const chipZoomOutBtn = document.getElementById('chipZoomOut');
const chipZoomInBtn = document.getElementById('chipZoomIn');
const timelineSpanOutBtn = document.getElementById('timelineSpanOut');
const timelineSpanInBtn = document.getElementById('timelineSpanIn');
const timelineSpanStatusEl = document.getElementById('timelineSpanStatus');
const laneOrderControlsEl = document.getElementById('laneOrderControls');
const laneOrderStatusEl = document.getElementById('laneOrderStatus');
const laneNorthUpBtn = document.getElementById('laneNorthUp');
const laneNorthDownBtn = document.getElementById('laneNorthDown');
const laneWestUpBtn = document.getElementById('laneWestUp');
const laneWestDownBtn = document.getElementById('laneWestDown');
const laneEastUpBtn = document.getElementById('laneEastUp');
const laneEastDownBtn = document.getElementById('laneEastDown');
const speedInput = document.getElementById('speed');
const scrubber = document.getElementById('scrubber');
const fileInput = document.getElementById('fileInput');
const scenarioEl = document.getElementById('scenario');
const rtlVersionEl = document.getElementById('rtlVersion');
const statusEl = document.getElementById('status');
const selectionEl = document.getElementById('selection');
const fpgaPopupEl = document.getElementById('fpgaPopup');
const fpgaPopupTitleEl = document.getElementById('fpgaPopupTitle');
const fpgaPopupBodyEl = document.getElementById('fpgaPopupBody');
const fpgaPopupCloseEl = document.getElementById('fpgaPopupClose');
const instructionsPopupEl = document.getElementById('instructionsPopup');
const instructionsPopupCloseEl = document.getElementById('instructionsPopupClose');
const runMetricsPopupEl = document.getElementById('runMetricsPopup');
const runMetricsPopupBodyEl = document.getElementById('runMetricsPopupBody');
const runMetricsPopupCloseEl = document.getElementById('runMetricsPopupClose');
const hudEl = document.getElementById('hud');
const hudResizeHandleEl = document.getElementById('hudResizeHandle');
const dataPacketMetricsSummaryEl = document.getElementById('dataPacketMetricsSummary');
const dataPacketMetricsListEl = document.getElementById('dataPacketMetricsList');
const filterConfigWriteEl = document.getElementById('filterConfigWrite');
const filterConfigReadEl = document.getElementById('filterConfigRead');
const filterEventDataEl = document.getElementById('filterEventData');
const filterMsgPacketEl = document.getElementById('filterMsgPacket');
const filterOtherPacketEl = document.getElementById('filterOtherPacket');
const filterSharedFifoEl = document.getElementById('filterSharedFifo');
const filterPacketLabelsEl = document.getElementById('filterPacketLabels');
const filterPersistentInjectionEl = document.getElementById('filterPersistentInjection');

const PISO_EDGE_TO_BIT = { north: 3, east: 2, south: 1, west: 0 };
const POSI_EDGE_TO_BIT = { north: 0, east: 3, south: 2, west: 1 };

const THEME = Object.freeze({
  canvas: '#f4f7fb',
  surface: '#ffffff',
  surfaceMuted: '#f7f9fc',
  text: '#182235',
  mutedText: '#5f6b7a',
  subtleText: '#6b7280',
  border: '#9aa8ba',
  grid: 'rgba(100, 116, 139, 0.22)',
  gridStrong: 'rgba(100, 116, 139, 0.36)',
  inactive: 'rgba(100, 116, 139, 0.55)',
  selected: '#1261a6',
});

const LIGHT_SIGNAL_COLORS = Object.freeze({
  '#ffffff': '#1f2937',
  '#f0f5ff': '#182235',
  '#f0e6ff': '#51306f',
  '#eef4ff': '#182235',
  '#edf3ff': '#182235',
  '#e8edf8': '#243044',
  '#e6ecf8': '#243044',
  '#d9dde7': '#344054',
  '#d7a6ff': '#7b3fb2',
  '#cdb4ff': '#7650a2',
  '#c9d2e3': '#4b5563',
  '#c3cce0': '#344054',
  '#b9c6d8': '#596579',
  '#b8c1d4': '#536174',
  '#b7c0d3': '#5b6474',
  '#b46cff': '#7b3fb2',
  '#aeb8ca': '#5f6b7a',
  '#a8b2c6': '#657184',
  '#9fb6ff': '#355ea8',
  '#9eabc2': '#64748b',
  '#8fd0ff': '#176b9c',
  '#7ee0a1': '#237a45',
  '#7cff7c': '#16803c',
  '#6fd3ff': '#0077a8',
  '#61e294': '#16805a',
  '#4db0ff': '#1677b8',
  '#ffcf4d': '#9a6a00',
  '#f2d06b': '#927000',
  '#ffb04d': '#c56a00',
  '#ff9f43': '#b85d00',
  '#d7f06a': '#708000',
  '#d784ff': '#8a3dac',
  '#ff8fb0': '#b8326a',
  '#ff8f8f': '#b83a48',
  '#ff7a7a': '#c73545',
  '#ff5e87': '#c8325c',
});

function themeColor(color) {
  if (typeof color !== 'string') return color;
  return LIGHT_SIGNAL_COLORS[color.toLowerCase()] || color;
}

let playback = null;
let playbackSourceUrl = null;
let chipDebugData = null;
let chipDebugAuxData = null;
let currentView = 'network';
let isPlaying = false;
let currentTickIndex = 0;
let selectedTarget = null;
let lastFrameMs = 0;
let accumulator = 0;
let hudResizeState = null;
let chipViewZoom = 1;
let chipTimelineSpanScale = 1;
let chipLaneTimelineOrder = ['north', 'west', 'east'];

const HUD_MIN_WIDTH = 260;
const HUD_MAX_WIDTH = 640;
const HUD_STORAGE_KEY = 'larpix-playback-hud-width';

function clampHudWidth(width) {
  const viewportMax = Math.max(HUD_MIN_WIDTH, Math.min(HUD_MAX_WIDTH, Math.floor(window.innerWidth * 0.7)));
  return Math.max(HUD_MIN_WIDTH, Math.min(viewportMax, Math.round(width)));
}

function applyHudWidth(width) {
  const clamped = clampHudWidth(width);
  document.body.style.setProperty('--hud-width', `${clamped}px`);
  return clamped;
}

function loadHudWidth() {
  const raw = window.localStorage?.getItem(HUD_STORAGE_KEY);
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 320;
}

function persistHudWidth(width) {
  try {
    window.localStorage?.setItem(HUD_STORAGE_KEY, String(width));
  } catch (_) {}
}

function startHudResize(clientX) {
  hudResizeState = {
    startX: clientX,
    startWidth: hudEl?.getBoundingClientRect().width || loadHudWidth(),
  };
  document.body.classList.add('hud-resizing');
}

function updateHudResize(clientX) {
  if (!hudResizeState) return;
  const nextWidth = hudResizeState.startWidth + (clientX - hudResizeState.startX);
  const applied = applyHudWidth(nextWidth);
  persistHudWidth(applied);
  resize();
}

function stopHudResize() {
  if (!hudResizeState) return;
  hudResizeState = null;
  document.body.classList.remove('hud-resizing');
}


function buildSharedFifoIndex(obj) {
  const byChip = new Map();
  for (const update of obj.shared_fifo_updates || []) {
    const key = `${update.x},${update.y}`;
    const list = byChip.get(key) || [];
    list.push(update);
    byChip.set(key, list);
  }
  obj._sharedFifoByChip = byChip;
}

function sharedFifoUpdatesForChip(x, y) {
  return playback?._sharedFifoByChip?.get(`${x},${y}`) || [];
}

function sharedFifoOccupancyAt(x, y, tick) {
  const updates = sharedFifoUpdatesForChip(x, y);
  let lo = 0;
  let hi = updates.length - 1;
  let best = -1;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    if ((updates[mid].tick ?? 0) <= tick) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best >= 0 ? Number(updates[best].shared_fifo_occupancy || 0) : 0;
}

function sharedFifoVisible() {
  return Boolean(filterSharedFifoEl?.checked);
}

function packetLabelsVisible() {
  return Boolean(filterPacketLabelsEl?.checked);
}

function persistentInjectionVisible() {
  return Boolean(filterPersistentInjectionEl?.checked);
}

function buildPersistentInjectionIndex(obj) {
  const firstByChip = new Map();
  for (const event of obj.chip_events || []) {
    if (event?.event !== 'charge_injected') continue;
    const key = `${event.x},${event.y}`;
    const tick = Number(event.tick || 0);
    const prev = firstByChip.get(key);
    if (prev === undefined || tick < prev) firstByChip.set(key, tick);
  }
  obj._persistentInjectionStartByChip = firstByChip;
}

function persistentInjectionStartTick(x, y) {
  return playback?._persistentInjectionStartByChip?.get(`${x},${y}`);
}

function chipHasPersistentInjectionAt(x, y, tick) {
  const start = persistentInjectionStartTick(x, y);
  return start !== undefined && tick >= start;
}

function chipViewCanvasHeight() {
  return Math.max(window.innerHeight, 1580);
}

function chipViewCanvasWidth() {
  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  return Math.max(window.innerWidth, Math.ceil(hudWidth + 1560));
}

function updateTimelineSpanStatus() {
  if (!timelineSpanStatusEl) return;
  timelineSpanStatusEl.textContent = `Timeline span: ${chipTimelineSpanScale.toFixed(1)}x`;
}

function updateChipViewHudControls() {
  if (!laneOrderControlsEl) return;
  laneOrderControlsEl.hidden = currentView !== 'chip'
    || chipDebugData?.kind === 'chip1_south_tx_only'
    || chipDebugData?.kind === 'chip1_south_tx_chip0_north_rx_focus'
    || chipDebugData?.kind === 'chip0_north_tx_chip1_south_rx_focus';
}

function updateLaneOrderStatus() {
  if (!laneOrderStatusEl) return;
  laneOrderStatusEl.textContent = `Top to bottom: ${chipLaneTimelineOrder.join(', ')}`;
}

function moveLaneTimeline(lane, delta) {
  const currentIndex = chipLaneTimelineOrder.indexOf(lane);
  if (currentIndex < 0) return;
  const nextIndex = Math.max(0, Math.min(chipLaneTimelineOrder.length - 1, currentIndex + delta));
  if (nextIndex === currentIndex) return;
  chipLaneTimelineOrder.splice(currentIndex, 1);
  chipLaneTimelineOrder.splice(nextIndex, 0, lane);
  updateLaneOrderStatus();
  draw();
}

function applyViewScrollMode() {
  const chipMode = currentView === 'chip';
  document.documentElement.style.overflowY = chipMode ? 'auto' : 'hidden';
  document.body.style.overflowY = chipMode ? 'auto' : 'hidden';
  document.documentElement.style.overflowX = chipMode ? 'auto' : 'hidden';
  document.body.style.overflowX = chipMode ? 'auto' : 'hidden';
}

function resize() {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const cssWidth = currentView === 'chip' ? chipViewCanvasWidth() : window.innerWidth;
  const cssHeight = currentView === 'chip' ? chipViewCanvasHeight() : window.innerHeight;
  canvas.width = Math.floor(cssWidth * dpr);
  canvas.height = Math.floor(cssHeight * dpr);
  canvas.style.width = `${cssWidth}px`;
  canvas.style.height = `${cssHeight}px`;
  applyViewScrollMode();
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  draw();
}

window.addEventListener('resize', resize);
window.addEventListener('pointermove', (event) => {
  if (!hudResizeState) return;
  updateHudResize(event.clientX);
});

window.addEventListener('pointerup', stopHudResize);
window.addEventListener('pointercancel', stopHudResize);


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
  if (!playback) return { state: null, packetEvents: [], chipEvents: [], chargeEvents: [], fpgaTxEvents: [], fpgaRxEvents: [] };
  const clamped = Math.max(0, Math.min(currentTickIndex, playback.total_ticks || 0));
  const packetEvents = (playback.packet_spans || []).filter((span) => span.start_tick <= clamped && clamped < span.end_tick);
  const chipEvents = (playback.chip_updates || []).filter((update) => (update.tick ?? 0) === clamped);
  const chargeEvents = (playback.chip_events || []).filter((event) => (event.tick ?? 0) === clamped);
  const fpgaActive = (playback.fpga_events || []).filter((event) => event.start_tick <= clamped && clamped < event.end_tick);
  return {
    state: buildStateAt(clamped),
    packetEvents,
    chipEvents,
    chargeEvents,
    fpgaTxEvents: fpgaActive.filter((event) => event.direction === 'tx'),
    fpgaRxEvents: fpgaActive.filter((event) => event.direction === 'rx'),
  };
}

function packetCategory(packetType) {
  if (packetType === 'config_write') return 'config_write';
  if (packetType === 'config_read_request' || packetType === 'config_read_reply') return 'config_read';
  if (packetType === 'event_data') return 'event_data';
  if (packetType === 'msg_packet') return 'msg_packet';
  return 'other';
}

function packetColor(packetType) {
  const category = packetCategory(packetType);
  return {
    config_write: '#16803c',
    config_read: '#1677b8',
    event_data: '#c8325c',
    msg_packet: '#9a6a00',
    other: '#708000',
  }[category] || '#708000';
}

function packetCategoryVisible(packetType) {
  const category = packetCategory(packetType);
  if (category === 'config_write') return Boolean(filterConfigWriteEl?.checked);
  if (category === 'config_read') return Boolean(filterConfigReadEl?.checked);
  if (category === 'event_data') return Boolean(filterEventDataEl?.checked);
  if (category === 'msg_packet') return Boolean(filterMsgPacketEl?.checked);
  return Boolean(filterOtherPacketEl?.checked);
}

function summarizeChannels(channels) {
  const list = (channels || []).map((value) => Number(value));
  if (list.length <= 8) return list.join(',');
  return `${list.slice(0, 8).join(',')} +${list.length - 8} more`;
}

function formatDeliveryPercent(received, generated) {
  if (!(generated > 0)) return 'n/a';
  return `${received}/${generated} = ${(100 * received / generated).toFixed(1)}%`;
}

function playbackUsesFullMsgOp(obj = playback) {
  const rtl = String(obj?.rtl_version || obj?.run_summary?.rtl_version || '').toLowerCase();
  if (rtl.includes('v3n1')) return true;
  return false;
}

function inferRtlVersion(playbackObj, sourceUrl) {
  const explicit = playbackObj?.rtl_version || playbackObj?.run_summary?.rtl_version;
  if (typeof explicit === 'string' && explicit.trim()) return explicit.trim();
  const haystacks = [
    sourceUrl,
    playbackObj?.name,
    playbackObj?.chip_internal_debug?.csv_url,
  ]
    .filter((value) => typeof value === 'string' && value.length > 0)
    .map((value) => value.toLowerCase());
  for (const text of haystacks) {
    if (text.includes('v3n1')) return 'v3n1';
    if (text.includes('v3c')) return 'v3c';
    if (text.includes('v3b2') || text.includes('chip_larpix_v2') || text.includes('_v2') || text.includes('v2 alternate rtl')) return 'v3b2';
  }
  if (typeof sourceUrl === 'string' && sourceUrl.length > 0) return 'v3b';
  return 'unknown';
}

function populateDataPacketMetrics() {
  if (!dataPacketMetricsSummaryEl || !dataPacketMetricsListEl) return;
  if (!playback?.data_packet_metrics) {
    dataPacketMetricsSummaryEl.textContent = 'Data packets: n/a';
    dataPacketMetricsListEl.innerHTML = '<div class="metrics-row metrics-empty">No data packet metrics in playback.</div>' ;
    return;
  }
  const metrics = playback.data_packet_metrics;
  const totalGenerated = Number(metrics.total_generated || 0);
  const totalReceived = Number(metrics.total_received_at_fpga || 0);
  const totalArrivals = Number(metrics.total_arrivals_at_fpga || 0);
  dataPacketMetricsSummaryEl.textContent = `Totals: gen ${totalGenerated} | FPGA unique ${totalReceived} | FPGA arrivals ${totalArrivals} | delivery ${formatDeliveryPercent(totalReceived, totalGenerated)}`;
  const entries = Array.isArray(metrics.generated_by_chip) ? metrics.generated_by_chip : [];
  if (entries.length === 0) {
    dataPacketMetricsListEl.innerHTML = '<div class="metrics-row metrics-empty">No chip-level data packets recorded.</div>' ;
    return;
  }
  dataPacketMetricsListEl.innerHTML = '';
  let visibleEntries = 0;
  for (const entry of entries) {
    const chipId = Number(entry.chip_id || 0);
    const generated = Number(entry.generated_count || 0);
    const received = Number(entry.received_at_fpga_count || 0);
    const arrivals = Number(entry.total_arrivals_at_fpga_count || 0);
    if (generated <= 0) continue;
    visibleEntries += 1;
    const row = document.createElement('div');
    row.className = 'metrics-row';
    row.textContent = `chip ${chipId}: gen=${generated} | FPGA unique ${received} | FPGA arrivals ${arrivals}`;
    dataPacketMetricsListEl.appendChild(row);
  }
  if (visibleEntries === 0) {
    dataPacketMetricsListEl.innerHTML = '<div class="metrics-row metrics-empty">No chip-level generated data packets recorded.</div>';
  }
}

function renderRunMetricsPopup(summary) {
  if (!runMetricsPopupEl || !runMetricsPopupBodyEl) return;
  if (runMetricsPopupEl.classList.contains('hidden')) return;
  if (!summary) {
    runMetricsPopupBodyEl.innerHTML = '<div class="fpga-card"><div class="fpga-empty">No run metrics in this playback.</div></div>';
    return;
  }
  const ticksPerSec = Number(summary.ticks_per_sec || 0);
  const runtimeSec = Number(summary.runtime_sec || 0);
  runMetricsPopupBodyEl.innerHTML = `
    <div class="fpga-card">
      <div class="fpga-card-title">Performance</div>
      <div class="fpga-label">ticks/sec: ${ticksPerSec > 0 ? ticksPerSec.toFixed(1) : 'n/a'}</div>
      <div class="fpga-label">total runtime: ${runtimeSec > 0 ? runtimeSec.toFixed(2) + ' sec' : 'n/a'}</div>
    </div>`;
}

function fpgaFrameBit(event, tick) {
  if (!event) return null;
  const offset = tick - Number(event?.start_tick || 0);
  const frameLength = Math.max(0, Number(event?.end_tick || 0) - Number(event?.start_tick || 0));
  if (offset < 0 || offset >= frameLength) return null;
  if (offset === 0) return 0;
  if (offset === frameLength - 1) return 1;
  const packetWord = BigInt(event.packet_word);
  const bitIndex = BigInt(offset - 1);
  return Number((packetWord >> bitIndex) & 1n);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}

function renderFpgaPopup(fpgaTxEvents, fpgaRxEvents) {
  if (!fpgaPopupEl || !fpgaPopupBodyEl || !fpgaPopupTitleEl) return;
  if (!playback || selectedTarget?.type !== 'fpga') {
    fpgaPopupEl.classList.add('hidden');
    fpgaPopupBodyEl.innerHTML = '';
    return;
  }
  fpgaPopupEl.classList.remove('hidden');
  fpgaPopupTitleEl.textContent = `FPGA at tick ${currentTickIndex}`;
  const sections = [];
  const eventGroups = [
    ['TX', fpgaTxEvents],
    ['RX', fpgaRxEvents],
  ];
  for (const [directionLabel, events] of eventGroups) {
    if (!events.length) {
      sections.push(`<div class="fpga-card"><div class="fpga-card-title">${directionLabel}</div><div class="fpga-empty">Idle on this tick.</div></div>`);
      continue;
    }
    for (const event of events) {
      const bit = fpgaFrameBit(event, currentTickIndex);
      const decode = event.decode || {};
      const decoded = decode.decoded || {};
      sections.push(`
        <div class="fpga-card">
          <div class="fpga-card-title">${directionLabel} ${escapeHtml(event.packet_type || 'packet')}</div>
          <div class="fpga-meta">bit on this tick: ${bit === null ? 'n/a' : bit} | frame ticks ${event.start_tick}..${Math.max(event.start_tick, (event.end_tick || 0) - 1)} | complete @ ${event.complete_tick}</div>
          <div class="fpga-label">${escapeHtml(event.label || '')}</div>
          <div class="fpga-word">word: ${escapeHtml(event.packet_word || '')}</div>
          <pre class="fpga-json">${escapeHtml(formatPacketDecode(decoded, event.packet_type || '', playback))}</pre>
        </div>`);
    }
  }
  fpgaPopupBodyEl.innerHTML = sections.join('');
}

function updateHud() {
  if (!playback) {
    scenarioEl.textContent = 'Scenario: none';
    rtlVersionEl.textContent = 'RTL: none';
    statusEl.textContent = 'Tick: 0 / 0';
    if (dataPacketMetricsSummaryEl) dataPacketMetricsSummaryEl.textContent = 'Data packets: n/a';
    if (dataPacketMetricsListEl) dataPacketMetricsListEl.innerHTML = '';
    selectionEl.textContent = 'Selection: none';
    renderFpgaPopup([], []);
    updateViewButtons();
    return;
  }
  scenarioEl.textContent = `Scenario: ${playback.name || 'unnamed'}`;
  rtlVersionEl.textContent = `RTL: ${inferRtlVersion(playback, playbackSourceUrl)}`;
  renderRunMetricsPopup(playback.run_summary);
  updateViewButtons();
  const { state, chipEvents, chargeEvents, fpgaTxEvents, fpgaRxEvents } = tickData();
  const parts = [`Tick: ${currentTickIndex} / ${Math.max(0, playback.total_ticks || 0)}`, `View: ${currentView === 'chip' ? chipDebugLabel() : 'Network'}`];
  if (chipEvents.length > 0) parts.push(`chip updates: ${chipEvents.length}`);
  if (chargeEvents.length > 0) parts.push(`charge injections: ${chargeEvents.length}`);
  statusEl.textContent = parts.join(' | ');
  if (currentView === 'chip') {
    renderFpgaPopup([], []);
    if (chipDebugData?.kind === 'chip1_south_tx_only') {
      const row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
      if (!row) {
        selectionEl.textContent = `Selection: ${chipDebugLabel()} | no debug sample for this tick`;
        return;
      }
      selectionEl.textContent =
        `Selection: chip ${chipDebugData.monitorChipId} south TX`
        + ` | hydra ${Number(row.south_select_hydra ?? 0)}`
        + ` | nifty ${Number(row.south_select_nifty ?? 0)}`
        + ` | final_ld ${Number(row.south_final_ld_tx ?? 0)}`
        + ` | raw_busy ${Number(row.south_raw_tx_busy ?? 0)}`
        + ` | override ${Number(row.south_msg_override ?? 0)}`;
      return;
    }
    if (chipDebugData?.kind === 'chip1_south_tx_chip0_north_rx_focus') {
      const chip1Row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
      const chip0Row = chipDebugRowAtTickFrom(chipDebugAuxData, currentTickIndex);
      if (!chip1Row || !chip0Row) {
        selectionEl.textContent = `Selection: ${chipDebugLabel()} | no debug sample for this tick`;
        return;
      }
      selectionEl.textContent =
        `Selection: chip ${chipDebugData.monitorChipId} south TX bit ${Number(chip1Row.south_tx_bit ?? 1)} valid ${Number(chip1Row.south_tx_bit_valid ?? 0)}`
        + ` | chip ${chipDebugAuxData?.monitorChipId ?? 0} north RX bit ${Number(chip0Row.north_rx_in_bit ?? 1)} sync ${Number(chip0Row.north_rx_sync ?? 1)} busy ${Number(chip0Row.north_busy ?? 0)}`;
      return;
    }
    if (chipDebugData?.kind === 'chip0_north_tx_chip1_south_rx_focus') {
      const chip0Row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
      const chip1Row = chipDebugRowAtTickFrom(chipDebugAuxData, currentTickIndex);
      if (!chip0Row || !chip1Row) {
        selectionEl.textContent = `Selection: ${chipDebugLabel()} | no debug sample for this tick`;
        return;
      }
      selectionEl.textContent =
        `Selection: chip ${chipDebugData.monitorChipId} north TX bit ${Number(chip0Row.north_tx_bit ?? 1)} valid ${Number(chip0Row.north_tx_bit_valid ?? 0)}`
        + ` | chip ${chipDebugAuxData?.monitorChipId ?? 0} south RX bit ${Number(chip1Row.south_rx_in_bit ?? 1)} sync ${Number(chip1Row.south_rx_sync ?? 1)} busy ${Number(chip1Row.south_busy ?? 0)}`;
      return;
    }
    const row = chipDebugRowAtTick(currentTickIndex);
    if (!chipDebugData) {
      selectionEl.textContent = 'Selection: chip internals unavailable for this playback';
      return;
    }
    if (!row) {
      selectionEl.textContent = `Selection: ${chipDebugLabel()} | no debug sample for this tick`;
      return;
    }
    const sel = laneNamesFromMask(row.hydra_sel_onehot, POSI_EDGE_TO_BIT).join(',') || 'none';
    const unload = laneNamesFromMask(row.hydra_uld_rx_data_uart, POSI_EDGE_TO_BIT).join(',') || 'none';
    selectionEl.textContent = `Selection: ${chipDebugLabel()} | Hydra ${hydraStateName(row.hydra_state)} -> ${hydraStateName(row.hydra_next_state)} | select ${sel} | unload ${unload} | rx_data ${abbreviateWord(row.hydra_rx_data_word)}`;
    return;
  }
  if (selectedTarget?.type === 'fpga') {
    const txBit = fpgaTxEvents.length > 0 ? fpgaFrameBit(fpgaTxEvents[0], currentTickIndex) : null;
    const rxBit = fpgaRxEvents.length > 0 ? fpgaFrameBit(fpgaRxEvents[0], currentTickIndex) : null;
    selectionEl.textContent = `Selection: FPGA | TX bit ${txBit === null ? 'idle' : txBit} | RX bit ${rxBit === null ? 'idle' : rxBit} | TX packets ${fpgaTxEvents.length} | RX packets ${fpgaRxEvents.length}`;
    renderFpgaPopup(fpgaTxEvents, fpgaRxEvents);
    return;
  }
  renderFpgaPopup(fpgaTxEvents, fpgaRxEvents);
  if (selectedTarget?.type === 'chip') {
    const chip = state?.get(`${selectedTarget.x},${selectedTarget.y}`);
    if (chip) {
      const activeUpdate = chipEvents.find((update) => update.x === selectedTarget.x && update.y === selectedTarget.y);
      const activeCharge = chargeEvents.find((event) => event.x === selectedTarget.x && event.y === selectedTarget.y);
      let line = `Selection: chip ${chip.chip_id} at (${chip.x},${chip.y}) U${(chip.up_mask || 0).toString(2).padStart(4, '0')} D${(chip.down_mask || 0).toString(2).padStart(4, '0')}`;
      line += ` | FIFO ${sharedFifoOccupancyAt(selectedTarget.x, selectedTarget.y, currentTickIndex)}`;
      if (activeUpdate) {
        line += ` | applied reg ${activeUpdate.register_addr} = 0x${Number(activeUpdate.register_data || 0).toString(16).toUpperCase().padStart(2, '0')}`;
      }
      if (activeCharge) {
        line += ` | charge ch ${summarizeChannels(activeCharge.channels)} (${activeCharge.channel_count} total)`;
      }
      selectionEl.textContent = line;
      return;
    }
  }
  if (chargeEvents.length > 0) {
    const event = chargeEvents[0];
    selectionEl.textContent = `Selection: charge injected at chip (${event.x},${event.y}) channels ${summarizeChannels(event.channels)} (${event.channel_count} total)`;
    return;
  }
  if (chipEvents.length > 0) {
    const update = chipEvents[0];
    selectionEl.textContent = `Selection: config applied at chip (${update.x},${update.y}) reg ${update.register_addr} = 0x${Number(update.register_data || 0).toString(16).toUpperCase().padStart(2, '0')}`;
    return;
  }
  selectionEl.textContent = 'Selection: none';
}

function laneEnabled(mask, edge) {
  return ((mask >> PISO_EDGE_TO_BIT[edge]) & 1) === 1;
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

function isPacketMotionEvent(event) {
  return Array.isArray(event?.src) && event.src.length === 2 && Array.isArray(event?.dst) && event.dst.length === 2;
}

function drawPacket(event, layout) {
  const src = layout.cellCenter(event.src[0], event.src[1]);
  const dst = layout.cellCenter(event.dst[0], event.dst[1]);
  const duration = Math.max(1, (event.end_tick || 0) - (event.start_tick || 0));
  const t = Math.max(0, Math.min(1, (currentTickIndex - (event.start_tick || 0)) / duration));
  const x = src.x + (dst.x - src.x) * t;
  const y = src.y + (dst.y - src.y) * t;
  const color = packetColor(event.packet_type);
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, Math.max(5, layout.cell * 0.1), 0, Math.PI * 2);
  ctx.fill();
  if (packetLabelsVisible() && event.label) {
    ctx.fillStyle = THEME.text;
    ctx.font = '11px ui-monospace, monospace';
    ctx.fillText(event.label, x + 10, y - 10);
  }
}

const SOURCE_FPGA_LANE_COLOR = '#7b3fb2';
const SOURCE_FPGA_LANE_INACTIVE_COLOR = '#9f86b7';
const SHARED_FIFO_TEXT_COLOR = '#7b3fb2';
const HYDRA_STATE_NAMES = {
  0: 'IDLE',
  1: 'RX_CAPTURE',
  2: 'RX_PROCESS',
  3: 'TX_UPSTREAM',
  4: 'TX_GET_FIFO',
  5: 'TX_SEND',
  6: 'TX_WAIT_FIFO',
};

const COMMS_STATE_NAMES = {
  0: 'IDLE',
  1: 'WRITE_CFG',
  2: 'READ_REQ',
  3: 'LOAD_FIFO',
};

function parseChipDebugValue(raw) {
  if (/^0x[0-9a-fA-F]+$/.test(raw)) return raw;
  if (/^-?\d+$/.test(raw)) return Number(raw);
  return raw;
}

function parseChipDebugCsv(text) {
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  if (lines.length < 2) return null;
  const headers = lines[0].split(',');
  const rows = [];
  const rowsByTick = new Map();
  const ticks = [];
  for (const line of lines.slice(1)) {
    const parts = line.split(',');
    if (parts.length < 1) continue;
    while (parts.length < headers.length) parts.push('');
    if (parts.length > headers.length) parts.length = headers.length;
    const row = {};
    const raw = {};
    for (let i = 0; i < headers.length; i += 1) {
      raw[headers[i]] = parts[i];
      row[headers[i]] = parseChipDebugValue(parts[i]);
    }
    row.__raw = raw;
    rows.push(row);
    const tick = Number(row.tick || 0);
    rowsByTick.set(tick, row);
    ticks.push(tick);
  }
  return { headers, rows, rowsByTick, ticks };
}

function parseChipDebugSidecar(obj) {
  if (!obj || !Array.isArray(obj.rows)) return null;
  const rowsByTick = new Map();
  const ticks = [];
  for (const row of obj.rows) {
    const tick = Number(row.tick || 0);
    rowsByTick.set(tick, row);
    ticks.push(tick);
  }
  return {
    ...obj,
    rowsByTick,
    ticks,
    mode: obj.kind || 'sidecar',
  };
}

function parseMaskValue(value) {
  if (typeof value === 'number') return value;
  if (typeof value === 'string' && value.startsWith('0x')) return Number.parseInt(value, 16);
  return Number(value || 0) || 0;
}

function maskHasLane(mask, lane) {
  return ((parseMaskValue(mask) >> lane) & 1) === 1;
}

function laneNamesFromMask(mask, edgeToBit = POSI_EDGE_TO_BIT) {
  const names = [];
  for (const [name, bit] of Object.entries(edgeToBit)) {
    if (maskHasLane(mask, bit)) names.push(name);
  }
  return names;
}

function hydraStateName(value) {
  return HYDRA_STATE_NAMES[Number(value)] || `STATE_${value}`;
}

function chipDebugLabel() {
  return chipDebugData?.label || `Chip ${chipDebugData?.monitorChipId ?? 0} View`;
}

function chipDebugSignalSpecs(data) {
  if (!data) return null;
  const specs = Array.isArray(data.signalSpecs) ? data.signalSpecs : Array.isArray(data.signal_specs) ? data.signal_specs : null;
  if (!specs) return null;
  return specs.map((spec) => ({
    key: String(spec.key || ''),
    label: String(spec.label || spec.key || ''),
    kind: String(spec.kind || 'binary'),
    color: String(spec.color || '#ffffff'),
    maxValue: Number(spec.maxValue ?? spec.max_value ?? 1),
    value: (row) => {
      const raw = row?.[spec.key];
      if (raw === undefined || raw === null || raw === '') return 0;
      return raw;
    },
  }));
}

function chipDebugRowAtTickFrom(data, tick) {
  if (!data) return null;
  const target = Number(tick || 0);
  const direct = data.rowsByTick?.get(target);
  if (direct) return direct;
  const ticks = data.ticks || [];
  const rows = data.rows || [];
  let lo = 0;
  let hi = ticks.length - 1;
  let best = -1;
  while (lo <= hi) {
    const mid = Math.floor((lo + hi) / 2);
    if (ticks[mid] <= target) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (best >= 0) {
    const byTick = data.rowsByTick?.get(ticks[best]);
    if (byTick) return byTick;
    if (rows[best]) return rows[best];
  }
  return rows.length ? rows[0] : null;
}

function commsStateName(value) {
  return COMMS_STATE_NAMES[Number(value)] || `STATE_${value}`;
}

function packetOpcode(value) {
  if (typeof value === 'string' && value.startsWith('0x')) {
    return Number.parseInt(value.slice(-1), 16) & 0x3;
  }
  return Number(value || 0) & 0x3;
}

function packetTypeNameFromWord(value) {
  const opcode = packetOpcode(value);
  if (opcode === 0) return playbackUsesFullMsgOp() ? 'MSG_OP_64' : 'MSG_OP';
  if (opcode === 1) return 'DATA_OP';
  if (opcode === 2) return 'CONFIG_WRITE_OP';
  if (opcode === 3) return 'CONFIG_READ_OP';
  return `OP_${opcode}`;
}

function formatPacketDecode(decoded = {}, packetType = '', obj = playback) {
  if (packetType === 'msg_packet' && playbackUsesFullMsgOp(obj)) {
    const payload = decoded.msg_payload_62;
    if (payload === undefined || payload === null) return JSON.stringify(decoded, null, 2);
    const payloadHex = `0x${BigInt(payload).toString(16).padStart(16, '0')}`;
    return JSON.stringify({
      packet_type: decoded.packet_type,
      on_wire_bits: decoded.on_wire_bits,
      msg_payload_62: payloadHex,
    }, null, 2);
  }
  return JSON.stringify(decoded, null, 2);
}

function formatHexWord(value) {
  const text = String(value || '0x0000000000000000');
  if (text === '0x0000000000000000') return '—';
  return text;
}

function abbreviateWord(value) {
  const text = String(value || '0x0000000000000000');
  if (text.length <= 14) return text;
  return `${text.slice(0, 8)}...${text.slice(-4)}`;
}

function chipDebugRowAtTick(tick) {
  return chipDebugRowAtTickFrom(chipDebugData, tick);
}

async function loadChipDebugDataset(meta, sourceUrl, fallbackCandidates = []) {
  if (!meta && fallbackCandidates.length === 0) return null;
  const candidates = [];
  if (meta?.sidecar_url) candidates.push(meta.sidecar_url);
  if (meta?.csv_url) candidates.push(meta.csv_url);
  candidates.push(...fallbackCandidates);
  const seen = new Set();
  for (const candidate of candidates) {
    if (!candidate || seen.has(candidate)) continue;
    seen.add(candidate);
    try {
      const resolved = new URL(candidate, sourceUrl || window.location.href);
      resolved.searchParams.set('cb', String(Date.now()));
      const response = await fetch(resolved.toString(), { cache: 'no-store' });
      if (!response.ok) continue;
      const text = await response.text();
      let parsed = null;
      const trimmed = text.trim();
      if (trimmed.startsWith('{')) {
        parsed = parseChipDebugSidecar(JSON.parse(trimmed));
      } else {
        parsed = parseChipDebugCsv(text);
      }
      if (!parsed) continue;
      return {
        ...parsed,
        sourceUrl: resolved.toString(),
        monitorChipId: Number(meta?.monitor_chip_id ?? parsed.monitorChipId ?? 0),
        monitorRuntimeId: Number(meta?.monitor_runtime_id ?? parsed.monitorRuntimeId ?? 0),
        label: String(meta?.label || parsed.label || ''),
        kind: String(meta?.kind || parsed.kind || 'sidecar'),
        signalSpecs: Array.isArray(meta?.signal_specs) ? meta.signal_specs : parsed.signalSpecs,
      };
    } catch (_) {}
  }
  return null;
}

async function tryLoadChipDebugForPlayback(obj, sourceUrl) {
  chipDebugData = null;
  chipDebugAuxData = null;
  const params = new URLSearchParams(window.location.search);
  const primaryFallbacks = [];
  const explicitSidecar = params.get('sidecar');
  const explicit = params.get('chip_debug');
  if (explicitSidecar) primaryFallbacks.push(explicitSidecar);
  if (explicit) primaryFallbacks.push(explicit);
  if (typeof sourceUrl === 'string' && sourceUrl.length > 0) {
    primaryFallbacks.push(sourceUrl.replace(/[^/]+$/, 'chip0_debug_sidecar.json'));
    primaryFallbacks.push(sourceUrl.replace(/[^/]+$/, 'chip0_rx_debug.csv'));
  }
  chipDebugData = await loadChipDebugDataset(obj?.chip_internal_debug, sourceUrl, primaryFallbacks);
  chipDebugAuxData = await loadChipDebugDataset(obj?.chip_internal_debug_aux, sourceUrl, []);
}

function updateViewButtons() {
  const hasChipDebug = Boolean(chipDebugData);
  showNetworkViewBtn?.classList.toggle('active', currentView === 'network');
  if (showChipViewBtn) showChipViewBtn.hidden = !hasChipDebug;
  if (showChipViewBtn && hasChipDebug) showChipViewBtn.textContent = chipDebugLabel();
  showChipViewBtn?.classList.toggle('active', currentView === 'chip');
}

function setCurrentView(view) {
  if (view === 'chip' && !chipDebugData) view = 'network';
  currentView = view;
  selectedTarget = null;
  updateViewButtons();
  updateChipViewHudControls();
  resize();
}


function drawSharedFifoCounter(left, top, cell, occupancy) {
  const barInset = Math.max(6, cell * 0.08);
  const barWidth = Math.max(12, cell * 0.84 - barInset * 2);
  const barHeight = Math.max(8, cell * 0.1);
  const barLeft = left + barInset;
  const barTop = top + cell * 0.84 - barInset - barHeight;

  ctx.fillStyle = THEME.surfaceMuted;
  ctx.strokeStyle = 'rgba(22, 128, 90, 0.48)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.roundRect(barLeft, barTop, barWidth, barHeight, 5);
  ctx.fill();
  ctx.stroke();

  if (cell >= 72) {
    ctx.fillStyle = occupancy > 0 ? SHARED_FIFO_TEXT_COLOR : '#7c6a8f';
    ctx.font = `${Math.max(9, cell * 0.11)}px ui-monospace, monospace`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(occupancy), barLeft + barWidth * 0.5, barTop + barHeight * 0.5);
    ctx.textBaseline = 'alphabetic';
  }
}

function fpgaLayout(layout) {
  if (!playback?.source) return null;
  const src = layout.cellCenter(playback.source.x, playback.source.y);
  const size = Math.max(22, layout.cell * 0.34);
  const gap = Math.max(12, layout.cell * 0.18);
  return {
    left: src.x - size * 0.5,
    top: src.y + layout.cell * 0.5 + gap,
    width: size,
    height: size,
    centerX: src.x,
    centerY: src.y + layout.cell * 0.5 + gap + size * 0.5,
  };
}

function pointInRect(x, y, rect) {
  return rect && x >= rect.left && x <= rect.left + rect.width && y >= rect.top && y <= rect.top + rect.height;
}

function drawFpga(layout, fpgaTxEvents, fpgaRxEvents) {
  const rect = fpgaLayout(layout);
  if (!rect) return null;
  const isSelected = selectedTarget?.type === 'fpga';
  const active = fpgaTxEvents.length > 0 || fpgaRxEvents.length > 0;
  const src = layout.cellCenter(playback.source.x, playback.source.y);
  const connectorColor = active ? SOURCE_FPGA_LANE_COLOR : SOURCE_FPGA_LANE_INACTIVE_COLOR;

  ctx.strokeStyle = connectorColor;
  ctx.lineWidth = active ? 4 : 2;
  ctx.beginPath();
  ctx.moveTo(src.x, src.y + layout.cell * 0.42);
  ctx.lineTo(rect.centerX, rect.top);
  ctx.stroke();

  ctx.fillStyle = active ? '#f0e7f8' : THEME.surface;
  ctx.strokeStyle = isSelected ? THEME.selected : connectorColor;
  ctx.lineWidth = isSelected ? 3 : 2;
  ctx.beginPath();
  ctx.roundRect(rect.left, rect.top, rect.width, rect.height, 8);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(9, layout.cell * 0.09)}px ui-monospace, monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('FPGA', rect.centerX, rect.centerY - 4);
  ctx.font = `${Math.max(8, layout.cell * 0.08)}px ui-monospace, monospace`;
  ctx.fillStyle = active ? SOURCE_FPGA_LANE_COLOR : THEME.subtleText;
  ctx.fillText(`T${fpgaTxEvents.length}/R${fpgaRxEvents.length}`, rect.centerX, rect.centerY + 8);
  ctx.textBaseline = 'alphabetic';
  return rect;
}

function drawFlowArrow(x1, y1, x2, y2, color, active, label = '') {
  const displayColor = themeColor(color);
  ctx.strokeStyle = active ? displayColor : THEME.inactive;
  ctx.lineWidth = active ? 4 : 2;
  ctx.beginPath();
  ctx.moveTo(x1, y1);
  ctx.lineTo(x2, y2);
  ctx.stroke();

  const dx = x2 - x1;
  const dy = y2 - y1;
  const len = Math.hypot(dx, dy) || 1;
  const ux = dx / len;
  const uy = dy / len;
  const px = -uy;
  const py = ux;
  const headLen = 10;
  const headWidth = 6;
  const hx = x2 - ux * headLen;
  const hy = y2 - uy * headLen;

  ctx.fillStyle = active ? displayColor : THEME.inactive;
  ctx.beginPath();
  ctx.moveTo(x2, y2);
  ctx.lineTo(hx + px * headWidth, hy + py * headWidth);
  ctx.lineTo(hx - px * headWidth, hy - py * headWidth);
  ctx.closePath();
  ctx.fill();

  if (label) {
    ctx.fillStyle = active ? THEME.text : THEME.subtleText;
    ctx.font = '11px ui-monospace, monospace';
    ctx.textAlign = 'center';
    ctx.fillText(label, (x1 + x2) * 0.5, (y1 + y2) * 0.5 - 8);
  }
}

function drawComponentBox(rect, title, lines, options = {}) {
  const active = Boolean(options.active);
  const accent = themeColor(options.accent || '#4db0ff');
  ctx.fillStyle = active ? '#eef4fb' : THEME.surface;
  ctx.strokeStyle = active ? accent : THEME.inactive;
  ctx.lineWidth = active ? 2.5 : 1.5;
  ctx.beginPath();
  ctx.roundRect(rect.left, rect.top, rect.width, rect.height, 12);
  ctx.fill();
  ctx.stroke();

  ctx.fillStyle = THEME.text;
  ctx.font = '12px ui-monospace, monospace';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.fillText(title, rect.left + 10, rect.top + 8);

  ctx.fillStyle = THEME.mutedText;
  ctx.font = '11px ui-monospace, monospace';
  let y = rect.top + 28;
  for (const line of lines) {
    ctx.fillText(line, rect.left + 10, y);
    y += 14;
  }
  ctx.textBaseline = 'alphabetic';
}

function debugWindowRows(centerTick, before = 14, after = 22) {
  return debugWindowRowsFrom(chipDebugData, centerTick, before, after);
}

function debugWindowRowsFrom(data, centerTick, before = 14, after = 22) {
  const scaledBefore = Math.max(1, Math.round(before * chipTimelineSpanScale));
  const scaledAfter = Math.max(1, Math.round(after * chipTimelineSpanScale));
  const start = Math.max(0, Number(centerTick || 0) - scaledBefore);
  const end = Number(centerTick || 0) + scaledAfter;
  return (data?.rows || []).filter((row) => Number(row.tick || 0) >= start && Number(row.tick || 0) <= end);
}

function drawSignalTimeline(rect, rows, specs, currentTick) {
  ctx.fillStyle = THEME.surface;
  ctx.strokeStyle = THEME.gridStrong;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.roundRect(rect.left, rect.top, rect.width, rect.height, 12);
  ctx.fill();
  ctx.stroke();

  if (!rows.length) return;
  const startTick = Number(rows[0].tick || 0);
  const endTick = Number(rows[rows.length - 1].tick || 0);
  const plotLeft = rect.left + 152;
  const plotRight = rect.left + rect.width - 14;
  const plotTop = rect.top + 16;
  const rowGap = 10;
  const rowHeight = (rect.height - 28 - Math.max(0, specs.length - 1) * rowGap) / specs.length;
  const tickSpan = Math.max(1, endTick - startTick);
  const xAt = (tick) => plotLeft + ((tick - startTick) / tickSpan) * (plotRight - plotLeft);

  ctx.save();
  ctx.strokeStyle = THEME.grid;
  ctx.lineWidth = 1;
  ctx.setLineDash([4, 4]);
  for (let tick = startTick; tick <= endTick; tick += 1) {
    const x = xAt(tick);
    ctx.beginPath();
    ctx.moveTo(x, plotTop - 4);
    ctx.lineTo(x, rect.top + rect.height - 12);
    ctx.stroke();
  }
  ctx.restore();

  ctx.font = '11px ui-monospace, monospace';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'middle';

  for (let i = 0; i < specs.length; i += 1) {
    const spec = specs[i];
    const baseY = plotTop + i * (rowHeight + rowGap);
    const yLow = baseY + rowHeight * 0.72;
    const yHigh = baseY + rowHeight * 0.18;
    ctx.font = '11px ui-monospace, monospace';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = THEME.text;
    ctx.fillText(spec.label, rect.left + 10, baseY + rowHeight * 0.45);
    ctx.strokeStyle = THEME.gridStrong;
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(plotLeft, yLow);
    ctx.lineTo(plotRight, yLow);
    ctx.stroke();
    const displayColor = themeColor(spec.color);
    ctx.strokeStyle = displayColor;
    ctx.lineWidth = 2;
    ctx.beginPath();
    let lastValue = null;
    const labels = [];
    for (let idx = 0; idx < rows.length; idx += 1) {
      const row = rows[idx];
      const rawValue = spec.value(row);
      const value = spec.kind === 'word'
        ? 0
        : Number(rawValue || 0);
      const x = xAt(Number(row.tick || 0));
      const y = spec.kind === 'binary'
        ? (value ? yHigh : yLow)
        : spec.kind === 'counter'
          ? yLow
          : spec.kind === 'word'
            ? ((String(rawValue || '0x0') === '0x0' || String(rawValue || '0x0') === '0x0000000000000000') ? yLow : yHigh)
          : (() => {
            const maxValue = Math.max(1, Number(spec.maxValue || 1));
            return yLow - Math.min(1, value / maxValue) * (yLow - yHigh);
          })();
      if (idx === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
      const nextTick = idx + 1 < rows.length ? Number(rows[idx + 1].tick || 0) : Number(row.tick || 0);
      const nextX = xAt(nextTick);
      const labelX = (x + nextX) * 0.5;
      ctx.lineTo(nextX, y);
      if (spec.kind === 'counter') {
        if (nextX > x && (lastValue === null || value !== lastValue)) {
          labels.push({ text: String(value), x: labelX, y: y - 6, fontSize: 10 });
          lastValue = value;
        }
      } else if (spec.kind === 'word') {
        const text = String(rawValue || '0x0000000000000000');
        if (nextX > x && (lastValue === null || text !== lastValue) && text !== '0x0000000000000000') {
          labels.push({ text: abbreviateWord(text), x: labelX, y: y - 6, fontSize: 10 });
          lastValue = text;
        }
      }
      if (nextX > x && spec.tickLabel) {
        const text = String(spec.tickLabel(rawValue, row) || '');
        if (text) {
          labels.push({
            text,
            x: labelX,
            y: y - 5,
            fontSize: Number(spec.tickLabelFontSize || 7),
          });
        }
      }
    }
    ctx.stroke();
    ctx.fillStyle = displayColor;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'bottom';
    for (const label of labels) {
      ctx.font = `${label.fontSize}px ui-monospace, monospace`;
      ctx.fillText(label.text, label.x, label.y);
    }
  }

  ctx.strokeStyle = THEME.selected;
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(xAt(currentTick), rect.top + 8);
  ctx.lineTo(xAt(currentTick), rect.top + rect.height - 8);
  ctx.stroke();

  ctx.fillStyle = THEME.mutedText;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  for (let tick = Math.ceil(startTick / 10) * 10; tick <= endTick; tick += 10) {
    const x = xAt(tick);
    ctx.fillText(String(tick), x, rect.top + rect.height - 4);
  }
}

function laneSignalSpecs(lane) {
  const colors = {
    bit: '#6fd3ff',
    empty: '#b9c6d8',
    sync: '#ff9f43',
    cnt: '#61e294',
    lock: '#f2d06b',
    pass: '#7ee0a1',
    fail: '#ff8f8f',
  };
  return [
    { key: `${lane}_rx_in_bit`, label: `${lane}_rx_in_bit`, kind: 'binary', color: colors.bit, value: (r) => Number(r[`${lane}_rx_in_bit`] ?? 1) ? 1 : 0 },
    { key: `${lane}_rx_sync`, label: `${lane}_rx_sync`, kind: 'binary', color: '#ffffff', value: (r) => Number(r[`${lane}_rx_sync`] ?? 1) ? 1 : 0 },
    { key: `${lane}_sync_armed`, label: `${lane}_sync_armed`, kind: 'binary', color: colors.sync, value: (r) => Number(r[`${lane}_sync_armed`] ?? 0) ? 1 : 0 },
    { key: `${lane}_busy`, label: `${lane}_busy`, kind: 'binary', color: '#8fd0ff', value: (r) => Number(r[`${lane}_busy`] ?? 0) ? 1 : 0 },
    { key: `${lane}_packet_ready`, label: `${lane}_packet_ready`, kind: 'binary', color: '#ff7a7a', value: (r) => Number(r[`${lane}_packet_ready`] ?? 0) ? 1 : 0 },
    { key: `${lane}_bit_cnt`, label: `${lane}_bit_cnt`, kind: 'counter', color: colors.cnt, value: (r) => Number(r[`${lane}_bit_cnt`] ?? 0), maxValue: 64 },
    { key: `${lane}_sync_lock`, label: `${lane}_sync_lock`, kind: 'binary', color: colors.lock, value: (r) => Number(r[`${lane}_sync_lock`] ?? 0) ? 1 : 0 },
    { key: `${lane}_sync_pass`, label: `${lane}_sync_pass`, kind: 'counter', color: colors.pass, value: (r) => Number(r[`${lane}_sync_pass`] ?? 0), maxValue: 7 },
    { key: `${lane}_sync_fail`, label: `${lane}_sync_fail`, kind: 'counter', color: colors.fail, value: (r) => Number(r[`${lane}_sync_fail`] ?? 0), maxValue: 7 },
  ];
}

function txMaskBit(mask, edge) {
  return ((Number(mask || 0) >> PISO_EDGE_TO_BIT[edge]) & 1) ? 1 : 0;
}

function txSignalSpecs(lane) {
  return [
    { key: 'chip_fifo_occupancy', label: 'chip_fifo_occupancy', kind: 'counter', color: '#61e294', value: (r) => Number(r.chip_fifo_occupancy ?? 0), maxValue: 16 },
    { key: `${lane}_hydra_pending_valid`, label: `${lane}_hydra_pending_valid`, kind: 'binary', color: '#ffb04d', value: (r) => Number(r[`${lane}_hydra_pending_valid`] ?? 0) ? 1 : 0 },
    { key: `${lane}_hydra_tx_busy`, label: `${lane}_hydra_tx_busy`, kind: 'binary', color: '#8fd0ff', value: (r) => txMaskBit(r.hydra_tx_busy, lane) },
    { key: `${lane}_raw_tx_busy`, label: `${lane}_raw_tx_busy`, kind: 'binary', color: '#9fb6ff', value: (r) => Number(r[`${lane}_raw_tx_busy`] ?? 0) ? 1 : 0 },
    { key: `${lane}_hydra_ld_tx`, label: `${lane}_hydra_ld_tx`, kind: 'binary', color: '#f2d06b', value: (r) => txMaskBit(r.hydra_ld_tx_data_uart, lane) },
    { key: `${lane}_final_ld_tx`, label: `${lane}_final_ld_tx`, kind: 'binary', color: '#ff7a7a', value: (r) => txMaskBit(r.final_ld_tx_data_uart, lane) },
    { key: `${lane}_select_hydra`, label: `${lane}_select_hydra`, kind: 'binary', color: '#4db0ff', value: (r) => txMaskBit(r.arb_select_hydra, lane) },
    { key: `${lane}_select_nifty`, label: `${lane}_select_nifty`, kind: 'binary', color: '#d784ff', value: (r) => txMaskBit(r.arb_select_nifty, lane) },
    { key: `${lane}_tx_bit_valid`, label: `${lane}_tx_bit_valid`, kind: 'binary', color: '#ffffff', value: (r) => Number(r[`${lane}_tx_bit_valid`] ?? 0) ? 1 : 0 },
    { key: `${lane}_tx_bit`, label: `${lane}_tx_bit`, kind: 'binary', color: '#6fd3ff', value: (r) => Number(r[`${lane}_tx_bit`] ?? 1) ? 1 : 0 },
  ];
}

function v3cRxSignalSpecs(lane) {
  return [
    { key: `${lane}_rx_in_bit`, label: `${lane}_rx_in_bit`, kind: 'binary', color: '#6fd3ff', value: (r) => Number(r[`${lane}_rx_in_bit`] ?? 1) ? 1 : 0 },
    { key: `${lane}_rx_sync`, label: `${lane}_rx_sync`, kind: 'binary', color: '#ffffff', value: (r) => Number(r[`${lane}_rx_sync`] ?? 1) ? 1 : 0 },
    { key: `${lane}_busy`, label: `${lane}_busy`, kind: 'binary', color: '#8fd0ff', value: (r) => Number(r[`${lane}_busy`] ?? 0) ? 1 : 0 },
    { key: `${lane}_packet_ready`, label: `${lane}_packet_ready`, kind: 'binary', color: '#ff7a7a', value: (r) => Number(r[`${lane}_packet_ready`] ?? 0) ? 1 : 0 },
    { key: `${lane}_bit_cnt`, label: `${lane}_bit_cnt`, kind: 'counter', color: '#61e294', value: (r) => Number(r[`${lane}_bit_cnt`] ?? 0), maxValue: 63 },
    { key: `${lane}_rx_empty`, label: `${lane}_rx_empty`, kind: 'binary', color: '#b9c6d8', value: (r) => Number(r[`${lane}_rx_empty`] ?? 1) ? 1 : 0 },
    { key: `${lane}_hold_valid`, label: `${lane}_hold_valid`, kind: 'binary', color: '#ffb04d', value: (r) => Number(r[`${lane}_hold_valid`] ?? 0) ? 1 : 0 },
  ];
}

function maskDirections(mask, edgeToBit) {
  const value = Number(mask || 0);
  return [
    ['N', edgeToBit.north],
    ['E', edgeToBit.east],
    ['S', edgeToBit.south],
    ['W', edgeToBit.west],
  ]
    .filter(([, bit]) => ((value >> bit) & 1) !== 0)
    .map(([direction]) => direction)
    .join('');
}

const posiMaskDirections = (mask) => maskDirections(mask, POSI_EDGE_TO_BIT);
const pisoMaskDirections = (mask) => maskDirections(mask, PISO_EDGE_TO_BIT);

function hydraStateAbbreviation(state) {
  return ['', 'RC', 'RP', 'TU', 'TG', 'TS', 'TW'][Number(state || 0)] || '';
}

function v3cHydraSignalSpecs() {
  return [
    {
      key: 'hydra_state',
      label: 'hydra_state',
      kind: 'value',
      color: '#9fb6ff',
      value: (r) => Number(r.hydra_state ?? 0),
      maxValue: 6,
      tickLabel: hydraStateAbbreviation,
      tickLabelFontSize: 7,
    },
    {
      key: 'hydra_uart_has_data',
      label: 'uart_has_data mask',
      kind: 'value',
      color: '#6fd3ff',
      value: (r) => Number(r.hydra_uart_has_data ?? 0),
      maxValue: 15,
      tickLabel: posiMaskDirections,
      tickLabelFontSize: 7,
    },
    {
      key: 'hydra_sel_onehot',
      label: 'selected RX mask',
      kind: 'value',
      color: '#f2d06b',
      value: (r) => Number(r.hydra_sel_onehot ?? 0),
      maxValue: 15,
      tickLabel: posiMaskDirections,
      tickLabelFontSize: 7,
    },
    {
      key: 'hydra_uld_rx_data_uart',
      label: 'RX unload mask',
      kind: 'value',
      color: '#ffb04d',
      value: (r) => Number(r.hydra_uld_rx_data_uart ?? 0),
      maxValue: 15,
      tickLabel: posiMaskDirections,
      tickLabelFontSize: 7,
    },
    { key: 'hydra_rx_data_flag', label: 'rx_data_flag', kind: 'binary', color: '#7ee0a1', value: (r) => Number(r.hydra_rx_data_flag ?? 0) ? 1 : 0 },
    { key: 'hydra_pkt_valid', label: 'pkt_valid', kind: 'binary', color: '#61e294', value: (r) => Number(r.hydra_pkt_valid ?? 0) ? 1 : 0 },
    { key: 'hydra_fifo_write_n', label: 'fifo_write_n', kind: 'binary', color: '#ff8f8f', value: (r) => Number(r.hydra_fifo_write_n ?? 1) ? 1 : 0 },
    { key: 'chip_fifo_occupancy', label: 'FIFO occupancy', kind: 'counter', color: '#61e294', value: (r) => Number(r.chip_fifo_occupancy ?? 0), maxValue: 128 },
    { key: 'hydra_fifo_read_n', label: 'fifo_read_n', kind: 'binary', color: '#d784ff', value: (r) => Number(r.hydra_fifo_read_n ?? 1) ? 1 : 0 },
    {
      key: 'final_ld_tx_data_uart',
      label: 'TX load mask',
      kind: 'value',
      color: '#f2d06b',
      value: (r) => Number(r.final_ld_tx_data_uart ?? 0),
      maxValue: 15,
      tickLabel: pisoMaskDirections,
      tickLabelFontSize: 7,
    },
    { key: 'south_raw_tx_busy', label: 'south TX busy', kind: 'binary', color: '#9fb6ff', value: (r) => Number(r.south_raw_tx_busy ?? 0) ? 1 : 0 },
    { key: 'south_tx_bit', label: 'south TX bit', kind: 'binary', color: '#ffffff', value: (r) => Number(r.south_tx_bit ?? 1) ? 1 : 0 },
  ];
}

function drawV3cPacketLossChip0View(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);
  if (!chipDebugData || !chipDebugRowAtTick(currentTickIndex)) {
    updateHud();
    return;
  }

  const baseScale = Math.max(0.58, Math.min(1.0, Math.min(availableW / 1260, availableH / 1080)));
  const scale = baseScale * chipViewZoom;
  const ox = marginLeft + Math.max(8, (availableW - 1230 * scale) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;
  const rows = debugWindowRowsFrom(chipDebugData, currentTickIndex, 24, 36);

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  ctx.fillText('v3c path: north/east UART RX → Hydra arbitration/FIFO → south UART TX', sx(0), sy(48));

  ctx.fillStyle = THEME.text;
  ctx.textAlign = 'left';
  ctx.fillText('North RX from chip 2', sx(0), sy(78));
  drawSignalTimeline(
    { left: sx(0), top: sy(90), width: sw(1230), height: sw(250) },
    rows,
    v3cRxSignalSpecs('north'),
    currentTickIndex,
  );

  ctx.fillStyle = THEME.text;
  ctx.textAlign = 'left';
  ctx.fillText('East RX from chip 1', sx(0), sy(370));
  drawSignalTimeline(
    { left: sx(0), top: sy(382), width: sw(1230), height: sw(250) },
    rows,
    v3cRxSignalSpecs('east'),
    currentTickIndex,
  );

  ctx.fillStyle = THEME.text;
  ctx.textAlign = 'left';
  ctx.fillText('Hydra arbitration, shared FIFO, and south TX', sx(0), sy(662));
  drawSignalTimeline(
    { left: sx(0), top: sy(674), width: sw(1230), height: sw(390) },
    rows,
    v3cHydraSignalSpecs(),
    currentTickIndex,
  );
  updateHud();
}

function drawV3cConvergentPacketLossChip4View(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);
  if (!chipDebugData || !chipDebugRowAtTick(currentTickIndex)) {
    updateHud();
    return;
  }

  const baseScale = Math.max(0.58, Math.min(1.0, Math.min(availableW / 1260, availableH / 1370)));
  const scale = baseScale * chipViewZoom;
  const ox = marginLeft + Math.max(8, (availableW - 1230 * scale) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;
  const rows = debugWindowRowsFrom(chipDebugData, currentTickIndex, 24, 36);

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  ctx.fillText('v3c path: north/east/west UART RX → Hydra arbitration/FIFO → south UART TX', sx(0), sy(48));

  ctx.fillStyle = THEME.text;
  ctx.textAlign = 'left';
  ctx.fillText('Hydra arbitration, shared FIFO, and south TX', sx(0), sy(78));
  drawSignalTimeline(
    { left: sx(0), top: sy(90), width: sw(1230), height: sw(390) },
    rows,
    v3cHydraSignalSpecs(),
    currentTickIndex,
  );

  const rxSections = [
    { lane: 'north', title: 'North RX from chip 7', titleY: 510, timelineY: 522 },
    { lane: 'east', title: 'East RX from chip 5', titleY: 802, timelineY: 814 },
    { lane: 'west', title: 'West RX from chip 3', titleY: 1094, timelineY: 1106 },
  ];
  for (const section of rxSections) {
    ctx.fillStyle = THEME.text;
    ctx.textAlign = 'left';
    ctx.fillText(section.title, sx(0), sy(section.titleY));
    drawSignalTimeline(
      { left: sx(0), top: sy(section.timelineY), width: sw(1230), height: sw(250) },
      rows,
      v3cRxSignalSpecs(section.lane),
      currentTickIndex,
    );
  }
  updateHud();
}

function drawSingleChipTimelineView(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);

  if (!chipDebugData) {
    updateHud();
    return;
  }

  const row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
  const baseScale = Math.max(0.72, Math.min(1.0, Math.min(availableW / 1260, availableH / 980)));
  const scale = baseScale * chipViewZoom;
  const contentWidth = 1210 * scale;
  const ox = marginLeft + Math.max(8, (availableW - contentWidth) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  ctx.fillText(`source ${chipDebugData.sourceUrl.split('/').pop()}`, sx(0), sy(48));

  if (!row) {
    ctx.fillStyle = THEME.text;
    ctx.font = '16px ui-monospace, monospace';
    ctx.fillText('No debug sample is available for the current tick.', sx(0), sy(92));
    updateHud();
    return;
  }

  const rows = debugWindowRowsFrom(chipDebugData, currentTickIndex, 24, 36);
  const specs = chipDebugSignalSpecs(chipDebugData) || txSignalSpecs('south');
  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(12, 13 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(`Chip ${chipDebugData.monitorChipId} timeline: south-lane TX`, sx(0), sy(84));
  drawSignalTimeline(
    { left: sx(-34), top: sy(98), width: sw(1268), height: Math.max(sw(420), specs.length * sw(30)) },
    rows,
    specs,
    currentTickIndex,
  );

  updateHud();
}

function drawChip1SouthTxChip0NorthRxFocusView(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);

  if (!chipDebugData || !chipDebugAuxData) {
    updateHud();
    return;
  }

  const chip1Row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
  const chip0Row = chipDebugRowAtTickFrom(chipDebugAuxData, currentTickIndex);
  const baseScale = Math.max(0.72, Math.min(1.0, Math.min(availableW / 1260, availableH / 980)));
  const scale = baseScale * chipViewZoom;
  const ox = marginLeft + Math.max(10, (availableW - 1120 * scale) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  ctx.fillText(
    `top ${chipDebugData.sourceUrl.split('/').pop()} | bottom ${chipDebugAuxData.sourceUrl.split('/').pop()}`,
    sx(0),
    sy(48),
  );

  if (!chip1Row || !chip0Row) {
    ctx.fillStyle = THEME.text;
    ctx.font = '16px ui-monospace, monospace';
    ctx.fillText('No debug sample is available for the current tick.', sx(0), sy(92));
    updateHud();
    return;
  }

  const chip1Rows = debugWindowRowsFrom(chipDebugData, currentTickIndex, 20, 28);
  const chip0Rows = debugWindowRowsFrom(chipDebugAuxData, currentTickIndex, 20, 28);
  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(12, 13 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(`Chip ${chipDebugData.monitorChipId} timeline: south-lane TX`, sx(0), sy(84));
  drawSignalTimeline(
    { left: sx(0), top: sy(98), width: sw(1230), height: sw(260) },
    chip1Rows,
    txSignalSpecs('south'),
    currentTickIndex,
  );
  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(12, 13 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(`Chip ${chipDebugAuxData.monitorChipId} timeline: north-lane RX`, sx(0), sy(390));
  drawSignalTimeline(
    { left: sx(0), top: sy(404), width: sw(1230), height: sw(320) },
    chip0Rows,
    laneSignalSpecs('north'),
    currentTickIndex,
  );

  updateHud();
}

function drawChip0NorthTxChip1SouthRxFocusView(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);

  if (!chipDebugData || !chipDebugAuxData) {
    updateHud();
    return;
  }

  const chip0Row = chipDebugRowAtTickFrom(chipDebugData, currentTickIndex);
  const chip1Row = chipDebugRowAtTickFrom(chipDebugAuxData, currentTickIndex);
  const baseScale = Math.max(0.72, Math.min(1.0, Math.min(availableW / 1260, availableH / 980)));
  const scale = baseScale * chipViewZoom;
  const ox = marginLeft + Math.max(10, (availableW - 1120 * scale) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  ctx.fillText(
    `top ${chipDebugData.sourceUrl.split('/').pop()} | bottom ${chipDebugAuxData.sourceUrl.split('/').pop()}`,
    sx(0),
    sy(48),
  );

  if (!chip0Row || !chip1Row) {
    ctx.fillStyle = THEME.text;
    ctx.font = '16px ui-monospace, monospace';
    ctx.fillText('No debug sample is available for the current tick.', sx(0), sy(92));
    updateHud();
    return;
  }

  const chip0Rows = debugWindowRowsFrom(chipDebugData, currentTickIndex, 20, 28);
  const chip1Rows = debugWindowRowsFrom(chipDebugAuxData, currentTickIndex, 20, 28);
  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(12, 13 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(`Chip ${chipDebugData.monitorChipId} timeline: north-lane TX / arbiter`, sx(0), sy(84));
  drawSignalTimeline(
    { left: sx(0), top: sy(98), width: sw(1230), height: sw(260) },
    chip0Rows,
    txSignalSpecs('north'),
    currentTickIndex,
  );
  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(12, 13 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(`Chip ${chipDebugAuxData.monitorChipId} timeline: south-lane RX`, sx(0), sy(390));
  drawSignalTimeline(
    { left: sx(0), top: sy(404), width: sw(1230), height: sw(320) },
    chip1Rows,
    laneSignalSpecs('south'),
    currentTickIndex,
  );

  updateHud();
}

function txPathSignalSpecs() {
  return [
    { key: 'chip_fifo_occupancy', label: 'chip_fifo_occupancy', kind: 'counter', color: '#61e294', value: (r) => Number(r.chip_fifo_occupancy ?? 0), maxValue: 16 },
    { key: 'south_hydra_pending_valid', label: 'south_hydra_pending_valid', kind: 'binary', color: '#ffb04d', value: (r) => Number(r.south_hydra_pending_valid ?? 0) ? 1 : 0 },
  ];
}

function drawNiftyReg125ProofView(width, height) {
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = Math.max(0, Math.round((hudWidth + 8) * 0.25));
  const margin = 26;
  const availableW = Math.max(300, width - marginLeft - margin);
  const availableH = Math.max(300, height - margin * 2);
  const scale = Math.max(0.74, Math.min(1.0, Math.min(availableW / 1260, availableH / 820)));
  const ox = marginLeft + Math.max(10, (availableW - 1120 * scale) * 0.5);
  const oy = margin + Math.max(10, (availableH - 760 * scale) * 0.5);
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;

  let row = chipDebugRowAtTick(currentTickIndex);
  if (!row && Array.isArray(chipDebugData?.rows) && chipDebugData.rows.length > 0) {
    row = chipDebugData.rows[0];
  }
  if (!row) {
    ctx.fillStyle = THEME.text;
    ctx.font = '18px ui-monospace, monospace';
    ctx.fillText('No debug sidecar sample is available for the current tick.', sx(0), sy(60));
    updateHud();
    return;
  }

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText('Chip 0 Sidecar View: Nifty Register 125 Proof', sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  const replyPacket = chipDebugData?.summary?.reply_packet || 'n/a';
  ctx.fillText(`debug source ${chipDebugData.sourceUrl.split('/').pop()} | reply ${replyPacket}`, sx(0), sy(48));

  const niftyCtrlRect = { left: sx(0), top: sy(92), width: sw(245), height: sw(128) };
  const niftyCfgRect = { left: sx(290), top: sy(92), width: sw(235), height: sw(128) };
  const arbiterRect = { left: sx(570), top: sy(92), width: sw(220), height: sw(128) };
  const commsRect = { left: sx(840), top: sy(92), width: sw(245), height: sw(128) };
  const regfileRect = { left: sx(570), top: sy(280), width: sw(220), height: sw(116) };
  const timelineRect = { left: sx(0), top: sy(450), width: sw(1085), height: sw(255) };

  drawComponentBox(
    niftyCtrlRect,
    'nifty_ctrl',
    [
      `cfg_cmd_valid: ${row.nifty_cfg_cmd_valid}`,
      `cfg_cmd_write: ${row.nifty_cfg_cmd_write}`,
      `stored readback: 0x${Number(row.nifty_local_reg125_read_data || 0).toString(16).toUpperCase().padStart(2, '0')}`,
      `target reg: 125`,
    ],
    { active: Number(row.nifty_cfg_cmd_valid || 0) === 1 || Number(row.nifty_local_reg125_read_data || 0) !== 0, accent: '#7cff7c' },
  );
  drawComponentBox(
    niftyCfgRect,
    'nifty_config_ctrl',
    [
      `write_regmap: ${row.nifty_write_regmap}`,
      `read_regmap: ${row.nifty_read_regmap}`,
      `nifty_read_valid: ${row.nifty_regmap_read_data_valid}`,
      `cmd data: 0x${Number(row.regmap_write_data || 0).toString(16).toUpperCase().padStart(2, '0')}`,
    ],
    { active: Number(row.nifty_write_regmap || 0) === 1 || Number(row.nifty_read_regmap || 0) === 1 || Number(row.nifty_regmap_read_data_valid || 0) === 1, accent: '#4db0ff' },
  );
  drawComponentBox(
    arbiterRect,
    'external_interface arbiter',
    [
      `write_regmap: ${row.write_regmap}`,
      `read_regmap: ${row.read_regmap}`,
      `owner: ${Number(row.regmap_read_owner || 0) === 1 ? 'NIFTY' : 'COMMS'}`,
      `comms_read_regmap: ${row.comms_read_regmap}`,
    ],
    { active: Number(row.write_regmap || 0) === 1 || Number(row.read_regmap || 0) === 1 || Number(row.comms_read_regmap || 0) === 1, accent: '#ffcf4d' },
  );
  drawComponentBox(
    commsRect,
    'comms_ctrl',
    [
      `state: ${commsStateName(row.comms_state)}`,
      `next: ${commsStateName(row.comms_next_state)}`,
      `external read pulse: ${row.comms_read_regmap}`,
      `external write pulse: ${row.comms_write_regmap}`,
      `regmap addr: ${row.comms_regmap_address}`
    ],
    { active: Number(row.comms_read_regmap || 0) === 1 || Number(row.comms_write_regmap || 0) === 1 || Number(row.comms_state || 0) !== 0, accent: '#b46cff' },
  );
  drawComponentBox(
    regfileRect,
    'config_regfile',
    [
      `addr: ${row.regmap_address}`,
      `write_data: 0x${Number(row.regmap_write_data || 0).toString(16).toUpperCase().padStart(2, '0')}`,
      `read_data: 0x${Number(row.regmap_read_data || 0).toString(16).toUpperCase().padStart(2, '0')}`,
      `reg125: 0x${Number(row.reg125_config || 0).toString(16).toUpperCase().padStart(2, '0')}`,
    ],
    { active: Number(row.write_regmap || 0) === 1 || Number(row.read_regmap || 0) === 1 || Number(row.reg125_config || 0) !== 0, accent: '#61e294' },
  );

  drawFlowArrow(niftyCtrlRect.left + niftyCtrlRect.width, niftyCtrlRect.top + niftyCtrlRect.height * 0.5, niftyCfgRect.left, niftyCfgRect.top + niftyCfgRect.height * 0.5, '#7cff7c', Number(row.nifty_cfg_cmd_valid || 0) === 1, Number(row.nifty_cfg_cmd_write || 0) === 1 ? 'write cmd' : Number(row.nifty_cfg_cmd_valid || 0) === 1 ? 'read cmd' : '');
  drawFlowArrow(niftyCfgRect.left + niftyCfgRect.width, niftyCfgRect.top + niftyCfgRect.height * 0.38, arbiterRect.left, arbiterRect.top + arbiterRect.height * 0.38, '#4db0ff', Number(row.nifty_write_regmap || 0) === 1 || Number(row.nifty_read_regmap || 0) === 1, Number(row.nifty_write_regmap || 0) === 1 ? 'local write' : Number(row.nifty_read_regmap || 0) === 1 ? 'local read' : '');
  drawFlowArrow(commsRect.left, commsRect.top + commsRect.height * 0.5, arbiterRect.left + arbiterRect.width, arbiterRect.top + arbiterRect.height * 0.62, '#b46cff', Number(row.comms_read_regmap || 0) === 1, Number(row.comms_read_regmap || 0) === 1 ? 'priority read' : '');
  drawFlowArrow(arbiterRect.left + arbiterRect.width * 0.5, arbiterRect.top + arbiterRect.height, regfileRect.left + regfileRect.width * 0.5, regfileRect.top, '#61e294', Number(row.write_regmap || 0) === 1 || Number(row.read_regmap || 0) === 1, Number(row.write_regmap || 0) === 1 ? 'commit write' : Number(row.read_regmap || 0) === 1 ? 'issue read' : '');
  drawFlowArrow(regfileRect.left, regfileRect.top + regfileRect.height * 0.6, niftyCfgRect.left + niftyCfgRect.width * 0.5, niftyCfgRect.top + niftyCfgRect.height, '#61e294', Number(row.nifty_regmap_read_data_valid || 0) === 1, Number(row.nifty_regmap_read_data_valid || 0) === 1 ? 'owner=NIFTY' : '');
  drawFlowArrow(regfileRect.left + regfileRect.width, regfileRect.top + regfileRect.height * 0.38, commsRect.left + commsRect.width * 0.5, commsRect.top + commsRect.height, '#b46cff', false, '');

  const windowRows = debugWindowRows(currentTickIndex, 16, 30);
  drawSignalTimeline(
    timelineRect,
    windowRows,
    [
      { key: 'nifty_cfg_cmd_valid', label: 'nifty_cfg_cmd_valid', kind: 'binary', color: '#7cff7c', value: (r) => r.nifty_cfg_cmd_valid },
      { key: 'nifty_write_regmap', label: 'nifty_write_regmap', kind: 'binary', color: '#4db0ff', value: (r) => r.nifty_write_regmap },
      { key: 'nifty_read_regmap', label: 'nifty_read_regmap', kind: 'binary', color: '#ffb04d', value: (r) => r.nifty_read_regmap },
      { key: 'comms_read_regmap', label: 'comms_read_regmap', kind: 'binary', color: '#b46cff', value: (r) => r.comms_read_regmap },
      { key: 'comms_write_regmap', label: 'comms_write_regmap', kind: 'binary', color: '#d784ff', value: (r) => r.comms_write_regmap },
      { key: 'comms_state', label: 'comms_state', kind: 'value', color: '#cdb4ff', value: (r) => r.comms_state, maxValue: 3 },
      { key: 'owner', label: 'regmap_read_owner', kind: 'binary', color: '#f0e6ff', value: (r) => r.regmap_read_owner },
      { key: 'reg125', label: 'reg125_config', kind: 'value', color: '#61e294', value: (r) => r.reg125_config, maxValue: 4 },
      { key: 'nifty_local', label: 'nifty_local_reg125_read', kind: 'value', color: '#ff8fb0', value: (r) => r.nifty_local_reg125_read_data, maxValue: 4 },
    ],
    currentTickIndex,
  );

  updateHud();
}

function drawChipInternalView(width, height) {
  if (chipDebugData?.kind === 'v3c_2x2_packet_loss_chip0') {
    drawV3cPacketLossChip0View(width, height);
    return;
  }
  if (chipDebugData?.kind === 'v3c_3x3_convergent_packet_loss_chip4') {
    drawV3cConvergentPacketLossChip4View(width, height);
    return;
  }
  if (chipDebugData?.kind === 'nifty_reg125_proof') {
    drawNiftyReg125ProofView(width, height);
    return;
  }
  if (chipDebugData?.kind === 'chip1_south_tx_only') {
    drawSingleChipTimelineView(width, height);
    return;
  }
  if (chipDebugData?.kind === 'chip1_south_tx_chip0_north_rx_focus') {
    drawChip1SouthTxChip0NorthRxFocusView(width, height);
    return;
  }
  if (chipDebugData?.kind === 'chip0_north_tx_chip1_south_rx_focus') {
    drawChip0NorthTxChip1SouthRxFocusView(width, height);
    return;
  }
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 1;
  const margin = 26;
  const availableW = Math.max(260, width - marginLeft - margin);
  const availableH = Math.max(260, height - margin * 2);

  if (!chipDebugData) {
    ctx.fillStyle = THEME.text;
    ctx.font = '18px ui-monospace, monospace';
    ctx.textAlign = 'center';
    ctx.fillText('Chip internal view is unavailable for this playback.', marginLeft + availableW * 0.5, margin + 80);
    ctx.font = '13px ui-monospace, monospace';
    ctx.fillStyle = THEME.mutedText;
    ctx.fillText('Expected a chip debug sidecar next to the playback JSON.', marginLeft + availableW * 0.5, margin + 108);
    ctx.textAlign = 'left';
    updateHud();
    return;
  }

  const row = chipDebugRowAtTick(currentTickIndex);
  const state = buildStateAt(currentTickIndex);
  let monitorChip = null;
  if (state) {
    for (const chip of state.values()) {
      if (Number(chip.chip_id) === Number(chipDebugData.monitorChipId || 0)) {
        monitorChip = chip;
        break;
      }
    }
  }
  if (!monitorChip && playback?.source) {
    monitorChip = state?.get(`${playback.source.x},${playback.source.y}`) || null;
  }

  const baseScale = Math.max(0.68, Math.min(1.0, Math.min(availableW / 1260, availableH / 720)));
  const scale = baseScale * chipViewZoom;
  const ox = marginLeft + Math.max(10, (availableW - 1120 * scale) * 0.5);
  const oy = margin + 8;
  const sx = (value) => ox + value * scale;
  const sy = (value) => oy + value * scale;
  const sw = (value) => value * scale;

  ctx.fillStyle = THEME.text;
  ctx.font = `${Math.max(16, 18 * scale)}px ui-monospace, monospace`;
  ctx.textAlign = 'left';
  ctx.fillText(chipDebugLabel(), sx(0), sy(24));
  ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
  ctx.fillStyle = THEME.mutedText;
  const chipMeta = monitorChip ? `monitoring chip_id ${monitorChip.chip_id} at (${monitorChip.x},${monitorChip.y})` : `monitoring chip_id ${chipDebugData.monitorChipId ?? 0}`;
  ctx.fillText(`${chipMeta} | debug source ${chipDebugData.sourceUrl.split('/').pop()}`, sx(0), sy(48));

  if (!row) {
    ctx.fillStyle = THEME.text;
    ctx.font = '16px ui-monospace, monospace';
    ctx.fillText('No debug sample is available for the current tick.', sx(0), sy(92));
    ctx.font = `${Math.max(11, 12 * scale)}px ui-monospace, monospace`;
    ctx.fillStyle = '#9a6a00';
    ctx.fillText(`debug rows: ${Array.isArray(chipDebugData?.rows) ? chipDebugData.rows.length : 'n/a'}`, sx(0), sy(118));
    ctx.fillText(`debug ticks: ${Array.isArray(chipDebugData?.ticks) ? chipDebugData.ticks.length : 'n/a'}`, sx(0), sy(138));
    ctx.fillText(`currentTickIndex: ${String(currentTickIndex)}`, sx(0), sy(158));
    updateHud();
    return;
  }

  const windowRows = debugWindowRows(currentTickIndex, 20, 28);
  const laneTopOffsets = [70, 335, 600];
  const laneRects = chipLaneTimelineOrder.map((lane, index) => ({
    lane,
    rect: { left: sx(0), top: sy(laneTopOffsets[index]), width: sw(1230), height: sw(235) },
  }));
  for (const { lane, rect } of laneRects) {
    drawSignalTimeline(rect, windowRows, laneSignalSpecs(lane), currentTickIndex);
  }

  if (row && ('chip_fifo_occupancy' in row || 'south_hydra_pending_valid' in row)) {
    drawSignalTimeline(
      { left: sx(0), top: sy(865), width: sw(1230), height: sw(180) },
      windowRows,
      txPathSignalSpecs(),
      currentTickIndex,
    );
  }

  updateHud();
}

function drawNetworkView(width, height) {
  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = THEME.canvas;
  ctx.fillRect(0, 0, width, height);

  if (!playback) {
    updateHud();
    return;
  }

  const rows = playback.rows;
  const cols = playback.cols;
  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 40;
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

  const { state, packetEvents, chipEvents, chargeEvents, fpgaTxEvents, fpgaRxEvents } = tickData();

  for (let gy = rows - 1; gy >= 0; gy -= 1) {
    for (let gx = 0; gx < cols; gx += 1) {
      const chip = state.get(`${gx},${gy}`) || { x: gx, y: gy, chip_id: 1, up_mask: 0, down_mask: 0 };
      const { x: cx, y: cy } = layout.cellCenter(gx, gy);
      const left = cx - cell * 0.42;
      const top = cy - cell * 0.42;
      const isSelected = selectedTarget?.type === 'chip' && selectedTarget.x === gx && selectedTarget.y === gy;
      const isSourceChip = playback.source && playback.source.x === gx && playback.source.y === gy;

      const activeUpdate = chipEvents.find((update) => update.x === gx && update.y === gy);
      const activeCharge = chargeEvents.find((event) => event.x === gx && event.y === gy);
      const persistCharge = persistentInjectionVisible() && chipHasPersistentInjectionAt(gx, gy, currentTickIndex);
      if (persistCharge) {
        ctx.strokeStyle = activeCharge ? 'rgba(255, 94, 135, 0.42)' : 'rgba(255, 143, 176, 0.30)';
        ctx.lineWidth = activeCharge ? 9 : 6;
        ctx.beginPath();
        ctx.roundRect(left - 4, top - 4, cell * 0.84 + 8, cell * 0.84 + 8, 14);
        ctx.stroke();
      }
      if (isSourceChip) {
        ctx.strokeStyle = 'rgba(77, 176, 255, 0.9)';
        ctx.lineWidth = 3;
        ctx.beginPath();
        ctx.roundRect(left - 7, top - 7, cell * 0.84 + 14, cell * 0.84 + 14, 16);
        ctx.stroke();
      }
      ctx.fillStyle = activeUpdate ? '#e7f6ec' : (isSelected ? '#e8f2ff' : (activeCharge ? '#fdebf0' : (persistCharge ? '#fff0f5' : THEME.surface)));
      ctx.strokeStyle = activeUpdate ? '#16803c' : (isSelected ? THEME.selected : (activeCharge ? '#c8325c' : (persistCharge ? '#b8326a' : THEME.border)));
      ctx.lineWidth = isSelected ? 2.5 : 1.5;
      ctx.beginPath();
      ctx.roundRect(left, top, cell * 0.84, cell * 0.84, 10);
      ctx.fill();
      ctx.stroke();

      for (const edge of ['north', 'east', 'south', 'west']) {
        drawLane(cx, cy, cell, edge, '#a7b2c1', false);
      }
      for (const edge of ['north', 'east', 'south', 'west']) {
        if (laneEnabled(chip.up_mask || 0, edge)) drawLane(cx, cy, cell, edge, '#1677b8', false);
        if (laneEnabled(chip.down_mask || 0, edge)) {
          const downColor = isSourceChip && edge === 'south' ? SOURCE_FPGA_LANE_COLOR : '#c56a00';
          drawLane(cx, cy, cell, edge, downColor, false);
        }
      }

      ctx.fillStyle = THEME.text;
      ctx.font = `${Math.max(13, cell * 0.16)}px ui-monospace, monospace`;
      ctx.textAlign = 'left';
      ctx.textBaseline = 'top';
      ctx.fillText(String(chip.chip_id), left + 8, top + 6);
      if (isSourceChip) {
        ctx.fillStyle = '#1677b8';
        ctx.font = `${Math.max(9, cell * 0.1)}px ui-monospace, monospace`;
        ctx.fillText('SRC', left + 8, top + 24);
      }
      ctx.textBaseline = 'alphabetic';

      if (sharedFifoVisible()) {
        drawSharedFifoCounter(left, top, cell, sharedFifoOccupancyAt(gx, gy, currentTickIndex));
      }
    }
  }

  for (const event of packetEvents || []) {
    if (!isPacketMotionEvent(event)) continue;
    if (!packetCategoryVisible(event.packet_type)) continue;
    drawPacket(event, layout);
    const src = layout.cellCenter(event.src[0], event.src[1]);
    const dst = layout.cellCenter(event.dst[0], event.dst[1]);
    ctx.strokeStyle = 'rgba(22, 128, 60, 0.24)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(src.x, src.y);
    ctx.lineTo(dst.x, dst.y);
    ctx.stroke();
  }

  drawFpga(layout, fpgaTxEvents, fpgaRxEvents);
  updateHud();
}

function draw() {
  const width = canvas.clientWidth || window.innerWidth;
  const height = canvas.clientHeight || window.innerHeight;
  if (currentView === 'chip') {
    drawChipInternalView(width, height);
    return;
  }
  drawNetworkView(width, height);
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
  if (!playback || currentView !== 'network') return;
  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const rows = playback.rows;
  const cols = playback.cols;
  const hudWidth = hudEl?.getBoundingClientRect().width || loadHudWidth();
  const marginLeft = hudWidth + 40;
  const margin = 30;
  const availW = Math.max(200, window.innerWidth - marginLeft - margin);
  const availH = Math.max(200, window.innerHeight - margin * 2);
  const cell = Math.min(availW / cols, availH / rows);
  const gridW = cell * cols;
  const gridH = cell * rows;
  const originX = marginLeft + (availW - gridW) * 0.5;
  const originY = margin + (availH - gridH) * 0.5;
  const layout = {
    cell,
    cellCenter(gx, gy) {
      return {
        x: originX + gx * cell + cell * 0.5,
        y: originY + (rows - 1 - gy) * cell + cell * 0.5,
      };
    },
  };
  const fpgaRect = fpgaLayout(layout);
  if (pointInRect(x, y, fpgaRect)) {
    selectedTarget = { type: 'fpga' };
    draw();
    return;
  }
  if (x < originX || x > originX + gridW || y < originY || y > originY + gridH) {
    selectedTarget = null;
    draw();
    return;
  }
  const gx = Math.floor((x - originX) / cell);
  const gyFromTop = Math.floor((y - originY) / cell);
  const gy = rows - 1 - gyFromTop;
  selectedTarget = { type: 'chip', x: gx, y: gy };
  draw();
}

async function loadPlaybackFromObject(obj, options = {}) {
  playback = obj;
  playbackSourceUrl = options.sourceUrl || null;
  await tryLoadChipDebugForPlayback(playback, playbackSourceUrl);
  if (!chipDebugData && currentView === 'chip') currentView = 'network';
  buildSharedFifoIndex(playback);
  buildPersistentInjectionIndex(playback);
  populateDataPacketMetrics();
  currentTickIndex = 0;
  selectedTarget = null;
  scrubber.max = String(Math.max(0, playback.total_ticks || 0));
  scrubber.value = '0';
  resize();
}

async function loadPlaybackFromUrl(url) {
  const response = await fetch(url, { cache: 'no-store' });
  if (!response.ok) throw new Error(`failed to load ${url}`);
  const obj = await response.json();
  const resolvedUrl = new URL(url, window.location.href).toString();
  await loadPlaybackFromObject(obj, { sourceUrl: resolvedUrl });
}

playPauseBtn.addEventListener('click', togglePlay);
stepBackBtn.addEventListener('click', () => step(-1));
stepForwardBtn.addEventListener('click', () => step(1));
resetBtn.addEventListener('click', () => setTick(0));
scrubber.addEventListener('input', () => setTick(Number(scrubber.value)));
hudResizeHandleEl?.addEventListener('pointerdown', (event) => {
  event.preventDefault();
  hudResizeHandleEl.setPointerCapture?.(event.pointerId);
  startHudResize(event.clientX);
});
canvas.addEventListener('click', handleCanvasClick);
filterConfigWriteEl?.addEventListener('change', draw);
filterConfigReadEl?.addEventListener('change', draw);
filterEventDataEl?.addEventListener('change', draw);
filterMsgPacketEl?.addEventListener('change', draw);
filterOtherPacketEl?.addEventListener('change', draw);
filterSharedFifoEl?.addEventListener('change', draw);
filterPacketLabelsEl?.addEventListener('change', draw);
filterPersistentInjectionEl?.addEventListener('change', draw);

fpgaPopupCloseEl?.addEventListener('click', () => {
  selectedTarget = null;
  draw();
});

showInstructionsBtn?.addEventListener('click', () => {
  instructionsPopupEl?.classList.remove('hidden');
});

instructionsPopupCloseEl?.addEventListener('click', () => {
  instructionsPopupEl?.classList.add('hidden');
});

showRunMetricsBtn?.addEventListener('click', () => {
  runMetricsPopupEl?.classList.remove('hidden');
  renderRunMetricsPopup(playback?.run_summary || null);
});

showNetworkViewBtn?.addEventListener('click', () => setCurrentView('network'));
showChipViewBtn?.addEventListener('click', () => setCurrentView('chip'));
chipZoomOutBtn?.addEventListener('click', () => {
  chipViewZoom = Math.max(0.7, Math.round((chipViewZoom - 0.1) * 10) / 10);
  resize();
});
chipZoomInBtn?.addEventListener('click', () => {
  chipViewZoom = Math.min(1.8, Math.round((chipViewZoom + 0.1) * 10) / 10);
  resize();
});
timelineSpanOutBtn?.addEventListener('click', () => {
  chipTimelineSpanScale = Math.max(0.5, Math.round((chipTimelineSpanScale - 0.25) * 100) / 100);
  updateTimelineSpanStatus();
  draw();
});
timelineSpanInBtn?.addEventListener('click', () => {
  chipTimelineSpanScale = Math.min(4.0, Math.round((chipTimelineSpanScale + 0.25) * 100) / 100);
  updateTimelineSpanStatus();
  draw();
});
laneNorthUpBtn?.addEventListener('click', () => moveLaneTimeline('north', -1));
laneNorthDownBtn?.addEventListener('click', () => moveLaneTimeline('north', 1));
laneWestUpBtn?.addEventListener('click', () => moveLaneTimeline('west', -1));
laneWestDownBtn?.addEventListener('click', () => moveLaneTimeline('west', 1));
laneEastUpBtn?.addEventListener('click', () => moveLaneTimeline('east', -1));
laneEastDownBtn?.addEventListener('click', () => moveLaneTimeline('east', 1));

runMetricsPopupCloseEl?.addEventListener('click', () => {
  runMetricsPopupEl?.classList.add('hidden');
});

fileInput.addEventListener('change', async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  const text = await file.text();
  await loadPlaybackFromObject(JSON.parse(text), { sourceUrl: null });
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

applyHudWidth(loadHudWidth());
updateTimelineSpanStatus();
updateChipViewHudControls();
updateLaneOrderStatus();
resize();
const playbackUrl = new URLSearchParams(window.location.search).get('playback') || '../../../build/larpix_2x2_msg_probe/live_event_2x2_msg_probe.json';
loadPlaybackFromUrl(playbackUrl).catch((error) => {
  scenarioEl.textContent = 'Scenario: failed to load sample';
  selectionEl.textContent = error.message;
  fpgaPopupEl?.classList.add('hidden');
  runMetricsPopupEl?.classList.add('hidden');
});
requestAnimationFrame(animate);
