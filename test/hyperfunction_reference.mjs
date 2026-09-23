// Test-only higher-order call-by-name oracle. No production compiler imports.
// Closures are deliberately retained here; production must defunctionalize them.
export class ObservationLimit extends Error {}
export function reference(limit = 256) {
  let remaining = limit;
  const tick = () => { if (remaining-- <= 0) throw new ObservationLimit(); };
  const delay = body => ({ force: body });
  const force = value => { tick(); return value.force(); };
  const make = body => ({ invoke: body });
  const invoke = (hyper, peer) => delay(() => { tick(); return force(hyper.invoke(peer)); });
  const base = value => make(() => value);
  const push = (f, tail) => make(peer => f(delay(() => force(invoke(force(peer), tail)))));
  const lift = f => push(f, delay(() => lift(f)));
  const identity = () => lift(x => x);
  const compose = (left, right) => make(peer => invoke(left,
    delay(() => compose(right, force(peer)))));
  const run = hyper => invoke(hyper, delay(identity));
  const project = (hyper, value) => invoke(hyper, delay(() => base(value)));
  const ana = (step, state) => make(peer => step(state,
    next => delay(() => force(invoke(force(peer), delay(() => ana(step, next)))))));
  return { delay, force, make, invoke, base, push, lift, identity, compose, run, project, ana };
}
