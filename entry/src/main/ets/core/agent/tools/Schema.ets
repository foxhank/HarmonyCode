import { JsonObject } from '../../llm/Json';

/** Small builders for the JSON Schemas that describe tool parameters. */
export class Schema {
  static object(properties: JsonObject, required: string[]): JsonObject {
    const o: JsonObject = { 'type': 'object', 'properties': properties, 'required': required };
    return o;
  }

  static str(description: string): JsonObject {
    const o: JsonObject = { 'type': 'string', 'description': description };
    return o;
  }

  static int(description: string): JsonObject {
    const o: JsonObject = { 'type': 'integer', 'description': description };
    return o;
  }

  static bool(description: string): JsonObject {
    const o: JsonObject = { 'type': 'boolean', 'description': description };
    return o;
  }

  static enumStr(description: string, values: string[]): JsonObject {
    const o: JsonObject = { 'type': 'string', 'description': description, 'enum': values };
    return o;
  }

  static array(description: string, items: JsonObject): JsonObject {
    const o: JsonObject = { 'type': 'array', 'description': description, 'items': items };
    return o;
  }
}
