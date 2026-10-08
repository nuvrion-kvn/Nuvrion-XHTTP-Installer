import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import {
  referenceOptions,
  startTopography,
  STATIC_CONTOURS,
} from "../dist/topography.mjs";
import { seedOffset } from "../dist/vendor/topolines-0.3.0.js";

// Guard the actual reference renderer, rather than an approximate custom field.
const vendor = readFileSync(
  new URL("../dist/vendor/topolines-0.3.0.js", import.meta.url),
);
assert.equal(
  createHash("sha256").update(vendor).digest("hex"),
  "d65f7bbfb5a3718492fd2f9295affedfbd1a23b334fd4eb83071c7a9a7fb9b64",
);
assert.deepEqual(referenceOptions(1440), {
  seed: "svoi-wave-studio",
  color: "#cba875",
  opacity: 0.19,
  scale: 0.82,
  levels: 10,
  lineWidth: 1.15,
  speed: 0.007,
  drift: [0.003, 0.001],
  warp: 0.23,
  maxDpr: 1,
  interactive: false,
});
assert.deepEqual(referenceOptions(390), {
  ...referenceOptions(1440),
  opacity: 0.12,
  scale: 0.72,
  levels: 8,
  lineWidth: 1,
});
assert.equal(referenceOptions(700).levels, 8);
assert.equal(referenceOptions(701).levels, 10);
assert.deepEqual(
  seedOffset("svoi-wave-studio"),
  seedOffset("svoi-wave-studio"),
);
assert(seedOffset("svoi-wave-studio").every(Number.isFinite));
assert.notDeepEqual(
  seedOffset("svoi-wave-studio"),
  seedOffset("another-field"),
);
const license = readFileSync(
  new URL("../dist/vendor/topolines-LICENSE.txt", import.meta.url),
  "utf8",
);
assert(
  license.includes("Copyright (c) 2026 idleCyrex") &&
    license.includes("Ashima Arts") &&
    license.includes("Stefan Gustavson"),
);
function emitter(properties = {}) {
  const handlers = new Map();
  return {
    ...properties,
    addEventListener(name, fn) {
      if (!handlers.has(name)) handlers.set(name, new Set());
      handlers.get(name).add(fn);
    },
    removeEventListener(name, fn) {
      handlers.get(name)?.delete(fn);
    },
    emit(name, event = {}) {
      for (const fn of handlers.get(name) || []) fn(event);
    },
    listenerCount() {
      return [...handlers.values()].reduce((n, s) => n + s.size, 0);
    },
  };
}
function harness({
  reduced = false,
  mobile = false,
  supported = true,
  throws = false,
} = {}) {
  const pending = new Map();
  let nextId = 0,
    draws = 0,
    instance;
  const document = emitter({ hidden: false });
  const motion = emitter({ matches: reduced });
  const window = emitter({
    innerWidth: mobile ? 390 : 1440,
    innerHeight: mobile ? 844 : 900,
    requestAnimationFrame(fn) {
      const id = ++nextId;
      pending.set(id, fn);
      return id;
    },
    cancelAnimationFrame(id) {
      pending.delete(id);
    },
    matchMedia() {
      return motion;
    },
  });
  const host = { style: {}, dataset: {}, children: [], appendChild() {} };
  const createField = (node, settings) => {
    if (throws) throw Error("WebGL blocked");
    instance = {
      ok: supported,
      visible: true,
      contextLost: false,
      running: false,
      clock: 0,
      last: 0,
      raf: 0,
      canvas: emitter(),
      live: { ...settings },
      start() {
        if (!this.running) {
          this.running = true;
          this.last = 0;
          this.raf = window.requestAnimationFrame(this.frame);
        }
      },
      play() {
        this.start();
      },
      pause() {
        this.running = false;
        window.cancelAnimationFrame(this.raf);
      },
      frame() {},
      render() {
        draws++;
      },
      resize() {},
      tickMouse() {},
      tickPan() {},
      setOptions(patch) {
        Object.assign(this.live, patch);
        if (this.ok && !this.running) this.render();
      },
      destroy() {
        this.pause();
        this.ok = false;
      },
    };
    if (supported) {
      instance.render();
      instance.start();
    }
    return instance;
  };
  function tick(time) {
    const callbacks = [...pending.values()];
    pending.clear();
    for (const fn of callbacks) fn(time);
  }
  return {
    window,
    document,
    motion,
    host,
    createField,
    pending,
    tick,
    get draws() {
      return draws;
    },
    get field() {
      return instance;
    },
  };
}
const h = harness();
const api = startTopography(h.host, {
  environment: h,
  createField: h.createField,
});
assert.equal(h.draws, 1);
assert.equal(api.renderer, "webgl");
assert.equal(api.running, true);
h.tick(0);
const first = h.draws;
h.tick(20);
assert.equal(h.draws, first);
h.tick(80);
assert(h.draws > first);
assert(
  Math.abs(h.field.clock - 0.08 * 0.007) < 1e-12,
  "Reference accumulated clock/speed retained",
);
api.setPaused(true);
assert.equal(api.paused, true);
assert.equal(h.pending.size, 0);
h.field.start();
assert.equal(
  h.pending.size,
  0,
  "Vendor callbacks cannot override manual pause",
);
api.toggle();
assert.equal(api.running, true);
h.document.hidden = true;
h.document.emit("visibilitychange");
assert.equal(h.pending.size, 0);
h.field.start();
assert.equal(h.pending.size, 0);
h.document.hidden = false;
h.document.emit("visibilitychange");
assert.equal(api.running, true);
h.motion.emit("change", { matches: true });
assert.equal(api.reducedMotion, true);
assert.equal(h.pending.size, 0);
h.motion.emit("change", { matches: false });
assert.equal(api.running, true);
h.window.emit("pagehide");
assert.equal(h.pending.size, 0);
h.window.emit("pageshow");
assert.equal(api.running, true);
api.setPaused(true);
h.window.innerWidth = 390;
h.window.emit("resize");
h.window.emit("orientationchange");
assert.equal(h.pending.size, 1);
h.tick(160);
assert.equal(h.field.live.levels, 8);
assert.equal(h.pending.size, 0);
const frozen = h.field.clock;
api.toggle();
h.tick(10000);
assert(h.field.clock - frozen <= 0.1 * 0.007 + 1e-12);
api.destroy();
assert.equal(h.pending.size, 0);
assert.equal(
  h.window.listenerCount() +
    h.document.listenerCount() +
    h.motion.listenerCount() +
    h.field.canvas.listenerCount(),
  0,
);
api.destroy();
const mobile = harness({ mobile: true });
const mobileApi = startTopography(mobile.host, {
  environment: mobile,
  createField: mobile.createField,
});
mobile.tick(0);
const mobileFirst = mobile.draws;
mobile.tick(60);
assert.equal(mobile.draws, mobileFirst);
mobile.tick(90);
assert(mobile.draws > mobileFirst);
mobileApi.destroy();
const still = harness({ reduced: true });
const staticApi = startTopography(still.host, {
  environment: still,
  createField: still.createField,
});
assert.equal(still.draws, 1);
assert.equal(still.pending.size, 0);
staticApi.destroy();
for (const settings of [{ supported: false }, { throws: true }]) {
  const missing = harness(settings);
  const fallback = startTopography(missing.host, {
    environment: missing,
    createField: missing.createField,
  });
  assert.equal(fallback.supported, false);
  assert.equal(fallback.renderer, "static");
  assert.equal(missing.host.dataset.renderer, "static");
  assert.equal(missing.host.style.backgroundImage, STATIC_CONTOURS);
  assert.equal(missing.pending.size, 0);
  fallback.destroy();
}
console.log(
  "Reference topography checks passed: exact vendored shader/license, viewport parameters, seeded field, capped FPS, pause, hidden/reduced motion, lifecycle and static fallback",
);
