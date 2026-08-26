import assert from 'node:assert';
import { EditorState, EditorSelection } from '@codemirror/state';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { ensureSyntaxTree } from '@codemirror/language';
import { liveDecorations } from './src/editor.mjs';

function decorate(doc, cursor) {
  const state = EditorState.create({
    doc,
    selection: EditorSelection.cursor(cursor),
    extensions: [markdown({ base: markdownLanguage })],
  });
  ensureSyntaxTree(state, doc.length, 5000);
  const set = liveDecorations({ state, visibleRanges: [{ from: 0, to: doc.length }] });
  const found = [];
  set.between(0, doc.length, (from, to, value) => {
    found.push({ from, to, spec: value.spec, text: doc.slice(from, to) });
  });
  return found;
}

const hidden = (found) => found.filter((d) => d.spec.widget === undefined && d.to > d.from).map((d) => d.text);
const lineClasses = (found) => found.filter((d) => d.spec.class).map((d) => d.spec.class);

let found = decorate('**bold** text\nsecond line', 20);
assert.deepStrictEqual(hidden(found), ['**', '**'], 'emphasis marks should be hidden');

found = decorate('**bold** text\nsecond line', 3);
assert.deepStrictEqual(hidden(found), [], 'the cursor line stays raw');

found = decorate('# Title\n\nbody', 10);
assert.deepStrictEqual(hidden(found), ['#'], 'the leading hash is hidden');
assert.ok(lineClasses(found).includes('cm-h1'), 'heading line needs its class');

found = decorate('see [text](/url) here\nnext', 24);
assert.deepStrictEqual(hidden(found), ['[', ']', '(', '/url', ')'], 'only the link text survives');

found = decorate('![alt](/img.png)\nnext', 20);
const widget = found.find((d) => d.spec.widget);
assert.ok(widget, 'image should be replaced by a widget');
assert.strictEqual(widget.spec.widget.url, '/img.png');
assert.strictEqual(widget.spec.widget.alt, 'alt');

found = decorate('- item one\n- item two', 15);
assert.deepStrictEqual(hidden(found), [], 'list marks are meaningful');

found = decorate('```\ncode\n```\n\ntail', 16);
assert.deepStrictEqual(hidden(found), [], 'fence marks stay');
found = decorate('a `snip` b\nnext', 13);
assert.deepStrictEqual(hidden(found), ['`', '`'], 'inline code marks hide');

found = decorate('> one\n> two\n\ntail', 14);
assert.strictEqual(lineClasses(found).filter((c) => c === 'cm-blockquote').length, 2);

console.log('ok');
