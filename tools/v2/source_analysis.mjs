// Untrusted finite witnesses. Lean checks both path ranks and closure against
// its independent staged-source dependency relation.
import assert from 'node:assert/strict';

export function sourceAnalysis(source) {
  const valueCount = source.values.length, termCount = source.terms.length;
  const total = valueCount + termCount + source.functions.length;
  const valueNode = (id) => { assert.ok(Number.isSafeInteger(id) && id >= 0 && id < valueCount); return id; };
  const termNode = (id) => { assert.ok(Number.isSafeInteger(id) && id >= 0 && id < termCount); return valueCount + id; };
  const functionNode = (id) => {
    assert.ok(Number.isSafeInteger(id) && id >= 0 && id < source.functions.length);
    return valueCount + termCount + id;
  };
  const dependencies = Array.from({ length: total }, () => []);
  const facts = Array.from({ length: total }, () => new Map());
  const add = (parent, child, excludes = []) => dependencies[parent].push({ child, excludes: new Set(excludes) });
  for (const [id, value] of source.values.entries()) {
    const expression = value.expression;
    if (Object.hasOwn(expression, 'variable')) {
      assert.ok(Number.isSafeInteger(expression.variable) && expression.variable >= 0 && expression.variable < source.variables.length);
      facts[id].set(expression.variable, 0);
    } else if (expression.primitive) {
      for (const child of expression.primitive.operands) add(id, valueNode(child));
    } else if (Object.hasOwn(expression, 'lambda')) add(id, functionNode(expression.lambda));
    else assert.ok(Object.hasOwn(expression, 'literal'));
  }
  for (const [id, term] of source.terms.entries()) {
    const parent = termNode(id), kind = Object.keys(term)[0], data = term[kind];
    const value = (id) => { if (id !== null && id !== undefined) add(parent, valueNode(id)); };
    const values = (ids) => ids.forEach(value);
    const child = (id, excludes = []) => add(parent, termNode(id), excludes);
    switch (kind) {
      case 'value': case 'dispose': case 'fail': value(data); break;
      case 'bind': child(data.value); child(data.next, [data.variable]); break;
      case 'conditional': value(data.condition); child(data.when_true); child(data.when_false); break;
      case 'call': add(parent, functionNode(data.function)); values(data.arguments); break;
      case 'apply': value(data.computation); values(data.arguments); break;
      case 'perform': value(data.capability); value(data.payload); values(data.bodies ?? []); values(data.use_site_capabilities ?? []); break;
      case 'handle': value(data.body); values(data.arguments); values(data.state); break;
      case 'resume_value': value(data.resumption); value(data.argument); break;
      case 'resume_with': value(data.resumption); value(data.argument); values(data.state); break;
      case 'resume_computation': value(data.resumption); value(data.computation); break;
      case 'protect': value(data.body); value(data.cleanup); values(data.arguments); value(data.resource); break;
      case 'with_region': value(data.body); values(data.arguments); break;
      case 'yield_then': child(data); break;
      case 'match_sum': value(data.value); for (const branch of data.cases) child(branch.body, [branch.variable]); break;
      case 'unpack_product': value(data.value); child(data.body, data.variables); break;
      default: throw new Error(`unknown staged term ${kind}`);
    }
  }
  for (const [id, fn] of source.functions.entries()) add(functionNode(id), termNode(fn.body), fn.parameters);
  let changed = true;
  while (changed) {
    changed = false;
    for (let parent = 0; parent < total; parent++) for (const { child, excludes } of dependencies[parent]) {
      for (const [variable, rank] of facts[child]) {
        if (excludes.has(variable)) continue;
        const previous = facts[parent].get(variable);
        if (previous === undefined || rank + 1 < previous) {
          facts[parent].set(variable, rank + 1);
          changed = true;
        }
      }
    }
  }
  const rows = facts.map((row) => [...row].sort(([a], [b]) => a - b));
  return { values: rows.slice(0, valueCount), terms: rows.slice(valueCount, valueCount + termCount), functions: rows.slice(valueCount + termCount) };
}

export function analysisLean(facts) {
  const rows = (items) => `[${items.map((row) => `[${row.map(([variable, rank]) => `(${variable}, ${rank})`).join(',')}]`).join(',')}]`;
  return `{ values := ${rows(facts.values)}, terms := ${rows(facts.terms)}, functions := ${rows(facts.functions)} }`;
}
