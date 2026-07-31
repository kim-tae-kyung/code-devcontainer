#!/usr/bin/env node
// Assemble naturally ordered PNG frames into a verified animated GIF.
// Usage:
//   frames_to_gif.mjs <dir | frame1.png frame2.png ...> --out demo.gif
//     [--delay 900] [--width 1000] [--loop 0] [--force]

import sharp from 'sharp';
import {
  existsSync,
  linkSync,
  lstatSync,
  mkdtempSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  unlinkSync,
} from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';

const usage = `usage:
  frames_to_gif.mjs <dir | frame1.png frame2.png ...> --out FILE
    [--delay MS] [--width PX] [--loop N] [--force]`;

const argv = process.argv.slice(2);
const opts = { out: 'demo.gif', delay: 900, loop: 0, width: undefined, force: false };
const inputs = [];
let optionsEnded = false;

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function optionValue(index, option) {
  const value = argv[index + 1];
  if (value === undefined || value === '') fail(`${option} requires a value`);
  return value;
}

for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  if (optionsEnded) inputs.push(arg);
  else if (arg === '--') optionsEnded = true;
  else if (arg === '--out' || arg === '-o') opts.out = optionValue(i++, arg);
  else if (arg === '--delay') opts.delay = Number(optionValue(i++, arg));
  else if (arg === '--width') opts.width = Number(optionValue(i++, arg));
  else if (arg === '--loop') opts.loop = Number(optionValue(i++, arg));
  else if (arg === '--force') opts.force = true;
  else if (arg === '--help' || arg === '-h') {
    console.log(usage);
    process.exit(0);
  } else if (arg.startsWith('-')) fail(`unknown option: ${arg}`);
  else inputs.push(arg);
}

if (!Number.isInteger(opts.delay) || opts.delay <= 0 || opts.delay > 60_000) {
  fail('--delay must be an integer from 1 to 60000');
}
if (opts.width !== undefined && (!Number.isInteger(opts.width) || opts.width <= 0)) {
  fail('--width must be a positive integer');
}
if (!Number.isInteger(opts.loop) || opts.loop < 0) {
  fail('--loop must be a non-negative integer');
}
if (inputs.length === 0) fail('provide a directory of PNGs or an ordered list of PNG files');

const naturalSort = (a, b) =>
  a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });

let frames;
try {
  if (inputs.length === 1 && statSync(inputs[0]).isDirectory()) {
    frames = readdirSync(inputs[0])
      .filter((file) => file.toLowerCase().endsWith('.png'))
      .sort(naturalSort)
      .map((file) => join(inputs[0], file));
  } else {
    frames = [...inputs];
  }
} catch (error) {
  fail(`cannot read input: ${error.message}`);
}

if (frames.length < 2) fail('at least two PNG frames are required for an animation');

const metadata = [];
for (const frame of frames) {
  if (!existsSync(frame) || !statSync(frame).isFile()) fail(`frame is not a file: ${frame}`);
  try {
    const info = await sharp(frame).metadata();
    if (info.format !== 'png' || !info.width || !info.height) {
      fail(`frame is not a readable PNG: ${frame}`);
    }
    metadata.push(info);
  } catch (error) {
    fail(`cannot decode frame ${frame}: ${error.message}`);
  }
}

const { width: sourceWidth, height: sourceHeight } = metadata[0];
for (let i = 1; i < metadata.length; i += 1) {
  if (metadata[i].width !== sourceWidth || metadata[i].height !== sourceHeight) {
    fail(
      `all frames must share dimensions; ${frames[0]} is ${sourceWidth}x${sourceHeight}, ` +
        `but ${frames[i]} is ${metadata[i].width}x${metadata[i].height}`,
    );
  }
}

const output = resolve(opts.out);
const outputDir = dirname(output);
const outputName = basename(output);
if (!existsSync(outputDir) || !statSync(outputDir).isDirectory()) {
  fail(`output directory does not exist: ${outputDir}`);
}
if (existsSync(output) || (() => {
  try {
    return lstatSync(output).isSymbolicLink();
  } catch {
    return false;
  }
})()) {
  if (!opts.force) fail(`output already exists: ${output}; pass --force to replace it`);
}
if (frames.some((frame) => resolve(frame) === output)) fail('output must not replace an input frame');

const tempDir = mkdtempSync(join(outputDir, '.capture-demo-'));
const tempOutput = join(tempDir, outputName);
let renderError;

try {
  let joinInput = frames;
  if (opts.width !== undefined) {
    joinInput = [];
    for (const frame of frames) {
      joinInput.push(await sharp(frame).resize({ width: opts.width }).png().toBuffer());
    }
  }

  const delay = new Array(frames.length).fill(opts.delay);
  await sharp(joinInput, { join: { animated: true } })
    .gif({ delay, loop: opts.loop })
    .toFile(tempOutput);

  const result = await sharp(tempOutput, { animated: true }).metadata();
  if (result.format !== 'gif' || result.pages !== frames.length) {
    throw new Error(
      `GIF verification failed: expected ${frames.length} frames, got ${result.pages ?? 1}`,
    );
  }
  if (opts.width !== undefined && result.width !== opts.width) {
    throw new Error(`GIF verification failed: expected width ${opts.width}, got ${result.width}`);
  }

  if (opts.force) {
    renameSync(tempOutput, output);
  } else {
    try {
      linkSync(tempOutput, output);
      unlinkSync(tempOutput);
    } catch (error) {
      if (error.code === 'EEXIST') {
        throw new Error(`output appeared during rendering: ${output}`);
      }
      throw error;
    }
  }

  const bytes = statSync(output).size;
  console.log(
    `wrote ${output} (${result.width}x${result.pageHeight ?? result.height}, ` +
      `${result.pages} frames, ${bytes} bytes, ${opts.delay}ms/frame, loop=${opts.loop})`,
  );
} catch (error) {
  renderError = error;
} finally {
  rmSync(tempDir, { recursive: true, force: true });
}

if (renderError) fail(renderError.message);
