import assert from 'node:assert/strict';
import test from 'node:test';
import { parseExactJson } from '../../tools/v2/exact_json.mjs';

test('metadata retains exact integers before any Number conversion', () => {
  const parsed = parseExactJson('{"safe":9007199254740991,"large":9007199254740993,"max":18446744073709551615}');
  assert.equal(parsed.safe, 9007199254740991);
  assert.equal(parsed.large, 9007199254740993n);
  assert.equal(parsed.max, 18446744073709551615n);
});

test('duplicate decoded keys and ambiguous numeric forms reject', () => {
  for (const input of ['{"a":1,"a":2}', '{"a":1,"\\u0061":2}', '01', '-1',
    '1.0', '1e0', '{}{}', '[1,]', '{"a":1,}', '', '[', '{', '"unterminated']) {
    assert.throws(() => parseExactJson(input), SyntaxError, input);
  }
  assert.throws(() => parseExactJson(Uint8Array.of(0xff)), TypeError);
  assert.throws(() => parseExactJson(Uint8Array.of(0xef, 0xbb, 0xbf, 0x30)), SyntaxError);
});

test('deep data uses an explicit stack and prototype keys remain data', () => {
  let value = parseExactJson('['.repeat(20000) + '0' + ']'.repeat(20000));
  for (let depth = 0; depth < 20000; depth++) value = value[0];
  assert.equal(value, 0);
  const object = parseExactJson('{"__proto__":{"polluted":true},"text":"a\\n\\u03bb"}');
  assert.equal(Object.getPrototypeOf(object), null);
  assert.equal(object.__proto__.polluted, true);
  assert.equal(object.text, 'a\nλ');
  assert.equal({}.polluted, undefined);
});
