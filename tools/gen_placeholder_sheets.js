#!/usr/bin/env node
// Generates placeholder sprite sheets + sidecars for the art pipeline
// (docs/art-pipeline.md). Real art replaces the PNGs file-for-file; the
// sidecar JSON is the contract. No dependencies beyond Node's zlib.
//
//   node tools/gen_placeholder_sheets.js
//
// Sheet layout: one block of rows per animation (in the order below), one
// row per drawn direction inside a block, one column per frame. Source
// colours are the sidecar's `palette` roles; the game swaps them per actor.

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const FRAME = [48, 64];
const ORIGIN = [24, 60]; // feet
const DIRECTIONS = ["s", "sw", "w", "nw", "n"];
const MIRROR = { se: "sw", e: "w", ne: "nw" };
const FACING = { s: [0, 1], sw: [-0.7, 0.7], w: [-1, 0], nw: [-0.7, -0.7], n: [0, -1] };
const ANIMS = [
  ["idle", 4, 6, true],
  ["walk", 6, 10, true],
  ["attack", 4, 12, false],
  ["cast", 4, 10, false],
  ["hit", 3, 12, false],
  ["death", 5, 8, false],
];
const PALETTE = { fill: "#ff00ff", outline: "#7f007f", highlight: "#ff80ff", accent: "#ffffff" };
const RGB = Object.fromEntries(Object.entries(PALETTE).map(([k, v]) => [k, hex(v)]));

function hex(h) { return [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16), 255]; }

// --- tiny PNG encoder ------------------------------------------------------
const CRC_TABLE = new Int32Array(256);
for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; CRC_TABLE[n] = c; }
function crc32(buf) { let c = -1; for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ -1) >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) { raw[y * (stride + 1)] = 0; rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", Buffer.alloc(0))]);
}

// --- canvas ----------------------------------------------------------------
class Canvas {
  constructor(w, h) { this.w = w; this.h = h; this.buf = Buffer.alloc(w * h * 4); }
  set(x, y, c) { x |= 0; y |= 0; if (x < 0 || y < 0 || x >= this.w || y >= this.h) return; const i = (y * this.w + x) * 4; this.buf[i] = c[0]; this.buf[i + 1] = c[1]; this.buf[i + 2] = c[2]; this.buf[i + 3] = c[3]; }
  ellipse(cx, cy, rx, ry, fill, outline) {
    for (let y = Math.floor(cy - ry) - 1; y <= cy + ry + 1; y++) for (let x = Math.floor(cx - rx) - 1; x <= cx + rx + 1; x++) {
      const nx = (x + 0.5 - cx) / rx, ny = (y + 0.5 - cy) / ry, d = nx * nx + ny * ny;
      if (d <= 1) this.set(x, y, d > 0.72 ? outline : fill);
    }
  }
  rect(x0, y0, w, h, c) { for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) this.set(x, y, c); }
  line(x0, y0, x1, y1, c) { const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0), 1); for (let i = 0; i <= n; i++) this.set(Math.round(x0 + (x1 - x0) * i / n), Math.round(y0 + (y1 - y0) * i / n), c); }
}

// --- the rig ---------------------------------------------------------------
// Draws one frame of the shared humanoid rig at frame-local origin (ox, oy).
function drawRig(cv, ox, oy, dir, anim, frame, variant) {
  const [fx, fy] = FACING[dir];
  const F = RGB.fill, O = RGB.outline, H = RGB.highlight, A = RGB.accent;
  let bob = 0, lean = 0, back = 0, fall = 0, flash = false, armsUp = false, weapon = false, legs = 0, glow = 0;
  switch (anim) {
    case "idle": bob = [0, -1, 0, 1][frame]; break;
    case "walk": bob = [0, -1, -1, 0, -1, -1][frame]; legs = [2, 3, 1, -2, -3, -1][frame]; break;
    case "attack": lean = [0, 3, 6, 2][frame]; weapon = frame >= 1 && frame <= 2; break;
    case "cast": armsUp = true; glow = [0, 2, 4, 3][frame]; break;
    case "hit": back = [-3, -2, -1][frame]; flash = frame === 0; break;
    case "death": fall = frame; break;
  }
  const shiftX = Math.round(fx * (lean + back)), shiftY = Math.round(fy * (lean + back) * 0.5) + bob;
  const cx = ox + shiftX, feet = oy + shiftY;
  const fillC = flash ? H : F;
  if (fall > 0) {
    // Torso tips over and flattens toward the ground.
    const t = fall / 4;
    cv.ellipse(cx + Math.round(-fx * 6 * t), feet - 10 + Math.round(6 * t), 9 + 6 * t, 15 - 11 * t, fillC, O);
    cv.ellipse(cx + Math.round(-fx * 14 * t), feet - 34 + Math.round(28 * t), 7, 7 - 3 * t, fillC, O);
    return;
  }
  // Legs
  cv.rect(cx - 6, feet - 12 + Math.max(0, -legs), 4, 12 - Math.max(0, -legs), O);
  cv.rect(cx + 2, feet - 12 + Math.max(0, legs), 4, 12 - Math.max(0, legs), O);
  // Torso
  cv.ellipse(cx, feet - 22, 9, 14, fillC, O);
  // Arms
  if (armsUp) { cv.ellipse(cx - 11, feet - 36, 3, 6, fillC, O); cv.ellipse(cx + 11, feet - 36, 3, 6, fillC, O); }
  else { cv.ellipse(cx - 11, feet - 24, 3, 7, fillC, O); cv.ellipse(cx + 11, feet - 24, 3, 7, fillC, O); }
  // Head
  cv.ellipse(cx, feet - 44, 7, 7, flash ? H : H, O);
  cv.ellipse(cx, feet - 44, 6, 6, fillC, fillC);
  // Face: eyes only when the face points toward the camera or sideways.
  if (fy >= 0) {
    const ex = cx + Math.round(fx * 3);
    if (Math.abs(fx) < 0.9) { cv.set(ex - 2, feet - 45, A); cv.set(ex + 2, feet - 45, A); } else cv.set(ex, feet - 45, A);
  }
  // Variant dressing
  if (variant === "scav") {
    // A sharpened strut carried on the facing side; swings on attack.
    const hx = cx + Math.round(fx * 12) + (fx === 0 ? 11 : 0), hy = feet - 24;
    const len = weapon ? 16 : 10;
    cv.line(hx, hy, hx + Math.round(fx * len) + (fx === 0 ? 0 : 0), hy - len + (weapon ? 4 : 0), O);
    cv.rect(cx - 6, feet - 48, 12, 2, O); // headband
  } else if (weapon) {
    cv.line(cx + Math.round(fx * 12), feet - 26, cx + Math.round(fx * 22), feet - 30, O);
  }
  if (glow > 0) cv.ellipse(cx + Math.round(fx * 8), feet - 40, glow, glow, H, H);
}

function buildSheet(id, variant) {
  const cols = Math.max(...ANIMS.map(a => a[1]));
  const rows = ANIMS.length * DIRECTIONS.length;
  const cv = new Canvas(FRAME[0] * cols, FRAME[1] * rows);
  const animations = {};
  let row = 0;
  for (const [name, frames, fps, loop] of ANIMS) {
    animations[name] = { row, frames, fps, loop };
    for (let d = 0; d < DIRECTIONS.length; d++) {
      for (let f = 0; f < frames; f++) drawRig(cv, f * FRAME[0] + ORIGIN[0], (row + d) * FRAME[1] + ORIGIN[1], DIRECTIONS[d], name, f, variant);
    }
    row += DIRECTIONS.length;
  }
  const sidecar = {
    name: id.charAt(0).toUpperCase() + id.slice(1) + " (placeholder rig)",
    summary: "Generated by tools/gen_placeholder_sheets.js. Replace the PNG file-for-file; keep this sidecar in sync with the new sheet.",
    image: id + ".png",
    frame: FRAME,
    origin: ORIGIN,
    directions: DIRECTIONS,
    mirror: MIRROR,
    palette: PALETTE,
    animations,
  };
  return { png: encodePng(cv.w, cv.h, cv.buf), sidecar };
}

const outDir = path.join(__dirname, "..", "content", "sprites");
fs.mkdirSync(outDir, { recursive: true });
for (const [id, variant] of [["trueborn", "trueborn"], ["scav", "scav"]]) {
  const { png, sidecar } = buildSheet(id, variant);
  fs.writeFileSync(path.join(outDir, id + ".png"), png);
  fs.writeFileSync(path.join(outDir, id + ".json"), JSON.stringify(sidecar, null, 2) + "\n");
  console.log(`${id}: ${png.length} bytes, ${Object.keys(sidecar.animations).length} animations, ${DIRECTIONS.length} directions`);
}
