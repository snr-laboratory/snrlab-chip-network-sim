// Recorded RTL decisions and physical UART packets are separate visual layers.
const directions = ['N', 'S', 'E', 'W'];
const edges = ['north', 'south', 'east', 'west'];
const masks = [8, 2, 4, 1];
const selectedOrange = '#ec7800';
const routeChangeTicks = 1000;
const cache = new WeakMap();
let panel;

function indexFor(playback) {
  if (!cache.has(playback)) {
    const byChip = new Map();
    for (const row of playback.snn_decisions || []) {
      if (!byChip.has(row.runtime_id)) byChip.set(row.runtime_id, []);
      byChip.get(row.runtime_id).push(row);
    }
    for (const rows of byChip.values()) rows.sort((a,b) => a.tick-b.tick);
    cache.set(playback, byChip);
  }
  return cache.get(playback);
}

function atTick(rows, tick) {
  let lo=0, hi=rows.length;
  while (lo<hi) { const mid=(lo+hi)>>1; if (rows[mid].tick<=tick) lo=mid+1; else hi=mid; }
  return lo ? rows[lo-1] : null;
}

function maskName(mask) {
  return masks.map((bit,i) => mask & bit ? directions[i] : '').filter(Boolean).join('+') || 'none';
}

// Highlight only applied lane changes, not the initial decision or a changed
// raw action that leaves the applied lane unchanged. Scrubbing is deterministic.
export function snnRouteChangeAt(playback,x,y,tick) {
  if (!playback?.snn_decisions || (playback.fixed_sink_runtimes || []).includes(y*playback.cols+x)) return null;
  const row=atTick(indexFor(playback).get(y*playback.cols+x) || [],tick);
  return row?.route_changed && tick-row.tick<routeChangeTicks ? row : null;
}

export function drawSnnRoute(ctx, playback, x,y,cx,cy,cell,tick,drawLane) {
  if (!playback?.snn_decisions) return;
  if ((playback.fixed_sink_runtimes || []).includes(y*playback.cols+x)) {
    drawLane(cx,cy,cell,'north',selectedOrange,false);
    ctx.save();ctx.fillStyle='#985000';ctx.textAlign='right';ctx.textBaseline='top';
    ctx.font=`bold ${Math.max(8,cell*.09)}px ui-monospace,monospace`;
    ctx.fillText('FIX N',cx+cell*.34,cy-cell*.34);ctx.restore();return;
  }
  const row=atTick(indexFor(playback).get(y*playback.cols+x) || [],tick);
  if (!row) return;
  const color=selectedOrange;
  for (let i=0;i<4;i++) if (row.piso_mask & masks[i]) drawLane(cx,cy,cell,edges[i],color,false);
  ctx.save();
  ctx.fillStyle=color;
  ctx.font=`bold ${Math.max(8,cell*.105)}px ui-monospace,monospace`;
  ctx.textAlign='right'; ctx.textBaseline='top';
  const badge=row.fallback_used ? `${directions[row.action]}→${maskName(row.piso_mask)}*` : maskName(row.piso_mask);
  ctx.fillText(badge,cx+cell*.34,cy-cell*.34);
  if (snnRouteChangeAt(playback,x,y,tick)) {
    ctx.fillStyle='#075e58';ctx.textAlign='center';ctx.textBaseline='middle';
    ctx.font=`bold ${Math.max(8,cell*.085)}px sans-serif`;
    ctx.fillText('ROUTE CHANGED',cx,cy,cell*.72);
  }
  ctx.restore();
}

function buildPanel() {
  const node=document.createElement('section');node.id='snnPanel';
  node.style.cssText='padding:10px 0;border-top:1px solid #cad5df;margin-top:10px;font-size:12px;line-height:1.45';
  node.innerHTML=`<b>SNN routing decisions</b>
    <div><span class="swatch down"></span>Light orange: enabled downstream direction</div>
    <div><span class="swatch selected-down"></span>Bright orange: current applied downstream selection</div>
    <div>The selection uses the SNN action, fallback, or a fixed sink output. E→W* identifies fallback; FIX N identifies a fixed North/FPGA sink.</div>
    <div>Arrow color shows routing preference. Moving dots are actual UART packets.</div>
    <div><span class="swatch snn-route-change"></span><b>Teal chip fill + ROUTE CHANGED:</b> a completed SNN decision changed the applied lane, including fallback.</div>
    <div id="snnStatus" style="margin:8px 0"></div>
    <div class="controls"><button id="snnPrev">Previous route change</button><button id="snnNext">Next route change</button></div>
    <b>Selected-chip history · entire run</b>
    <canvas id="snnHistory" width="380" height="170" style="width:100%;background:white;border:1px solid #d7e0e9" aria-label="Selected chip: applied lane and shared FIFO occupancy over the entire run"></canvas>
    <div style="font-size:11px"><b>Horizontal axis:</b> simulation ticks, from start to finish.<br><b>Top orange strip:</b> applied output (N/S/E/W); gray means the initial configured mask before the first decision.<br><b>Blue line:</b> packets in this chip's shared FIFO, from 0 to capacity. Higher means a fuller buffer.<br><b>Pink vertical line:</b> current playback tick. Future history remains visible. Click another chip to change this plot.</div>`;
  const selection=document.getElementById('selection');
  selection.parentNode.insertBefore(node,selection.nextSibling);
  return node;
}

function drawHistory(canvas,playback,rows,id,tick) {
  const ctx=canvas.getContext('2d'), w=canvas.width, h=canvas.height;
  ctx.clearRect(0,0,w,h);
  const left=42,right=w-12,span=playback.total_ticks || 1;
  const x=t=>left+(right-left)*t/span;
  ctx.font='11px sans-serif';ctx.fillStyle='#304255';ctx.fillText('route',3,24);
  if (!(playback.fixed_sink_runtimes || []).includes(id)) {
    const end=rows[0]?.tick ?? span;
    ctx.fillStyle='#dce3ea';ctx.fillRect(left,12,x(end)-left,18);
    if (x(end)-left>62) {ctx.fillStyle='#304255';ctx.fillText('configured',left+3,25);}
  }
  for (let i=0;i<rows.length;i++) {
    const row=rows[i],end=rows[i+1]?.tick ?? span;
    ctx.fillStyle=selectedOrange;
    ctx.fillRect(x(row.tick),12,Math.max(1,x(end)-x(row.tick)),18);
    if (x(end)-x(row.tick)>16) {ctx.fillStyle='white';ctx.fillText(maskName(row.piso_mask),x(row.tick)+3,25);}
  }
  if ((playback.fixed_sink_runtimes || []).includes(id)) {
    ctx.fillStyle=selectedOrange;ctx.fillRect(left,12,right-left,18);
    ctx.fillStyle='white';ctx.fillText('North → FPGA (fixed)',left+5,25);
  }
  const capacity=playback.shared_fifo_capacity || 2048;
  const top=48,bottom=138;
  ctx.strokeStyle='#ccd4dc';ctx.beginPath();ctx.moveTo(left,top);ctx.lineTo(left,bottom);ctx.lineTo(right,bottom);ctx.stroke();
  ctx.fillStyle='#304255';ctx.fillText(String(capacity),2,top+4);ctx.fillText('0',25,bottom+4);
  ctx.fillText('FIFO',3,95);
  const samples=playback._sharedFifoByChip?.get(`${id%playback.cols},${Math.floor(id/playback.cols)}`) || [];
  ctx.strokeStyle='#5476c3';ctx.lineWidth=1.4;ctx.beginPath();
  let last=0;ctx.moveTo(left,bottom);
  for(const sample of samples) {ctx.lineTo(x(sample.tick),bottom-last/capacity*(bottom-top));last=sample.shared_fifo_occupancy;ctx.lineTo(x(sample.tick),bottom-last/capacity*(bottom-top));}
  ctx.lineTo(right,bottom-last/capacity*(bottom-top));ctx.stroke();
  ctx.fillStyle='#304255';ctx.fillText('0',left,155);ctx.fillText(String(span),right-42,155);ctx.fillText('tick',w/2,166);
  ctx.strokeStyle='#c33a55';ctx.lineWidth=1;ctx.beginPath();ctx.moveTo(x(tick),4);ctx.lineTo(x(tick),bottom);ctx.stroke();
}

export function updateSnnPanel(playback,tick,selected,setTick) {
  if (!playback.snn_decisions) { if(panel) panel.hidden=true; return; }
  panel=panel || buildPanel();panel.hidden=false;
  const id=selected?.type==='chip' ? selected.y*playback.cols+selected.x : playback.snn_focus_runtime;
  const rows=indexFor(playback).get(id) || [], row=atTick(rows,tick);
  const x=id%playback.cols,y=Math.floor(id/playback.cols);
  const changes=rows.filter(r=>r.route_changed);
  const node=panel.querySelector('#snnStatus');
  const initial=(playback.initial_chips || []).find(c=>c.x===x && c.y===y);
  const title=`Chip ${initial?.chip_id ?? id} · row ${playback.rows-1-y}, col ${x}`;
  node.innerHTML=row ? `<b>${title}</b><br>Decision at tick ${row.tick}<br>Raw action: <b>${directions[row.action]}</b> · applied: <b>${maskName(row.piso_mask)}</b>${row.fallback_used ? ' (fallback)' : ''}<br>Applied lane changes: ${changes.filter(r=>r.tick<=tick).length}<br>Latched local occupancy: ${(row.local_observation/6).toFixed(2)}<br>Latched pressures N/S/E/W: ${row.features.slice(2,6).map(v=>(v/6).toFixed(2)).join(' / ')}` : `<b>${title}</b><br>Awaiting first completed inference; configured downstream mask applies.`;
  if ((playback.fixed_sink_runtimes || []).includes(id))
    node.innerHTML=`<b>${title}</b><br>Fixed North → FPGA output.<br>SNN routing is disabled on this chip. Its configured mask controls transmission from the start.`;
  const previous=changes.filter(r=>r.tick<tick).at(-1), next=changes.find(r=>r.tick>tick);
  const prev=panel.querySelector('#snnPrev'),nxt=panel.querySelector('#snnNext');
  prev.disabled=!previous;nxt.disabled=!next;
  prev.onclick=()=>previous && setTick(previous.tick);
  nxt.onclick=()=>next && setTick(next.tick);
  drawHistory(panel.querySelector('#snnHistory'),playback,rows,id,tick);
}
