import { Transaction } from '@codemirror/state';
import { EditorView, Decoration, WidgetType, ViewPlugin, keymap } from '@codemirror/view';
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands';
import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
import { syntaxTree, syntaxHighlighting, HighlightStyle } from '@codemirror/language';
import { tags } from '@lezer/highlight';

const HEADINGS = {
  ATXHeading1: 'cm-h1',
  ATXHeading2: 'cm-h2',
  ATXHeading3: 'cm-h3',
  ATXHeading4: 'cm-h4',
  ATXHeading5: 'cm-h5',
  ATXHeading6: 'cm-h6',
};

const MARKS = new Set(['HeaderMark', 'EmphasisMark', 'StrikethroughMark', 'QuoteMark', 'LinkTitle']);

const highlightStyle = HighlightStyle.define([
  { tag: tags.heading, class: 'cm-tok-head' },
  { tag: tags.strong, class: 'cm-tok-strong' },
  { tag: tags.emphasis, class: 'cm-tok-em' },
  { tag: tags.strikethrough, class: 'cm-tok-strike' },
  { tag: tags.link, class: 'cm-tok-link' },
  { tag: tags.url, class: 'cm-tok-url' },
  { tag: tags.monospace, class: 'cm-tok-code' },
  { tag: tags.quote, class: 'cm-tok-quote' },
  { tag: tags.list, class: 'cm-tok-list' },
  { tag: tags.processingInstruction, class: 'cm-tok-mark' },
]);

function localMedia(url, mediaOrigin) {
  if (mediaOrigin && url.startsWith(mediaOrigin + '/media/')) {
    return '/public/media/' + url.slice((mediaOrigin + '/media/').length);
  }
  return url;
}

class ImageWidget extends WidgetType {
  constructor(url, alt) {
    super();
    this.url = url;
    this.alt = alt;
  }

  eq(other) {
    return other.url === this.url && other.alt === this.alt;
  }

  toDOM() {
    const img = document.createElement('img');
    img.className = 'cm-image';
    img.src = this.url;
    img.alt = this.alt;
    return img;
  }
}

function activeLines(view) {
  const lines = new Set();
  if (!view.hasFocus) return lines;
  const state = view.state;
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number;
    const last = state.doc.lineAt(range.to).number;
    for (let n = first; n <= last; n++) lines.add(n);
  }
  return lines;
}

function isHidden(node) {
  const name = node.name;
  if (MARKS.has(name)) return true;
  if (name === 'CodeMark') return node.node.parent && node.node.parent.name === 'InlineCode';
  if (name === 'LinkMark' || name === 'URL') return node.node.parent && node.node.parent.name === 'Link';
  return false;
}

function imageSource(state, node, mediaOrigin) {
  const url = node.node.getChild('URL');
  if (!url) return null;
  const text = state.doc.sliceString(node.from, node.to);
  const alt = text.slice(2, text.indexOf(']('));
  return new ImageWidget(localMedia(state.doc.sliceString(url.from, url.to), mediaOrigin), alt);
}

export function liveDecorations(view, mediaOrigin) {
  const ranges = [];
  const active = activeLines(view);
  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from,
      to,
      enter: (node) => {
        const line = view.state.doc.lineAt(node.from);
        const raw = active.has(line.number);
        const heading = HEADINGS[node.name];
        if (heading && node.from === line.from) {
          ranges.push(Decoration.line({ class: heading }).range(line.from));
        }
        if (node.name === 'Blockquote') {
          for (let pos = node.from; pos <= node.to; ) {
            const quoted = view.state.doc.lineAt(pos);
            ranges.push(Decoration.line({ class: 'cm-blockquote' }).range(quoted.from));
            pos = quoted.to + 1;
          }
        }
        if (raw) return true;
        if (node.name === 'Image') {
          const widget = imageSource(view.state, node, mediaOrigin);
          if (widget) {
            ranges.push(Decoration.replace({ widget }).range(node.from, node.to));
            return false;
          }
          return true;
        }
        if (isHidden(node)) ranges.push(Decoration.replace({}).range(node.from, node.to));
        return true;
      },
    });
  }
  return Decoration.set(ranges, true);
}

function livePreview(mediaOrigin) {
  return ViewPlugin.fromClass(
    class {
      constructor(view) {
        this.decorations = liveDecorations(view, mediaOrigin);
      }

      update(update) {
        if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) {
          this.decorations = liveDecorations(update.view, mediaOrigin);
        }
      }
    },
    { decorations: (plugin) => plugin.decorations },
  );
}

function fileHandler(onFiles) {
  return (event, source) => {
    const files = Array.from(source.files || []);
    if (!files.length) return false;
    event.preventDefault();
    onFiles(files);
    return true;
  };
}

export function createEditor(parent, options) {
  const { nonce = '', mediaOrigin = '', onChange = () => {}, onFiles = () => {}, onCommand = () => false } = options || {};
  const files = fileHandler(onFiles);

  const command = (name) => () => {
    onCommand(name);
    return true;
  };

  const view = new EditorView({
    parent,
    extensions: [
      history(),
      keymap.of([
        { key: 'Mod-b', run: command('bold') },
        { key: 'Mod-i', run: command('italic') },
        { key: 'Mod-u', run: command('underline') },
        { key: 'Mod-k', run: command('link') },
        ...historyKeymap,
        ...defaultKeymap,
      ]),
      markdown({ base: markdownLanguage }),
      syntaxHighlighting(highlightStyle),
      livePreview(mediaOrigin),
      EditorView.lineWrapping,
      EditorView.cspNonce.of(nonce),
      EditorView.updateListener.of((update) => {
        if (update.docChanged) onChange();
      }),
      EditorView.domEventHandlers({
        paste: (event) => files(event, event.clipboardData),
        drop: (event) => files(event, event.dataTransfer),
        dragover: (event) => {
          if (Array.from(event.dataTransfer.types).includes('Files')) event.preventDefault();
          return false;
        },
      }),
    ],
  });

  return {
    view,

    get value() {
      return view.state.doc.toString();
    },

    set value(text) {
      view.dispatch({
        changes: { from: 0, to: view.state.doc.length, insert: text },
        selection: { anchor: 0 },
        annotations: Transaction.addToHistory.of(false),
      });
    },

    get selectionStart() {
      return view.state.selection.main.from;
    },

    get selectionEnd() {
      return view.state.selection.main.to;
    },

    setSelectionRange(from, to) {
      view.dispatch({ selection: { anchor: from, head: to }, scrollIntoView: true });
    },

    setRangeText(text, from, to) {
      view.dispatch({ changes: { from, to, insert: text } });
    },

    focus() {
      view.focus();
    },
  };
}

if (typeof window !== 'undefined') window.markdownEditor = { create: createEditor };
