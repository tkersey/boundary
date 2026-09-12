// Staged-source JSON: exact unsigned integers, duplicate-key
// rejection, and an explicit stack so nesting does not consume the JS stack.
const maximumSafe = BigInt(Number.MAX_SAFE_INTEGER);

export function parseExactJson(input) {
  const text = typeof input === 'string' ? input
    : new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(input);
  let cursor = 0, root, complete = false;
  const stack = [];
  const fail = (message) => { throw new SyntaxError(`${message} at character ${cursor}`); };
  const whitespace = () => { while (cursor < text.length && /[\x20\t\r\n]/.test(text[cursor])) cursor++; };
  function string() {
    if (text[cursor] !== '"') fail('expected string');
    const start = cursor++;
    while (cursor < text.length) {
      const character = text[cursor++];
      if (character === '"') return JSON.parse(text.slice(start, cursor)); // A string token only.
      if (character === '\\') cursor++;
      else if (character.charCodeAt(0) < 32) fail('control character in string');
    }
    fail('unterminated string');
  }
  function attach(value) {
    const frame = stack.at(-1);
    if (!frame) { root = value; complete = true; return; }
    if (frame.kind === 'array') frame.value.push(value);
    else frame.value[frame.key] = value;
    frame.state = 'comma';
  }
  function value() {
    whitespace();
    const first = text[cursor];
    if (first === '{' || first === '[') {
      cursor++;
      const object = first === '{';
      const output = object ? Object.create(null) : [];
      attach(output);
      stack.push({ kind: object ? 'object' : 'array', value: output, state: 'first', keys: new Set() });
    } else if (first === '"') attach(string());
    else if (first >= '0' && first <= '9') {
      const start = cursor++;
      while (text[cursor] >= '0' && text[cursor] <= '9') cursor++;
      const token = text.slice(start, cursor);
      if ((token.length > 1 && token[0] === '0') || /[.eE]/.test(text[cursor] ?? '')) {
        fail('expected a canonical unsigned integer');
      }
      const integer = BigInt(token);
      attach(integer <= maximumSafe ? Number(integer) : integer);
    } else if (text.startsWith('true', cursor)) { cursor += 4; attach(true); }
    else if (text.startsWith('false', cursor)) { cursor += 5; attach(false); }
    else if (text.startsWith('null', cursor)) { cursor += 4; attach(null); }
    else fail('expected data value');
  }
  while (!complete || stack.length) {
    whitespace();
    const frame = stack.at(-1);
    if (!frame) { value(); continue; }
    const end = frame.kind === 'object' ? '}' : ']';
    if (frame.state === 'comma') {
      if (text[cursor] === end) { cursor++; stack.pop(); continue; }
      if (text[cursor++] !== ',') fail('expected comma or closing delimiter');
      frame.state = 'next';
      whitespace();
    } else if (frame.state === 'first' && text[cursor] === end) {
      cursor++; stack.pop(); continue;
    }
    if (frame.kind === 'object') {
      const key = string();
      if (frame.keys.has(key)) fail(`duplicate key ${JSON.stringify(key)}`);
      frame.keys.add(key); frame.key = key;
      whitespace();
      if (text[cursor++] !== ':') fail('expected colon');
    }
    value();
  }
  whitespace();
  if (cursor !== text.length) fail('trailing data');
  return root;
}
