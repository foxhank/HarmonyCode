// Globals isomorphic-git expects but the ArkTS runtime does not provide.
// esbuild's `inject` swaps references to these names for the exports below.
import { Buffer as BufferPolyfill } from 'buffer';

export const Buffer = typeof globalThis.Buffer !== 'undefined' ? globalThis.Buffer : BufferPolyfill;

function utf8Encode(str) {
  const out = [];
  for (let i = 0; i < str.length; i++) {
    let c = str.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
      const d = str.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) { c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00); i++; }
    }
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return new Uint8Array(out);
}

function utf8Decode(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes.buffer || bytes);
  let s = '';
  const CHUNK = 0x8000;
  const codes = [];
  for (let i = 0; i < u8.length;) {
    const b = u8[i++];
    let c;
    if (b < 0x80) c = b;
    else if (b >= 0xf0) { c = ((b & 7) << 18) | ((u8[i++] & 63) << 12) | ((u8[i++] & 63) << 6) | (u8[i++] & 63); }
    else if (b >= 0xe0) { c = ((b & 15) << 12) | ((u8[i++] & 63) << 6) | (u8[i++] & 63); }
    else if (b >= 0xc0) { c = ((b & 31) << 6) | (u8[i++] & 63); }
    else c = 0xfffd;
    if (c > 0xffff) { c -= 0x10000; codes.push(0xd800 + (c >> 10), 0xdc00 + (c & 1023)); }
    else codes.push(c);
    if (codes.length >= CHUNK) { s += String.fromCharCode.apply(null, codes); codes.length = 0; }
  }
  return s + String.fromCharCode.apply(null, codes);
}

class TextEncoderShim { get encoding() { return 'utf-8'; } encode(s = '') { return utf8Encode(String(s)); } }
class TextDecoderShim { constructor() {} get encoding() { return 'utf-8'; } decode(b) { return b ? utf8Decode(b) : ''; } }

export const TextEncoder = typeof globalThis.TextEncoder !== 'undefined' ? globalThis.TextEncoder : TextEncoderShim;
export const TextDecoder = typeof globalThis.TextDecoder !== 'undefined' ? globalThis.TextDecoder : TextDecoderShim;

export const process = typeof globalThis.process !== 'undefined' ? globalThis.process : {
  env: {}, browser: true, version: '', versions: {}, platform: 'harmonyos',
  nextTick: (fn, ...args) => Promise.resolve().then(() => fn(...args)),
  cwd: () => '/',
};

export { utf8Encode, utf8Decode };
