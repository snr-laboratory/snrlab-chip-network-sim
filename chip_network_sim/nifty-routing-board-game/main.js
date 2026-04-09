const canvas = document.getElementById('c');
const hudMode = document.getElementById('mode');
const gl = canvas.getContext('webgl2', {antialias: true});
if (!gl) throw new Error('Graphics support required');

let wasm, memory;
const textDec = new TextDecoder();
const textEnc = new TextEncoder();

// Handle pools
const shaders = [];
const programs = [];
const buffers = [];
const uniforms = [];
const vaos = [];
const textures = [];

// Heap views
const u8  = () => new Uint8Array(memory.buffer);
const f32 = () => new Float32Array(memory.buffer);

// Helpers
function cstr(ptr) {
  const bytes = u8();
  let end = ptr;
  while (bytes[end] !== 0) ++end;
  return textDec.decode(bytes.subarray(ptr, end));
}
function view(ptr, byteLen) { return u8().subarray(ptr, ptr + byteLen); }

function resize() {
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const w = Math.floor(canvas.clientWidth * dpr);
  const h = Math.floor(canvas.clientHeight * dpr);
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w; canvas.height = h;
    gl.viewport(0, 0, w, h);
    if (wasm) wasm.exports.set_viewport(w, h);
  }
}
window.addEventListener('resize', resize);

const imports = {
  env: {
    // Debug + small helpers
    debug_log: (ptr) => console.log(cstr(ptr)),
    set_mode_label: (ptr) => { if (hudMode) hudMode.textContent = cstr(ptr); },

    // no libc shims required; compiled with -ffreestanding -fno-builtin

    // Init
    js_init() {
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
      resize();
      gl.clearColor(0.07, 0.07, 0.08, 1.0);
      gl.clear(gl.COLOR_BUFFER_BIT);
    },

    // Math fallbacks if LLVM emits calls
    sinf: x => Math.sin(x),
    cosf: x => Math.cos(x),
    tanf: x => Math.tan(x),

    // Shaders
    gl_create_shader: (type) => { const s = gl.createShader(type); shaders.push(s); return shaders.length - 1; },
    gl_shader_source: (sid, srcPtr) => { gl.shaderSource(shaders[sid], cstr(srcPtr)); },
    gl_compile_shader: (sid) => { gl.compileShader(shaders[sid]); },
    gl_get_shader_iv: (sid, pname) => gl.getShaderParameter(shaders[sid], pname) ? 1 : 0,
    gl_get_shader_info_log: (sid, outPtr, maxLen) => {
      const log = gl.getShaderInfoLog(shaders[sid]) || '';
      const enc = textEnc.encode(log);
      const dst = u8();
      const n = Math.min(enc.length, maxLen - 1);
      dst.set(enc.subarray(0, n), outPtr);
      dst[outPtr + n] = 0;
    },

    // Program
    gl_create_program: () => { const p = gl.createProgram(); programs.push(p); return programs.length - 1; },
    gl_attach_shader: (pid, sid) => { gl.attachShader(programs[pid], shaders[sid]); },
    gl_link_program: (pid) => { gl.linkProgram(programs[pid]); },
    gl_get_program_iv: (pid, pname) => gl.getProgramParameter(programs[pid], pname) ? 1 : 0,
    gl_get_program_info_log: (pid, outPtr, maxLen) => {
      const log = gl.getProgramInfoLog(programs[pid]) || '';
      const enc = textEnc.encode(log);
      const dst = u8();
      const n = Math.min(enc.length, maxLen - 1);
      dst.set(enc.subarray(0, n), outPtr);
      dst[outPtr + n] = 0;
    },
    gl_use_program: (pid) => { gl.useProgram(programs[pid]); },
    gl_get_attrib_location: (pid, namePtr) => gl.getAttribLocation(programs[pid], cstr(namePtr)),

    // Buffers + attributes
    gl_gen_buffer: () => { const b = gl.createBuffer(); buffers.push(b); return buffers.length - 1; },
    gl_bind_buffer: (target, bid) => { gl.bindBuffer(target, buffers[bid]); },
    gl_buffer_data: (target, srcPtr, byteLen, usage) => { gl.bufferData(target, view(srcPtr, byteLen), usage); },
    gl_enable_vertex_attrib_array: (loc) => { gl.enableVertexAttribArray(loc); },
    gl_vertex_attrib_pointer: (loc, size, type, normalized, stride, offset) => {
      gl.vertexAttribPointer(loc, size, type, !!normalized, stride, offset);
    },

    // VAO
    gl_create_vertex_array: () => { const v = gl.createVertexArray(); vaos.push(v); return vaos.length - 1; },
    gl_bind_vertex_array: (vid) => { gl.bindVertexArray(vid >= 0 ? vaos[vid] : null); },

    // Uniforms
    gl_get_uniform_location: (pid, namePtr) => {
      const u = gl.getUniformLocation(programs[pid], cstr(namePtr));
      uniforms.push(u); return uniforms.length - 1;
    },
    gl_uniform_matrix4fv: (uid, transpose, ptr) => {
      gl.uniformMatrix4fv(uniforms[uid], !!transpose, f32().subarray(ptr>>2, (ptr>>2) + 16));
    },
    gl_uniform1i: (uid, x) => { gl.uniform1i(uniforms[uid], x); },
    gl_uniform3f: (uid, x, y, z) => { gl.uniform3f(uniforms[uid], x, y, z); },
    gl_uniform4f: (uid, x, y, z, w) => { gl.uniform4f(uniforms[uid], x, y, z, w); },

    // State + draw
    gl_viewport: (x, y, w, h) => { gl.viewport(x, y, w, h); },
    gl_clear_color: (r,g,b,a) => { gl.clearColor(r,g,b,a); },
        gl_clear: (mask) => { gl.clear(mask); },
        gl_draw_elements: (mode, count, type, offset) => { gl.drawElements(mode, count, type, offset); },
        gl_draw_arrays: (mode, first, count) => { gl.drawArrays(mode, first, count); },

    // Constants passthrough (for completeness if needed)
    now_ms: () => performance.now(),
  }
};

// Load and start (with fallback if server lacks correct MIME)
let instance;
try {
  if (WebAssembly.instantiateStreaming) {
    const resp = await fetch('main.wasm');
    ({instance} = await WebAssembly.instantiateStreaming(resp, { env: imports.env }));
  } else {
    const resp = await fetch('main.wasm');
    const buf = await resp.arrayBuffer();
    ({instance} = await WebAssembly.instantiate(buf, { env: imports.env }));
  }
} catch (e) {
  const resp = await fetch('main.wasm');
  const buf = await resp.arrayBuffer();
  ({instance} = await WebAssembly.instantiate(buf, { env: imports.env }));
}
wasm = instance;
memory = wasm.exports.memory;

imports.env.js_init();
// Ensure WASM receives initial viewport size
resize();
wasm.exports.init();

function applyGameConfig(cfg) {
  if (!wasm || !wasm.exports.set_game_config) return;
  const w = Number.isFinite(cfg.width) ? cfg.width : 0;
  const h = Number.isFinite(cfg.height) ? cfg.height : 0;
  const outX = Number.isFinite(cfg.outX) ? cfg.outX : -1;
  const outY = Number.isFinite(cfg.outY) ? cfg.outY : -1;
  const seed = Number.isFinite(cfg.seed) ? cfg.seed : 0;
  const history = Number.isFinite(cfg.history) ? cfg.history : 0;
  const ok = wasm.exports.set_game_config(w, h, outX, outY, seed, history);
  if (!ok) console.warn('set_game_config failed', cfg);
}

function applyRoutingPattern(kind) {
  if (!wasm || !wasm.exports.set_routing_pattern) return;
  wasm.exports.set_routing_pattern(kind | 0);
}

const params = new URLSearchParams(window.location.search);
const parsed = {
  width: parseInt(params.get('w'), 10),
  height: parseInt(params.get('h'), 10),
  outX: parseInt(params.get('outx'), 10),
  outY: parseInt(params.get('outy'), 10),
  seed: parseInt(params.get('seed'), 10),
  history: parseInt(params.get('history'), 10),
};
const hasAnyParam = ['w','h','outx','outy','seed','history'].some(k => params.has(k));
if (hasAnyParam) applyGameConfig(parsed);
window.setGameConfig = applyGameConfig;
window.setRoutingPattern = applyRoutingPattern;

function sendPointer(e, type) {
  if (!wasm) return;
  const rect = canvas.getBoundingClientRect();
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const x = Math.floor((e.clientX - rect.left) * dpr);
  const y = Math.floor((e.clientY - rect.top) * dpr);
  const buttons = e.buttons || (type===1?1:0); // 1 down move up mapping
  const mods = (e.shiftKey?1:0) | (e.ctrlKey?2:0) | (e.altKey?4:0) | (e.metaKey?8:0);
  wasm.exports.on_pointer(x, y, type, buttons, mods);
}

canvas.addEventListener('mousedown', e => {
  // prevent text selection and default behaviors for all buttons
  e.preventDefault();
  if (e.button === 2) { /* right button */ e.preventDefault(); }
  sendPointer(e, 1);
});
canvas.addEventListener('mousemove', e => sendPointer(e, 0));
window.addEventListener('mouseup', e => sendPointer(e, 2));
canvas.addEventListener('contextmenu', e => { e.preventDefault(); e.stopPropagation(); });
canvas.addEventListener('auxclick', e => { if (e.button===2){ e.preventDefault(); e.stopPropagation(); }});

function keyCodeFor(e) {
  const c = e.code;
  if (c === 'Space') return 32;
  // no Tab handling; let browser use it
  if (c.startsWith('Key') && c.length === 4) return c.charCodeAt(3); // KeyR -> 'R'
  if (c.startsWith('Digit') && c.length === 6) return c.charCodeAt(5); // Digit0..9 -> '0'..'9'
  if (c.startsWith('Numpad') && c.length === 7) return c.charCodeAt(6); // Numpad0..9
  if (c === 'ArrowUp') return 38;
  if (c === 'ArrowDown') return 40;
  if (c === 'ArrowLeft') return 37;
  if (c === 'ArrowRight') return 39;
  return 0;
}
window.addEventListener('keydown', e => {
  if (!wasm) return;
  const code = keyCodeFor(e);
  if (code === 32) { e.preventDefault(); e.stopPropagation(); }
  if (code) wasm.exports.on_key(code, 1);
}, {capture:true});
window.addEventListener('keyup', e => {
  if (!wasm) return;
  const code = keyCodeFor(e);
  if (code) wasm.exports.on_key(code, 0);
}, {capture:true});

let tPrev = performance.now();
function tick(tNow) {
  const dt = (tNow - tPrev) * 0.001;
  tPrev = tNow;
  wasm.exports.frame(dt);
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
