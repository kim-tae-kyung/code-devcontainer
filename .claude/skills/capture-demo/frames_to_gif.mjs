#!/usr/bin/env node
// Assemble PNG frames into an animated GIF using sharp (no ffmpeg).
// Usage:
//   node frames_to_gif.mjs <dir | frame1.png frame2.png ...> --out demo.gif [--delay 800] [--width 1000] [--loop 0]
// - <dir>: a directory; all *.png inside are used, natural-sorted (frame-2 before frame-10).
// - Multiple file args are used in the given order.
// All frames must share the same dimensions (screenshots from one viewport do).
// GIF is the only output format on purpose: it is the sole animated format GitHub renders inline.
import sharp from 'sharp';
import { readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const opts = { out: 'demo.gif', delay: 800, loop: 0, width: undefined };
const inputs = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--out' || a === '-o') opts.out = argv[++i];
  else if (a === '--delay') opts.delay = Number(argv[++i]);
  else if (a === '--width') opts.width = Number(argv[++i]);
  else if (a === '--loop') opts.loop = Number(argv[++i]);
  else if (a === '-h' || a === '--help') { console.log('see header of this file for usage'); process.exit(0); }
  else inputs.push(a);
}

if (inputs.length === 0) {
  console.error('error: provide a directory of PNGs or a list of PNG files');
  process.exit(1);
}

const naturalSort = (a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });

let frames;
if (inputs.length === 1 && statSync(inputs[0]).isDirectory()) {
  const dir = inputs[0];
  frames = readdirSync(dir)
    .filter((f) => f.toLowerCase().endsWith('.png'))
    .sort(naturalSort)
    .map((f) => join(dir, f));
} else {
  frames = inputs; // explicit file list, order preserved
}

if (frames.length === 0) {
  console.error('error: no PNG frames found');
  process.exit(1);
}

// Resize each frame BEFORE joining: resizing a joined animated pipeline collapses
// it to a single frame. delay must be a per-frame array; a scalar only sets frame 0.
let joinInput = frames;
if (opts.width) {
  joinInput = [];
  for (const f of frames) joinInput.push(await sharp(f).resize({ width: opts.width }).png().toBuffer());
}
const delay = new Array(frames.length).fill(opts.delay);
await sharp(joinInput, { join: { animated: true } })
  .gif({ delay, loop: opts.loop })
  .toFile(opts.out);

console.log(`wrote ${opts.out} (${frames.length} frames, ${opts.delay}ms/frame, loop=${opts.loop})`);
