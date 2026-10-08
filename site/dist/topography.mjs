/**
 * The same Topolines 0.3.0 renderer and idle configuration used by
 * https://streammedia2.ru/topographic.js?v=2-glass-preview.
 * The unmodified MIT engine and license are vendored locally.
 * Its palette is adapted to the warm glass UI at the user's request.
 *
 * startTopography(host, options) accepts a background div (preferred) or canvas.
 * API: setPaused/toggle/resize/destroy; paused/running/reducedMotion/supported/
 * renderer getters. It draws immediately. environment/createField inject tests.
 */
import { TopoField } from "./vendor/topolines-0.3.0.js";

export const STATIC_CONTOURS =
  "repeating-radial-gradient(ellipse at 90% 20%,transparent 0 42px,#cba87516 43px 44px,transparent 45px 75px)";

/** Deterministic, reference-derived viewport configuration. */
export function referenceOptions(width = 1440) {
  const small = width <= 700;
  return {
    seed: "svoi-wave-studio",
    color: "#cba875",
    opacity: small ? 0.12 : 0.19,
    scale: small ? 0.72 : 0.82,
    levels: small ? 8 : 10,
    lineWidth: small ? 1 : 1.15,
    speed: 0.007,
    drift: [0.003, 0.001],
    warp: 0.23,
    maxDpr: 1,
    interactive: false,
  };
}

export function startTopography(element, options = {}) {
  const win = options.environment?.window ?? globalThis.window ?? globalThis;
  const doc =
    options.environment?.document ?? element?.ownerDocument ?? win.document;
  const raf =
    typeof win.requestAnimationFrame === "function"
      ? win.requestAnimationFrame.bind(win)
      : null;
  const caf =
    typeof win.cancelAnimationFrame === "function"
      ? win.cancelAnimationFrame.bind(win)
      : () => {};
  const motion = win.matchMedia?.("(prefers-reduced-motion: reduce)");
  let reducedMotion = Boolean(motion?.matches),
    manualPause = Boolean(options.paused);
  let destroyed = false,
    suspended = false,
    resizeFrame = null,
    field = null;
  let host = element,
    replacedCanvas = null;
  const cleanups = [];
  const viewportWidth = () =>
    Number(win.innerWidth) || host?.clientWidth || 1440;

  // The reference engine owns its canvas, so preserve the original canvas API
  // by replacing it with an equivalent background host when necessary.
  if (
    typeof element?.getContext === "function" &&
    doc?.createElement &&
    element.parentNode?.replaceChild
  ) {
    host = doc.createElement("div");
    for (const attribute of [...element.attributes])
      host.setAttribute(attribute.name, attribute.value);
    element.parentNode.replaceChild(host, element);
    replacedCanvas = element;
  }
  function markState() {
    if (host?.dataset) {
      host.dataset.renderer = field?.ok ? "webgl" : "static";
      host.dataset.motion = reducedMotion
        ? "reduced"
        : manualPause
          ? "paused"
          : "animated";
    }
  }
  function canAnimate() {
    return (
      !destroyed &&
      !suspended &&
      !!field?.ok &&
      !field.contextLost &&
      field.visible !== false &&
      !manualPause &&
      !reducedMotion &&
      !doc?.hidden &&
      !!raf
    );
  }
  function reconcile() {
    markState();
    if (canAnimate()) field.play();
    else field?.pause();
  }
  const initialChildren = new Set(host?.children ? [...host.children] : []);
  try {
    const createField =
      options.createField ??
      ((node, settings) => new TopoField(node, settings));
    if (host && typeof host.appendChild === "function")
      field = createField(host, referenceOptions(viewportWidth()));
  } catch {
    for (const child of host?.children ? [...host.children] : [])
      if (!initialChildren.has(child)) child.remove?.();
    field = null;
  }
  if (!field?.ok && host?.style) host.style.backgroundImage = STATIC_CONTOURS;

  if (field?.ok) {
    // Keep the reference shader, seed, geometry and accumulated clock intact;
    // wrap only its controller for manual pause and a lower rendering rate.
    field.pause();
    const vendorStart = field.start.bind(field);
    field.start = () => {
      if (canAnimate()) vendorStart();
    };
    let lastRender = -Infinity;
    field.frame = (now) => {
      if (!field.running || !canAnimate()) {
        field.pause();
        return;
      }
      const dt = Math.max(0, Math.min((now - field.last) / 1000, 0.1));
      field.last = now;
      field.clock += dt * field.live.speed;
      field.tickMouse(dt);
      field.tickPan(dt);
      if (now - lastRender >= 1000 / (viewportWidth() <= 700 ? 12 : 18)) {
        field.render();
        lastRender = now;
      }
      field.raf = raf(field.frame);
    };
  }
  function resize() {
    if (destroyed) return;
    if (field?.ok) {
      field.setOptions(referenceOptions(viewportWidth()));
      field.resize();
      if (field.running) field.render();
    }
    reconcile();
  }
  function queueResize() {
    if (destroyed || resizeFrame !== null) return;
    if (!raf) {
      resize();
      return;
    }
    resizeFrame = raf(() => {
      resizeFrame = null;
      resize();
    });
  }
  function listen(target, name, callback) {
    if (!target?.addEventListener) return;
    target.addEventListener(name, callback);
    cleanups.push(() => target.removeEventListener(name, callback));
  }
  function motionChanged(event) {
    reducedMotion = Boolean(event.matches);
    reconcile();
  }
  listen(win, "resize", queueResize);
  listen(win, "orientationchange", queueResize);
  listen(win.visualViewport, "resize", queueResize);
  listen(doc, "visibilitychange", reconcile);
  listen(win, "pagehide", () => {
    suspended = true;
    reconcile();
  });
  listen(win, "pageshow", () => {
    suspended = false;
    reconcile();
  });
  if (motion?.addEventListener) listen(motion, "change", motionChanged);
  else if (motion?.addListener) {
    motion.addListener(motionChanged);
    cleanups.push(() => motion.removeListener(motionChanged));
  }
  listen(field?.canvas, "webglcontextrestored", reconcile);
  // The vendor already rendered its first frame synchronously and owns its
  // context-loss handlers and resize/intersection observers.
  reconcile();
  return {
    setPaused(value) {
      if (!destroyed) {
        manualPause = Boolean(value);
        reconcile();
      }
      return manualPause;
    },
    toggle() {
      return this.setPaused(!manualPause);
    },
    resize,
    destroy() {
      if (destroyed) return;
      destroyed = true;
      if (resizeFrame !== null) caf(resizeFrame);
      resizeFrame = null;
      cleanups.splice(0).forEach((cleanup) => cleanup());
      field?.destroy();
      if (replacedCanvas && host?.parentNode)
        host.parentNode.replaceChild(replacedCanvas, host);
    },
    get paused() {
      return manualPause;
    },
    get running() {
      return !destroyed && Boolean(field?.running);
    },
    get reducedMotion() {
      return reducedMotion;
    },
    get supported() {
      return Boolean(field?.ok);
    },
    get renderer() {
      return field?.ok ? "webgl" : "static";
    },
  };
}
