import test from 'node:test';
import assert from 'node:assert/strict';
import { reference, ObservationLimit } from './hyperfunction_reference.mjs';

test('constant lift leaves its infinite reciprocal demand unused', () => {
  const h = reference();
  assert.equal(h.force(h.run(h.lift(() => h.delay(() => 42)))), 42);
});

test('base ignores divergent peer and product observation ignores another field', () => {
  const h = reference();
  const divergent = h.run(h.identity());
  assert.equal(h.force(h.invoke(h.base(h.delay(() => 42)), h.delay(() => {
    throw new Error('unused peer entered');
  }))), 42);
  const pair = h.delay(() => [h.delay(() => 9), divergent]);
  assert.equal(h.force(h.force(pair)[0]), 9);
});

test('identity exhausts a bounded observation; exhaustion is not a result', () => {
  const h = reference(64);
  assert.throws(() => h.force(h.run(h.identity())), ObservationLimit);
});

test('checked failure occurs only when demanded', () => {
  const h = reference();
  const fault = h.delay(() => { throw new RangeError('checked overflow'); });
  assert.equal(h.force(h.project(h.lift(() => h.delay(() => 3)), fault)), 3);
  assert.throws(() => h.force(h.project(h.lift(x => x), fault)), /checked overflow/);
});

test('ana adaptively asks twice across distinct endpoints and returns non-tail work', () => {
  const h = reference();
  const visits = [];
  const producer = h.ana((state, query) => h.delay(() => {
    visits.push(state);
    if (state === 1) return 'x';
    if (state === 2) return 'long';
    const first = h.force(query(1));
    const second = h.force(query(first + 1));
    return `${first}:${second}!`;
  }), 0);
  // H<string, number> answers using the complementary H<number, string>.
  const consumer = h.make(tail => h.delay(() =>
    h.force(h.project(h.force(tail), h.delay(() => 7))).length));
  assert.equal(h.force(h.invoke(producer, h.delay(() => consumer))), '1:4!');
  assert.deepEqual(visits, [0, 1, 2]);
});

test('projection and composition agree with hand-derived finite observations', () => {
  const h = reference();
  const add = h.lift(x => h.delay(() => h.force(x) + 2));
  const twice = h.lift(x => h.delay(() => h.force(x) * 2));
  assert.equal(h.force(h.project(add, h.delay(() => 5))), 7);
  assert.equal(h.force(h.project(h.compose(twice, add), h.delay(() => 5))), 14);
});

test('two ana participants retain both non-tail callers through reciprocal demand', () => {
  const h = reference(256);
  const trace = [];
  const producer = h.ana((state, query) => h.delay(() => {
    trace.push('producer');
    const answer = h.force(query(true));
    trace.push('producer-return');
    return answer + 10;
  }), false);
  const consumer = h.ana((state, query) => h.delay(() => {
    trace.push(state ? 'consumer-successor' : 'consumer');
    if (state) return 19;
    const answer = h.force(query(true));
    trace.push('consumer-return');
    return answer + 13;
  }), false);
  assert.equal(h.force(h.invoke(consumer, h.delay(() => producer))), 42);
  assert.deepEqual(trace, ['consumer', 'producer', 'consumer-successor',
    'producer-return', 'consumer-return']);
});

test('composition preserves distinct endpoint values', () => {
  const h = reference(1024);
  const right = h.lift(x => h.delay(() => h.force(x) ? 41 : 0));
  const left = h.lift(x => h.delay(() => ({ok:h.force(x)===41,value:h.force(x)+1})));
  assert.deepEqual(h.force(h.project(h.compose(left,right),h.delay(()=>true))), {ok:true,value:42});
});
