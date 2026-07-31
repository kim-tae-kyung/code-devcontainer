#!/usr/bin/env node
import sharp from 'sharp';
import { statSync } from 'node:fs';
import { resolve } from 'node:path';

const argv = process.argv.slice(2);
let file;
let minFrames = 1;

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

for (let i = 0; i < argv.length; i += 1) {
  const arg = argv[i];
  if (arg === '--min-frames') {
    const value = argv[++i];
    minFrames = Number(value);
  } else if (arg === '--help' || arg === '-h') {
    console.log('usage: verify_gif.mjs FILE [--min-frames N]');
    process.exit(0);
  } else if (arg.startsWith('-')) {
    fail(`unknown option: ${arg}`);
  } else if (file === undefined) {
    file = arg;
  } else {
    fail(`unexpected argument: ${arg}`);
  }
}

if (!file) fail('provide a GIF file');
if (!Number.isInteger(minFrames) || minFrames < 1) {
  fail('--min-frames must be a positive integer');
}

const path = resolve(file);
let metadata;
try {
  metadata = await sharp(path, { animated: true }).metadata();
} catch (error) {
  fail(`cannot decode ${path}: ${error.message}`);
}

const frames = metadata.pages ?? 1;
if (metadata.format !== 'gif') fail(`expected GIF, got ${metadata.format ?? 'unknown format'}`);
if (frames < minFrames) fail(`expected at least ${minFrames} frames, got ${frames}`);

const bytes = statSync(path).size;
if (bytes === 0) fail('GIF is empty');

console.log(
  `verified ${path} (${metadata.width}x${metadata.pageHeight ?? metadata.height}, ` +
    `${frames} frames, ${bytes} bytes)`,
);
