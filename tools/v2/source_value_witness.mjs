// Data-only candidates for the formal value checker. No result is trusted
// until the Lean side checks schemas and exact canonical bytes.
import assert from 'node:assert/strict';

export function decodeValueWitness(source, schema, bytes, cursor = { offset: 0 }) {
  const shape = source.schemas[schema];
  const kind = typeof shape === 'string' ? shape : Object.keys(shape)[0];
  const body = shape[kind];
  const byte = () => { assert.ok(cursor.offset < bytes.length, 'truncated value'); return bytes[cursor.offset++]; };
  const natural = () => {
    let value = 0n, shift = 0n;
    for (;;) { const part = byte(); value |= BigInt(part & 127) << shift; if (!(part & 128)) break; shift += 7n; assert.ok(shift < 70n); }
    assert.ok(value <= BigInt(Number.MAX_SAFE_INTEGER)); return Number(value);
  };
  if (kind === 'unit') return { kind: 'scalar', schema, value: '0' };
  if (kind === 'boolean') return { kind: 'scalar', schema, value: String(byte()) };
  if (/^[iu](8|16|32|64)$/.test(kind) || kind === 'enumeration') {
    const bits = kind === 'enumeration' ? 32 : Number(kind.slice(1));
    let value = 0n;
    for (let index = 0; index < bits / 8; index++) value |= BigInt(byte()) << BigInt(index * 8);
    if (kind[0] === 'i') value = BigInt.asIntN(bits, value);
    return { kind: 'scalar', schema, value: String(value) };
  }
  if (['text', 'bytes', 'bounded_text', 'bounded_bytes'].includes(kind)) {
    const length = natural(), value = Array.from({ length }, byte);
    return { kind: 'blob', schema, value };
  }
  if (kind === 'product') return { kind: 'product', schema, value: body.map((child) => decodeValueWitness(source, child, bytes, cursor)) };
  if (kind === 'sum') {
    const tag = natural(); assert.ok(tag < body.length);
    return { kind: 'variant', schema, tag, value: decodeValueWitness(source, body[tag], bytes, cursor) };
  }
  if (['array', 'seq', 'vector'].includes(kind)) {
    const count = kind === 'array' ? body.length : natural();
    const child = kind === 'seq' ? body : body.element;
    return { kind: 'sequence', schema, value: Array.from({ length: count }, () => decodeValueWitness(source, child, bytes, cursor)) };
  }
  throw new Error(`non-exportable schema ${kind}`);
}

export function exactValueWitness(source, schema, bytes) {
  const cursor = { offset: 0 }, value = decodeValueWitness(source, schema, bytes, cursor);
  assert.equal(cursor.offset, bytes.length, 'trailing value bytes'); return value;
}
