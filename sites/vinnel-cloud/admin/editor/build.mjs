import { build } from 'esbuild';

const outfile = process.argv[2] || 'dist/editor.js';

await build({
  entryPoints: ['src/editor.mjs'],
  outfile,
  bundle: true,
  format: 'iife',
  target: 'es2022',
  minify: true,
  legalComments: 'none',
});
