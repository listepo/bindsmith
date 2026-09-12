import assert from 'node:assert/strict';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { extract } from '../index.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const fixture = path.resolve(here, '../../../../../fixtures/dts/greeter.d.ts');

const model = extract([fixture]);
const byName = Object.fromEntries(model.decls.map((d) => [d.name, d]));

test('every export is listed once, namespaces are dotted', () => {
  assert.deepEqual(
    model.decls.map((d) => `${d.kind}:${d.name}`).sort(),
    [
      'class:Box',
      'class:Greeter',
      'enum:Tone',
      'function:createGreeter',
      'function:utils.shout',
      'interface:GreeterOptions',
      'typeAlias:GreetCallback',
      'variable:VERSION',
    ],
  );
  assert.equal(model.version, 1);
  assert.match(model.typescript, /^\d+\.\d+/);
});

test('class members: static, overloads, accessors, private hidden', () => {
  const greeter = byName.Greeter;
  assert.equal(greeter.docs, 'Greets people.');
  const names = greeter.members.map((m) => `${m.kind}:${m.name}`);
  assert.deepEqual(names, [
    'property:version',
    'property:name',
    'constructor:constructor',
    'method:greet',
    'method:greet',
    'method:greetLater',
    'getter:uppercase',
    'setter:uppercase',
  ]);
  assert.equal(greeter.members[0].static, true);
  assert.equal(greeter.members[0].readonly, true);
  assert.deepEqual(greeter.members[2].params[1], {
    name: 'options',
    type: { k: 'ref', name: 'GreeterOptions', args: [] },
    optional: true,
    rest: false,
  });
  assert.deepEqual(greeter.members[4].returns, { k: 'array', elem: { k: 'keyword', name: 'string' } });
  assert.deepEqual(greeter.members[5].returns, {
    k: 'ref',
    name: 'Promise',
    args: [{ k: 'keyword', name: 'string' }],
  });
  assert.equal(greeter.file, path.relative(process.cwd(), fixture));
  assert.equal(typeof greeter.line, 'number');
});

test('interface: optional, literal union, callback, index signature, docs', () => {
  const options = byName.GreeterOptions;
  const [prefix, , tone, onGreet, index] = options.members;
  assert.equal(prefix.optional, true);
  assert.equal(prefix.docs, 'Text placed before the name.');
  assert.deepEqual(tone.type, {
    k: 'union',
    types: [
      { k: 'literal', value: 'formal' },
      { k: 'literal', value: 'casual' },
    ],
  });
  assert.equal(onGreet.type.k, 'fn');
  assert.deepEqual(onGreet.type.returns, { k: 'keyword', name: 'void' });
  assert.equal(index.kind, 'index');
  assert.deepEqual(index.type, { k: 'keyword', name: 'unknown' });
});

test('JSDoc tags are listed as written, links left for the driver', () => {
  const later = byName.Greeter.members.find((m) => m.name === 'greetLater');
  assert.equal(later.docs, 'Greets after a delay.');
  assert.deepEqual(later.tags, [
    { tag: 'param', name: 'delayMs', text: 'How long to wait, in milliseconds.' },
    { tag: 'returns', text: 'the greeting, once the delay has passed.' },
  ]);
  assert.equal(byName.GreeterOptions.docs, 'Options accepted by {@link Greeter}.');
});

test('enum, alias, const, generics', () => {
  assert.deepEqual(
    byName.Tone.members.map((m) => [m.name, m.value]),
    [
      ['Formal', 'formal'],
      ['Casual', 'casual'],
    ],
  );
  assert.equal(byName.GreetCallback.type.k, 'fn');
  assert.equal(byName.VERSION.isConst, true);
  assert.deepEqual(byName.VERSION.type, { k: 'keyword', name: 'string' });
  assert.deepEqual(byName.Box.typeParams, [{ name: 'T' }]);
  const map = byName.Box.members[1];
  assert.deepEqual(map.typeParams, [{ name: 'U' }]);
  assert.deepEqual(map.returns, { k: 'ref', name: 'Box', args: [{ k: 'ref', name: 'U', args: [] }] });
});
