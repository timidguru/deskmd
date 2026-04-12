const { deflateSync } = require("node:zlib");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const iconsetDir = path.join(root, "macos", "AppIcon.iconset");
const icnsPath = path.join(root, "macos", "AppIcon.icns");

const outputs = [
  ["icon_16x16.png", 16],
  ["icon_16x16@2x.png", 32],
  ["icon_32x32.png", 32],
  ["icon_32x32@2x.png", 64],
  ["icon_128x128.png", 128],
  ["icon_128x128@2x.png", 256],
  ["icon_256x256.png", 256],
  ["icon_256x256@2x.png", 512],
  ["icon_512x512.png", 512],
  ["icon_512x512@2x.png", 1024]
];

const crcTable = new Uint32Array(256);
for (let i = 0; i < 256; i += 1) {
  let crc = i;
  for (let bit = 0; bit < 8; bit += 1) {
    crc = crc & 1 ? 0xedb88320 ^ (crc >>> 1) : crc >>> 1;
  }
  crcTable[i] = crc >>> 0;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuffer = Buffer.from(type);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])));
  return Buffer.concat([length, typeBuffer, data, checksum]);
}

function writePng(filename, size) {
  const pixels = Buffer.alloc(size * size * 4);
  const setPixel = (x, y, r, g, b, a = 255) => {
    if (x < 0 || y < 0 || x >= size || y >= size) {
      return;
    }
    const offset = (y * size + x) * 4;
    pixels[offset] = r;
    pixels[offset + 1] = g;
    pixels[offset + 2] = b;
    pixels[offset + 3] = a;
  };
  const fillRect = (x, y, width, height, color) => {
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(size, Math.ceil(x + width));
    const y1 = Math.min(size, Math.ceil(y + height));
    for (let py = y0; py < y1; py += 1) {
      for (let px = x0; px < x1; px += 1) {
        setPixel(px, py, ...color);
      }
    }
  };
  const fillRoundedRect = (x, y, width, height, radius, color) => {
    const x0 = Math.max(0, Math.floor(x));
    const y0 = Math.max(0, Math.floor(y));
    const x1 = Math.min(size, Math.ceil(x + width));
    const y1 = Math.min(size, Math.ceil(y + height));
    for (let py = y0; py < y1; py += 1) {
      for (let px = x0; px < x1; px += 1) {
        const dx = Math.max(x + radius - px, 0, px - (x + width - radius));
        const dy = Math.max(y + radius - py, 0, py - (y + height - radius));
        if (dx * dx + dy * dy <= radius * radius) {
          setPixel(px, py, ...color);
        }
      }
    }
  };

  fillRect(0, 0, size, size, [15, 118, 110, 255]);
  const pad = size * 0.11;
  fillRoundedRect(pad, pad, size - pad * 2, size - pad * 2, size * 0.08, [247, 248, 244, 255]);
  fillRoundedRect(pad + size * 0.07, pad + size * 0.12, size - pad * 2 - size * 0.14, size * 0.045, size * 0.02, [15, 118, 110, 255]);

  const left = size * 0.28;
  const top = size * 0.4;
  const unit = size * 0.055;
  const height = unit * 5.2;
  fillRect(left, top, unit, height, [18, 32, 29, 255]);
  fillRect(left + unit, top + unit, unit, unit * 1.2, [18, 32, 29, 255]);
  fillRect(left + unit * 2, top + unit * 1.8, unit, unit * 1.2, [18, 32, 29, 255]);
  fillRect(left + unit * 3, top + unit, unit, unit * 1.2, [18, 32, 29, 255]);
  fillRect(left + unit * 4, top, unit, height, [18, 32, 29, 255]);

  const dLeft = left + unit * 6.2;
  fillRect(dLeft, top, unit, height, [18, 32, 29, 255]);
  fillRect(dLeft + unit, top, unit * 2.4, unit, [18, 32, 29, 255]);
  fillRect(dLeft + unit, top + height - unit, unit * 2.4, unit, [18, 32, 29, 255]);
  fillRect(dLeft + unit * 3.2, top + unit, unit, height - unit * 2, [18, 32, 29, 255]);

  const scanlines = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y += 1) {
    const rowOffset = y * (size * 4 + 1);
    scanlines[rowOffset] = 0;
    pixels.copy(scanlines, rowOffset + 1, y * size * 4, (y + 1) * size * 4);
  }

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", ihdr),
    chunk("IDAT", deflateSync(scanlines)),
    chunk("IEND", Buffer.alloc(0))
  ]);

  fs.writeFileSync(path.join(iconsetDir, filename), png);
}

fs.rmSync(iconsetDir, { recursive: true, force: true });
fs.mkdirSync(iconsetDir, { recursive: true });
for (const [filename, size] of outputs) {
  writePng(filename, size);
}

execFileSync("iconutil", ["-c", "icns", iconsetDir, "-o", icnsPath], { stdio: "inherit" });
