import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { marked } from 'marked';

const [postsDir = 'posts', htmlFile = 'index.html', feedFile = 'feed.xml'] = process.argv.slice(2);

const SITE = 'https://vin.moe';
const TITLE = 'vin.moe';
const AUTHOR = 'Finlay';
const SLUG = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function parse(slug, raw) {
  const text = raw.replace(/\r\n/g, '\n');
  if (!text.startsWith('---\n')) throw new Error(`${slug}: missing front matter`);
  const rest = text.slice(4);
  const end = rest.indexOf('\n---\n');
  if (end < 0) throw new Error(`${slug}: unterminated front matter`);

  const meta = {};
  for (const line of rest.slice(0, end).split('\n')) {
    const i = line.indexOf(':');
    if (i < 0) continue;
    meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  if (!meta.title) throw new Error(`${slug}: no title`);
  if (!DATE.test(meta.date)) throw new Error(`${slug}: date must be YYYY-MM-DD, got ${meta.date}`);

  return {
    slug,
    title: meta.title,
    date: meta.date,
    draft: meta.draft === 'true',
    body: rest.slice(end + 5).replace(/^\n+/, ''),
  };
}

const posts = (existsSync(postsDir) ? readdirSync(postsDir) : [])
  .filter((f) => f.endsWith('.md'))
  .map((f) => {
    const slug = f.slice(0, -3);
    if (!SLUG.test(slug)) throw new Error(`${f}: filename is not a valid slug`);
    return parse(slug, readFileSync(join(postsDir, f), 'utf8'));
  })
  .filter((p) => !p.draft)
  .sort((a, b) => (a.date === b.date ? a.slug.localeCompare(b.slug) : b.date.localeCompare(a.date)));

const items = posts
  .map(
    (p) => `<li>
<details id="post-${p.slug}" name="post">
<summary><span class="post-title">${esc(p.title)}</span><time datetime="${p.date}">${p.date}</time></summary>
<div class="post-body">${marked.parse(p.body).trim()}</div>
</details>
</li>`,
  )
  .join('\n');

const block = posts.length
  ? `<ol class="posts">\n${items}\n</ol>`
  : '<p class="muted">Nothing published yet.</p>';

const html = readFileSync(htmlFile, 'utf8');
const marker = /<!--posts:start-->[\s\S]*?<!--posts:end-->/;
if (!marker.test(html)) throw new Error(`${htmlFile}: posts markers not found`);
writeFileSync(htmlFile, html.replace(marker, block));

const updated = posts.length ? `${posts[0].date}T00:00:00Z` : new Date().toISOString().slice(0, 19) + 'Z';
const entries = posts
  .map(
    (p) => `  <entry>
    <title>${esc(p.title)}</title>
    <link rel="alternate" type="text/html" href="${SITE}/#post-${p.slug}"/>
    <id>tag:vin.moe,${p.date.slice(0, 4)}:post/${p.slug}</id>
    <updated>${p.date}T00:00:00Z</updated>
    <content type="html">${esc(marked.parse(p.body).trim())}</content>
  </entry>`,
  )
  .join('\n');

writeFileSync(
  feedFile,
  `<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>${TITLE}</title>
  <subtitle>infrastructure, devops, software</subtitle>
  <link rel="self" type="application/atom+xml" href="${SITE}/feed.xml"/>
  <link rel="alternate" type="text/html" href="${SITE}/"/>
  <id>${SITE}/</id>
  <updated>${updated}</updated>
  <author><name>${AUTHOR}</name><email>a@vin.moe</email></author>
${entries}
</feed>
`,
);

console.log(`rendered ${posts.length} post(s)`);
