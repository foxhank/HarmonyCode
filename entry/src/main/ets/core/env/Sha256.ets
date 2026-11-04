import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';

const CHUNK: number = 4 * 1024 * 1024;
const HEX_RADIX: number = 16;
const HEX_PAD: number = 2;

/** SHA-256 of a file as lowercase hex, read in chunks; reports bytes hashed so far. */
export async function sha256File(path: string, onProgress?: (done: number) => void): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const buf = new ArrayBuffer(CHUNK);
    let offset = 0;
    while (true) {
      const n = await fileIo.read(file.fd, buf, { offset: offset });
      if (n <= 0) {
        break;
      }
      await md.update({ data: new Uint8Array(buf.slice(0, n)) });
      offset += n;
      if (onProgress !== undefined) {
        onProgress(offset);
      }
    }
  } finally {
    fileIo.closeSync(file);
  }
  const digest = await md.digest();
  let hex = '';
  for (const b of digest.data) {
    hex += b.toString(HEX_RADIX).padStart(HEX_PAD, '0');
  }
  return hex;
}
