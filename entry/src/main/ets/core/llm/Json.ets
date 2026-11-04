/** A decoded JSON object. Values are strings, numbers, booleans, arrays, nested objects or null. */
export type JsonObject = Record<string, Object>;

/**
 * Typed reads from untrusted JSON (API responses, tool arguments). Every getter tolerates
 * missing keys, nulls and wrong types by returning the fallback, so callers never crash on
 * a provider that leaves a field out.
 */
export class Json {
  /** Parses `text` as a JSON object; null when it is not valid JSON or not an object. */
  static parseObject(text: string): JsonObject | null {
    if (text.trim().length === 0) {
      return null;
    }
    try {
      const v = JSON.parse(text) as Object;
      return Json.asObject(v);
    } catch (e) {
      return null;
    }
  }

  /** `v` as an object, or null when it is an array, primitive or null. */
  static asObject(v: Object | undefined | null): JsonObject | null {
    if (v === undefined || v === null || typeof v !== 'object' || Array.isArray(v)) {
      return null;
    }
    return v as JsonObject;
  }

  static value(o: JsonObject | null | undefined, key: string): Object | undefined {
    if (o === null || o === undefined) {
      return undefined;
    }
    const v: Object | undefined = o[key];
    return v === null ? undefined : v;
  }

  static obj(o: JsonObject | null | undefined, key: string): JsonObject | null {
    return Json.asObject(Json.value(o, key));
  }

  static arr(o: JsonObject | null | undefined, key: string): Object[] {
    const v = Json.value(o, key);
    return v !== undefined && Array.isArray(v) ? v as Object[] : [];
  }

  static str(o: JsonObject | null | undefined, key: string, fallback: string = ''): string {
    const v = Json.value(o, key);
    return typeof v === 'string' ? v as string : fallback;
  }

  static num(o: JsonObject | null | undefined, key: string, fallback: number = 0): number {
    const v = Json.value(o, key);
    return typeof v === 'number' ? v as number : fallback;
  }

  static bool(o: JsonObject | null | undefined, key: string, fallback: boolean = false): boolean {
    const v = Json.value(o, key);
    return typeof v === 'boolean' ? v as boolean : fallback;
  }

  static has(o: JsonObject | null | undefined, key: string): boolean {
    return Json.value(o, key) !== undefined;
  }

  /** The objects inside an array value, skipping anything that isn't an object. */
  static objects(o: JsonObject | null | undefined, key: string): JsonObject[] {
    const out: JsonObject[] = [];
    for (const item of Json.arr(o, key)) {
      const obj = Json.asObject(item);
      if (obj !== null) {
        out.push(obj);
      }
    }
    return out;
  }
}
