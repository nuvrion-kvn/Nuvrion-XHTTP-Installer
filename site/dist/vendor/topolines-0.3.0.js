// src/color.ts
var ctx2d;
var cache = /* @__PURE__ */ new Map();
var CACHE_LIMIT = 512;
function devWarn(msg) {
  const g = globalThis;
  if (g.process?.env?.NODE_ENV === "production") return;
  if (typeof console !== "undefined") console.warn(msg);
}
function parseColor(c) {
  const hit = cache.get(c);
  if (hit) return [hit[0], hit[1], hit[2]];
  if (ctx2d === void 0) {
    if (typeof document !== "undefined") {
      const canvas = document.createElement("canvas");
      canvas.width = 1;
      canvas.height = 1;
      ctx2d = canvas.getContext("2d", { willReadFrequently: true });
    } else {
      ctx2d = null;
    }
  }
  if (!ctx2d) {
    devWarn(`topolines: no 2D canvas available to parse color "${c}"`);
    return [1, 1, 1];
  }
  ctx2d.fillStyle = "#000";
  ctx2d.fillStyle = c;
  const first = ctx2d.fillStyle;
  ctx2d.fillStyle = "#fff";
  ctx2d.fillStyle = c;
  let rgb;
  if (ctx2d.fillStyle !== first) {
    devWarn(`topolines: unrecognized color "${c}", falling back to white`);
    rgb = [1, 1, 1];
  } else {
    ctx2d.clearRect(0, 0, 1, 1);
    ctx2d.fillRect(0, 0, 1, 1);
    const d = ctx2d.getImageData(0, 0, 1, 1).data;
    rgb = [d[0] / 255, d[1] / 255, d[2] / 255];
  }
  if (cache.size >= CACHE_LIMIT) cache.clear();
  cache.set(c, rgb);
  return [rgb[0], rgb[1], rgb[2]];
}

// src/seed.ts
function seedOffset(seed) {
  let a = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    a ^= seed.charCodeAt(i);
    a = Math.imul(a, 16777619);
  }
  const x = (a >>> 0) % 1e4 / 10;
  const y = (Math.imul(a, 48271) >>> 0) % 1e4 / 10;
  return [x, y];
}
function randomSeed() {
  return Math.random().toString(36).slice(2, 10);
}

// src/shader.ts
var VERT = `
precision highp float;
attribute vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
`;
var FRAG = `
#extension GL_OES_standard_derivatives : enable
precision highp float;

uniform vec2  uRes;
uniform float uTime;
uniform vec2  uSeed;
uniform float uScale;
uniform float uLevels;
uniform float uLineWidth;
uniform float uOpacity;
uniform vec3  uColor;
uniform vec2  uDrift;
uniform float uWarp;
uniform vec2  uScrollOff;
uniform vec2  uMouse;        // cursor in the pre-offset stBase space
uniform float uMouseBump;    // eased bump height (0 disables the feature)
uniform float uMouseRadius;  // bump falloff radius, in stBase units

// Simplex noise \u2014 Ashima Arts / Stefan Gustavson, MIT licensed.
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
  const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
  const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

  vec3 i  = floor(v + dot(v, C.yyy));
  vec3 x0 = v - i + dot(i, C.xxx);

  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min(g.xyz, l.zxy);
  vec3 i2 = max(g.xyz, l.zxy);

  vec3 x1 = x0 - i1 + C.xxx;
  vec3 x2 = x0 - i2 + C.yyy;
  vec3 x3 = x0 - D.yyy;

  i = mod289(i);
  vec4 p = permute(permute(permute(
             i.z + vec4(0.0, i1.z, i2.z, 1.0))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0))
           + i.x + vec4(0.0, i1.x, i2.x, 1.0));

  float n_ = 0.142857142857;
  vec3 ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_);

  vec4 x = x_ * ns.x + ns.yyyy;
  vec4 y = y_ * ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4(x.xy, y.xy);
  vec4 b1 = vec4(x.zw, y.zw);

  vec4 s0 = floor(b0) * 2.0 + 1.0;
  vec4 s1 = floor(b1) * 2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
  vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

  vec3 p0 = vec3(a0.xy, h.x);
  vec3 p1 = vec3(a0.zw, h.y);
  vec3 p2 = vec3(a1.xy, h.z);
  vec3 p3 = vec3(a1.zw, h.w);

  vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
  p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

  vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
  m = m * m;
  return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// Two octaves. One is too glassy, three gets fussy and crowded.
float fbm(vec3 p) {
  return (snoise(p) + 0.5 * snoise(p * 2.0)) / 1.5;
}

void main() {
  // Normalize by the shorter edge: aspect-correct, and the pattern scales with
  // the element instead of stretching. stBase is the pre-offset, scale-applied
  // space that uMouse is expressed in.
  vec2 stN = (gl_FragCoord.xy - 0.5 * uRes) / min(uRes.x, uRes.y);
  vec2 stBase = stN * uScale;
  vec2 st = stBase + uSeed + uDrift * uTime + uScrollOff;

  // Domain warp \u2014 bends the field so the loops meander like real terrain
  // rather than reading as regular concentric blobs.
  if (uWarp > 0.0) {
    vec2 q = vec2(
      fbm(vec3(st, uTime * 0.6)),
      fbm(vec3(st + 5.2, uTime * 0.6))
    );
    st += q * uWarp;
  }

  float v = fbm(vec3(st, uTime));

  // Mouse bump \u2014 raise the field with a soft Gaussian around the cursor so the
  // contour rings bloom outward. d is measured in the pre-offset stBase space,
  // the same space uMouse lives in.
  vec2 d = stBase - uMouse;
  v += uMouseBump * exp(-dot(d, d) / (uMouseRadius * uMouseRadius));

  float c = v * uLevels;

  // fwidth() converts "distance to the nearest iso-level" into screen pixels,
  // so every line draws at the same width regardless of how steep the field is.
  float w = fwidth(c);
  float dist = 0.5 - abs(fract(c) - 0.5);
  float dd = dist / max(w, 1e-5);

  float line = 1.0 - smoothstep(uLineWidth * 0.5 - 0.5, uLineWidth * 0.5 + 0.5, dd);

  // Where the field is so steep that bands fall below one pixel, fade out
  // instead of aliasing into moir\xE9. Typical w here is ~0.02, so this only
  // engages in genuinely degenerate regions.
  line *= 1.0 - smoothstep(0.6, 1.4, w);

  float a = line * uOpacity;
  gl_FragColor = vec4(uColor * a, a); // premultiplied
}
`;
function buildProgram(gl) {
  const compile = (type, src) => {
    const s = gl.createShader(type);
    if (!s) return null;
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      console.error("topolines shader:", gl.getShaderInfoLog(s));
      gl.deleteShader(s);
      return null;
    }
    return s;
  };
  const vs = compile(gl.VERTEX_SHADER, VERT);
  const fs = compile(gl.FRAGMENT_SHADER, FRAG);
  if (!vs || !fs) return null;
  const p = gl.createProgram();
  if (!p) return null;
  gl.attachShader(p, vs);
  gl.attachShader(p, fs);
  gl.linkProgram(p);
  gl.deleteShader(vs);
  gl.deleteShader(fs);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
    console.error("topolines link:", gl.getProgramInfoLog(p));
    return null;
  }
  return p;
}

// src/engine.ts
var fri = (k, dt) => 1 - Math.pow(1 - k, dt * 60);
var DEFAULTS = {
  seed: "topo",
  speed: 0.012,
  scale: 1.15,
  levels: 11,
  lineWidth: 1.2,
  opacity: 0.16,
  color: "#C3D82C",
  drift: [4e-3, 2e-3],
  warp: 0.18,
  scrollPan: [0, 0],
  scrollEase: 0.18,
  maxDpr: 1.5,
  interactive: false,
  mouseStrength: 0.35,
  mouseRadius: 0.35
};
var NULLABLE = /* @__PURE__ */ new Set([
  "colorStops",
  "getPanScroll",
  "getProgress"
]);
function applyPatch(base, patch) {
  Object.keys(patch).forEach((k) => {
    const v = patch[k];
    if (v !== void 0 || NULLABLE.has(k)) {
      base[k] = v;
    }
  });
}
var clamp01 = (n) => Math.min(1, Math.max(0, n));
var TopoField = class {
  constructor(host, options = {}) {
    /** False when WebGL/derivatives are unavailable — the constructor then
     *  mounted nothing and every method is a no-op. */
    this.ok = false;
    /** True while the GL context is lost. The canvas stays mounted and the field
     *  rebuilds itself and resumes when the browser restores the context. */
    this.contextLost = false;
    // Runtime state.
    this.width = 0;
    this.height = 0;
    this.clock = 0;
    // accumulated animation time, independent of wall clock
    this.last = 0;
    this.raf = 0;
    this.visible = true;
    this.running = false;
    this.destroyed = false;
    this.seedX = 0;
    this.seedY = 0;
    // Mouse state. `client*` is the raw viewport position from the last event,
    // `mouseN*` its normalized (scale-free, DPR-free) form, `mouse*` the smoothed
    // value in stBase space, and `bump` the eased strength sent to the shader.
    this.pointerBound = false;
    this.clientX = 0;
    this.clientY = 0;
    this.mouseNX = 0;
    this.mouseNY = 0;
    this.mouseX = 0;
    this.mouseY = 0;
    /** The canvas rect, cached until something that can move it fires. Null
     *  means "read it next time it is actually needed". */
    this.rect = null;
    this.rectAge = 0;
    /** The eased scroll position the pan is drawn from, and whether it has been
     *  seeded from the real one yet. */
    this.pan = 0;
    this.panReady = false;
    this.bump = 0;
    this.pointerInside = false;
    this.start = () => {
      if (this.running || !this.visible || this.contextLost) return;
      if (this.reduceMotion.matches) return;
      this.running = true;
      this.last = performance.now();
      this.raf = requestAnimationFrame(this.frame);
    };
    this.stop = () => {
      this.running = false;
      cancelAnimationFrame(this.raf);
    };
    this.frame = (now) => {
      const dt = Math.min((now - this.last) / 1e3, 0.1);
      this.last = now;
      this.clock += dt * this.live.speed;
      this.tickMouse(dt);
      this.tickPan(dt);
      this.render();
      this.raf = requestAnimationFrame(this.frame);
    };
    this.render = () => {
      if (this.contextLost) return;
      const p = this.live;
      const gl = this.gl;
      if (!this.panReady) this.tickPan(0);
      let r;
      let g;
      let b;
      let alpha;
      const s = p.colorStops;
      if (s && s.length) {
        const prog = this.progress();
        const first = s[0];
        const last = s[s.length - 1];
        if (prog <= first.at) {
          [r, g, b] = parseColor(first.color);
          alpha = first.opacity;
        } else if (prog >= last.at) {
          [r, g, b] = parseColor(last.color);
          alpha = last.opacity;
        } else {
          let lo = first;
          let hi = last;
          for (let i = 0; i < s.length - 1; i++) {
            if (prog >= s[i].at && prog <= s[i + 1].at) {
              lo = s[i];
              hi = s[i + 1];
              break;
            }
          }
          const t = (prog - lo.at) / (hi.at - lo.at || 1e-6);
          const ca = parseColor(lo.color);
          const cb = parseColor(hi.color);
          r = ca[0] + (cb[0] - ca[0]) * t;
          g = ca[1] + (cb[1] - ca[1]) * t;
          b = ca[2] + (cb[2] - ca[2]) * t;
          alpha = lo.opacity + (hi.opacity - lo.opacity) * t;
        }
      } else {
        [r, g, b] = parseColor(p.color);
        alpha = p.opacity;
      }
      gl.uniform2f(this.uRes, this.width, this.height);
      gl.uniform1f(this.uTime, this.clock);
      gl.uniform2f(this.uSeed, this.seedX, this.seedY);
      gl.uniform1f(this.uScale, p.scale);
      gl.uniform1f(this.uLevels, p.levels);
      gl.uniform1f(this.uLineWidth, p.lineWidth);
      gl.uniform1f(this.uOpacity, alpha);
      gl.uniform3f(this.uColor, r, g, b);
      gl.uniform2f(this.uDrift, p.drift[0], p.drift[1]);
      gl.uniform1f(this.uWarp, p.warp);
      const sy2 = this.pan;
      gl.uniform2f(this.uScrollOff, sy2 * p.scrollPan[0], -sy2 * p.scrollPan[1]);
      gl.uniform2f(this.uMouse, this.mouseX, this.mouseY);
      gl.uniform1f(this.uMouseBump, this.bump);
      gl.uniform1f(this.uMouseRadius, Math.max(p.mouseRadius, 1e-3));
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    };
    this.onContextLost = (e) => {
      e.preventDefault();
      this.contextLost = true;
      this.stop();
    };
    this.onContextRestored = () => {
      if (this.destroyed) return;
      this.contextLost = false;
      if (!this.setupGL()) {
        this.contextLost = true;
        return;
      }
      this.width = 0;
      this.height = 0;
      this.resize();
      this.render();
      this.start();
    };
    this.onVisibility = () => {
      if (document.hidden) this.stop();
      else this.start();
    };
    this.onMotionChange = () => {
      this.stop();
      this.resize();
      this.render();
      this.start();
    };
    this.onDprChange = () => {
      this.watchDpr();
      this.rect = null;
      this.resize();
      if (!this.running) this.render();
    };
    /** Scrolling moves the element without resizing it, so it is the third and
     *  last thing that can invalidate the cached rect. Passive, and it does one
     *  assignment - the read itself is deferred to the frame that needs it. */
    this.onScroll = () => {
      this.rect = null;
    };
    this.onPointerMove = (e) => {
      this.pointerInside = true;
      this.clientX = e.clientX;
      this.clientY = e.clientY;
    };
    this.onPointerLeave = () => {
      this.pointerInside = false;
    };
    this.host = host;
    this.live = { ...DEFAULTS };
    applyPatch(this.live, options);
    const [sx, sy] = seedOffset(this.live.seed);
    this.seedX = sx;
    this.seedY = sy;
    const canvas = document.createElement("canvas");
    canvas.style.cssText = "display:block;width:100%;height:100%";
    host.appendChild(canvas);
    this.canvas = canvas;
    const gl = canvas.getContext("webgl", {
      alpha: true,
      antialias: false,
      depth: false,
      stencil: false,
      premultipliedAlpha: true,
      // preserveDrawingBuffer stays false: snapshot() draws and reads in the
      // same tick, so we get correct pixels without the perf cost.
      powerPreference: "low-power"
    });
    const bail = () => {
      gl?.getExtension("WEBGL_lose_context")?.loseContext();
      if (canvas.parentNode === host) host.removeChild(canvas);
      this.ok = false;
    };
    if (!gl) {
      bail();
      return;
    }
    this.gl = gl;
    if (!this.setupGL()) {
      bail();
      return;
    }
    this.reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    this.resize();
    this.io = new IntersectionObserver(([entry]) => {
      this.visible = entry.isIntersecting;
      if (this.visible) this.start();
      else this.stop();
    });
    this.io.observe(canvas);
    this.ro = new ResizeObserver(() => {
      this.rect = null;
      this.resize();
      if (!this.running) this.render();
    });
    this.ro.observe(canvas);
    canvas.addEventListener("webglcontextlost", this.onContextLost);
    canvas.addEventListener("webglcontextrestored", this.onContextRestored);
    document.addEventListener("visibilitychange", this.onVisibility);
    this.reduceMotion.addEventListener("change", this.onMotionChange);
    this.watchDpr();
    if (this.live.interactive) this.bindPointer();
    this.ok = true;
    this.render();
    this.start();
  }
  // -------------------------------------------------------------- public API
  /** Live-update options. Never rebuilds the program or context. */
  setOptions(patch) {
    if (patch.seed !== void 0 && patch.seed !== this.live.seed) {
      const [sx, sy] = seedOffset(patch.seed);
      this.seedX = sx;
      this.seedY = sy;
    }
    const wasInteractive = this.live.interactive;
    applyPatch(this.live, patch);
    if (this.ok && this.live.interactive !== wasInteractive) {
      if (this.live.interactive) {
        this.bindPointer();
      } else {
        this.unbindPointer();
        this.pointerInside = false;
      }
    }
    if (this.ok && !this.running) {
      this.resize();
      this.render();
    }
  }
  play() {
    if (this.ok) this.start();
  }
  pause() {
    if (this.ok) this.stop();
  }
  /** Set the accumulated animation time directly. */
  setClock(t) {
    this.clock = t;
    if (this.ok && !this.running) this.render();
  }
  /** Render one frame and read it back as a data URL. Returns null when not ok
   *  or while the context is lost. Draw-then-read in the same tick is required
   *  because the context is not preserveDrawingBuffer. */
  snapshot() {
    if (!this.ok || this.contextLost) return null;
    this.resize();
    this.render();
    return this.canvas.toDataURL("image/png");
  }
  /** Full teardown: stop the loop, disconnect observers, remove listeners,
   *  delete GL objects, force the context loss, drop the canvas. */
  destroy() {
    if (!this.ok) return;
    this.destroyed = true;
    this.stop();
    this.io?.disconnect();
    this.ro?.disconnect();
    this.dprQuery?.removeEventListener("change", this.onDprChange);
    this.canvas.removeEventListener("webglcontextlost", this.onContextLost);
    this.canvas.removeEventListener(
      "webglcontextrestored",
      this.onContextRestored
    );
    document.removeEventListener("visibilitychange", this.onVisibility);
    this.reduceMotion.removeEventListener("change", this.onMotionChange);
    this.unbindPointer();
    this.gl.deleteBuffer(this.buffer);
    this.gl.deleteProgram(this.program);
    this.gl.getExtension("WEBGL_lose_context")?.loseContext();
    if (this.canvas.parentNode === this.host) this.host.removeChild(this.canvas);
    this.ok = false;
  }
  // ---------------------------------------------------------------- internals
  /** (Re)create everything that lives inside the GL context: the derivatives
   *  extension, program, buffer, attribute and uniform locations, blend state.
   *  Runs at construction and again after `webglcontextrestored`, which
   *  invalidates every object the previous context handed out. */
  setupGL() {
    const gl = this.gl;
    if (!gl.getExtension("OES_standard_derivatives")) return false;
    const program = buildProgram(gl);
    if (!program) return false;
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 3, -1, -1, 3]),
      gl.STATIC_DRAW
    );
    const aPos = gl.getAttribLocation(program, "aPos");
    gl.enableVertexAttribArray(aPos);
    gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);
    const u = (n) => gl.getUniformLocation(program, n);
    this.program = program;
    this.buffer = buffer;
    this.uRes = u("uRes");
    this.uTime = u("uTime");
    this.uSeed = u("uSeed");
    this.uScale = u("uScale");
    this.uLevels = u("uLevels");
    this.uLineWidth = u("uLineWidth");
    this.uOpacity = u("uOpacity");
    this.uColor = u("uColor");
    this.uDrift = u("uDrift");
    this.uWarp = u("uWarp");
    this.uScrollOff = u("uScrollOff");
    this.uMouse = u("uMouse");
    this.uMouseBump = u("uMouseBump");
    this.uMouseRadius = u("uMouseRadius");
    gl.useProgram(program);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
    return true;
  }
  /** Pointer listeners cost a layout read per frame per instance, so they only
   *  go on while `interactive` is actually set. */
  bindPointer() {
    if (this.pointerBound) return;
    this.pointerBound = true;
    window.addEventListener("pointermove", this.onPointerMove);
    document.documentElement.addEventListener(
      "pointerleave",
      this.onPointerLeave
    );
    window.addEventListener("blur", this.onPointerLeave);
    window.addEventListener("scroll", this.onScroll, {
      passive: true,
      capture: true
    });
  }
  unbindPointer() {
    if (!this.pointerBound) return;
    this.pointerBound = false;
    window.removeEventListener("pointermove", this.onPointerMove);
    document.documentElement.removeEventListener(
      "pointerleave",
      this.onPointerLeave
    );
    window.removeEventListener("blur", this.onPointerLeave);
    window.removeEventListener("scroll", this.onScroll, { capture: true });
  }
  /** devicePixelRatio changes (window dragged to a different-density display)
   *  don't change the element's CSS size, so ResizeObserver never fires. Watch
   *  the resolution media query instead, or a paused instance keeps a stale
   *  backing store and renders blurry. */
  watchDpr() {
    this.dprQuery?.removeEventListener("change", this.onDprChange);
    const dpr = window.devicePixelRatio || 1;
    this.dprQuery = window.matchMedia(`(resolution: ${dpr}dppx)`);
    this.dprQuery.addEventListener("change", this.onDprChange);
  }
  tickMouse(dt) {
    const p = this.live;
    const active = p.interactive && this.pointerInside;
    if (!active && this.bump === 0) return;
    if (active) {
      this.rectAge += dt;
      if (this.rectAge > 0.5) {
        this.rectAge = 0;
        this.rect = null;
      }
      if (!this.rect) this.rect = this.canvas.getBoundingClientRect();
      const rect = this.rect;
      const w = rect.width;
      const h = rect.height;
      if (w > 0 && h > 0) {
        const fx = this.clientX - rect.left;
        const fy = h - (this.clientY - rect.top);
        const m = Math.min(w, h);
        this.mouseNX = (fx - 0.5 * w) / m;
        this.mouseNY = (fy - 0.5 * h) / m;
      }
    }
    const target = active ? p.mouseStrength : 0;
    this.bump += (target - this.bump) * fri(0.08, dt);
    if (!active && Math.abs(this.bump) < 1e-4) this.bump = 0;
    const tx = this.mouseNX * p.scale;
    const ty = this.mouseNY * p.scale;
    const k = fri(0.06, dt);
    this.mouseX += (tx - this.mouseX) * k;
    this.mouseY += (ty - this.mouseY) * k;
  }
  /** The scroll pan, eased. The raw value steps: a wheel notch is ~100px at
   *  once, and a field panned straight off `scrollY` jumps that far in one
   *  frame while everything else on the page is still gliding. Following it
   *  instead keeps the map moving continuously between notches, and costs the
   *  pan a few frames of lag that nothing is synchronised to anyway.
   *  `scrollEase: 1` is the old behaviour, locked to the scrollbar. */
  tickPan(dt) {
    const p = this.live;
    if (p.scrollPan[0] === 0 && p.scrollPan[1] === 0) return;
    const target = p.getPanScroll ? p.getPanScroll() : window.scrollY || 0;
    if (!this.panReady) {
      this.panReady = true;
      this.pan = target;
      return;
    }
    this.pan += (target - this.pan) * fri(p.scrollEase, dt);
  }
  progress() {
    if (this.live.getProgress) return clamp01(this.live.getProgress());
    if (typeof window === "undefined") return 0;
    const doc = document.documentElement;
    return clamp01(
      (window.scrollY || 0) / Math.max(1, doc.scrollHeight - window.innerHeight)
    );
  }
  resize() {
    if (this.contextLost) return;
    const dpr = Math.min(window.devicePixelRatio || 1, this.live.maxDpr);
    const w = Math.max(1, Math.round(this.canvas.clientWidth * dpr));
    const h = Math.max(1, Math.round(this.canvas.clientHeight * dpr));
    if (w === this.width && h === this.height) return;
    this.width = w;
    this.height = h;
    this.canvas.width = w;
    this.canvas.height = h;
    this.gl.viewport(0, 0, w, h);
  }
};

// src/support.ts
var cached = null;
function isSupported() {
  if (cached !== null) return cached;
  if (typeof document === "undefined") return false;
  try {
    const canvas = document.createElement("canvas");
    const gl = canvas.getContext("webgl") || canvas.getContext("experimental-webgl");
    cached = !!(gl && gl.getExtension("OES_standard_derivatives"));
    gl?.getExtension("WEBGL_lose_context")?.loseContext();
  } catch {
    cached = false;
  }
  return cached;
}

// src/presets.ts
var PRESETS = [
  {
    id: "relief",
    name: "Relief",
    options: { color: "#F2EFE6", opacity: 0.34, warp: 0.22 }
  },
  {
    id: "ridgeline",
    name: "Ridgeline",
    options: {
      scale: 0.8,
      levels: 8,
      lineWidth: 1.6,
      color: "#FF4D00",
      opacity: 0.5,
      warp: 0.3
    }
  },
  {
    id: "survey",
    name: "Survey",
    options: {
      scale: 1.6,
      levels: 18,
      lineWidth: 0.8,
      color: "#9EC7E8",
      opacity: 0.4,
      warp: 0.12
    }
  },
  {
    id: "basin",
    name: "Basin",
    options: {
      scale: 0.6,
      levels: 12,
      color: "#C3D82C",
      opacity: 0.42,
      warp: 0.05,
      speed: 0.02
    }
  },
  {
    id: "glass",
    name: "Glass",
    options: {
      warp: 0,
      levels: 7,
      lineWidth: 2.2,
      color: "#C9B8E8",
      opacity: 0.3,
      speed: 6e-3
    }
  },
  {
    id: "drift",
    name: "Drift",
    options: {
      drift: [0.02, 0.01],
      speed: 0.03,
      levels: 10,
      color: "#A8B89A",
      opacity: 0.38
    }
  }
];
export {
  DEFAULTS,
  PRESETS,
  TopoField,
  isSupported,
  parseColor,
  randomSeed,
  seedOffset
};
//# sourceMappingURL=index.js.map