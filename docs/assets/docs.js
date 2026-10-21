// HHT documentation — shared chrome. Every page is just <main> content; the header, sidebar,
// "On this page" outline and prev/next links are built here from NAV, so adding a page means
// adding one entry below.

const NAV = [
  { group: 'Get started', items: [
    { href: 'index.html', title: 'Overview' },
    { href: 'installation.html', title: 'Installation' },
    { href: 'using-the-app.html', title: 'Using the app' },
    { href: 'ui-guide.html', title: 'UI guide' },
  ] },
  { group: 'Concepts', items: [
    { href: 'architecture.html', title: 'Architecture' },
    { href: 'inference.html', title: 'How inference works' },
    { href: 'data.html', title: 'Data model & export' },
    { href: 'privacy.html', title: 'Privacy' },
  ] },
  { group: 'Vision & research', items: [
    { href: 'vision.html', title: 'Vision' },
    { href: 'roadmap.html', title: 'Roadmap' },
    { href: 'research.html', title: 'Research uses & limitations' },
    { href: 'validation.html', title: 'Validation' },
  ] },
  { group: 'Reference', items: [
    { href: 'data-dictionary.html', title: 'Data dictionary' },
    { href: 'api.html', title: 'Developer API' },
    { href: 'contributing.html', title: 'Contributing' },
  ] },
  { group: 'About', items: [
    { href: 'developer.html', title: 'Meet the developer' },
  ] },
  { group: 'Links', items: [
    { href: 'backup/', title: 'Project story', ext: true },
    { href: 'https://github.com/zyang91/HHT-app', title: 'GitHub', ext: true },
  ] },
];

const REPO = 'https://github.com/zyang91/HHT-app';

const ICONS = {
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  moon: '<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
  sun: '<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
  github: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 .5a11.5 11.5 0 0 0-3.6 22.4c.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.2 1.2a11 11 0 0 1 5.8 0C17.3 4.3 18.3 4.6 18.3 4.6c.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6A11.5 11.5 0 0 0 12 .5z"/></svg>',
};

function currentFile() {
  const f = location.pathname.split('/').pop();
  return f && f.endsWith('.html') ? f : 'index.html';
}

function slug(text) {
  return text.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
}

function buildHeader() {
  const h = document.createElement('header');
  h.className = 'dx-header';
  h.innerHTML = `
    <button class="icon-btn menu-btn" aria-label="Open navigation">${ICONS.menu}</button>
    <a class="dx-brand" href="index.html"><img src="assets/hht-logo.png" alt="">HHT <span class="tag">docs</span></a>
    <nav>
      <a class="hide-sm" href="installation.html">Install</a>
      <a class="hide-sm" href="roadmap.html">Roadmap</a>
      <a class="hide-sm" href="api.html">API</a>
      <a class="hide-sm" href="backup/">Project story</a>
      <a class="icon-btn" href="${REPO}" aria-label="GitHub repository">${ICONS.github}</a>
      <button class="icon-btn theme-btn" aria-label="Toggle dark mode">${ICONS.moon}${ICONS.sun}</button>
    </nav>`;
  document.body.prepend(h);

  h.querySelector('.menu-btn').addEventListener('click', () => document.body.classList.toggle('nav-open'));
  h.querySelector('.theme-btn').addEventListener('click', () => {
    const root = document.documentElement;
    const dark = root.dataset.theme
      ? root.dataset.theme === 'dark'
      : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('hht-docs-theme', root.dataset.theme); } catch (e) {}
  });
}

function buildSidebar(layout) {
  const here = currentFile();
  const aside = document.createElement('aside');
  aside.className = 'dx-sidebar';
  aside.innerHTML = NAV.map(g => `
    <h4>${g.group}</h4>
    ${g.items.map(i => `<a href="${i.href}" class="${i.ext ? 'ext' : ''} ${i.href === here ? 'active' : ''}">${i.title}</a>`).join('')}
  `).join('');
  layout.prepend(aside);
  aside.addEventListener('click', e => { if (e.target.closest('a')) document.body.classList.remove('nav-open'); });
  document.addEventListener('click', e => {
    if (document.body.classList.contains('nav-open') && !e.target.closest('.dx-sidebar, .menu-btn')) {
      document.body.classList.remove('nav-open');
    }
  });
}

function buildToc(layout, content) {
  const heads = [...content.querySelectorAll('h2, h3')].filter(h => !h.closest('.card, .api'));
  heads.forEach(h => {
    if (!h.id) h.id = slug(h.textContent);
    const a = document.createElement('a');
    a.className = 'anchor'; a.href = '#' + h.id; a.textContent = '#'; a.tabIndex = -1; a.setAttribute('aria-hidden', 'true');
    h.append(a);
  });
  const toc = document.createElement('aside');
  toc.className = 'dx-toc';
  if (heads.length > 1) {
    toc.innerHTML = '<h5>On this page</h5>' + heads.map(h =>
      `<a href="#${h.id}" class="${h.tagName.toLowerCase()}">${h.firstChild.textContent.trim()}</a>`).join('');
  }
  layout.append(toc);

  const links = [...toc.querySelectorAll('a')];
  if (!links.length) return;
  const spy = () => {
    let cur = heads[0];
    for (const h of heads) if (h.getBoundingClientRect().top < 120) cur = h;
    links.forEach(l => l.classList.toggle('active', l.getAttribute('href') === '#' + cur.id));
  };
  addEventListener('scroll', spy, { passive: true });
  spy();
}

function buildPager(content) {
  const flat = NAV.flatMap(g => g.items).filter(i => !i.ext);
  const i = flat.findIndex(p => p.href === currentFile());
  if (i < 0) return;
  const prev = flat[i - 1], next = flat[i + 1];
  const pager = document.createElement('div');
  pager.className = 'pager';
  pager.innerHTML =
    (prev ? `<a class="prev" href="${prev.href}"><small>← Previous</small>${prev.title}</a>` : '') +
    (next ? `<a class="next" href="${next.href}"><small>Next →</small>${next.title}</a>` : '');
  content.append(pager);

  const foot = document.createElement('footer');
  foot.className = 'dx-foot';
  foot.innerHTML = `<span>HHT · Apache 2.0 · from a travel survey of one to travel surveys within reach</span>
    <span><a href="vision.html">Vision</a> · <a href="roadmap.html">Roadmap</a> ·
    <a href="https://doi.org/10.5281/zenodo.23307589">Cite</a> ·
    <a href="${REPO}/edit/main/docs/${currentFile()}">Edit this page on GitHub</a></span>`;
  content.append(foot);
}

// Tiny highlighter: comments, strings and a handful of keywords. Enough for short snippets.
function highlight(pre) {
  const lang = pre.dataset.lang;
  if (!lang || lang === 'text') return;
  const code = pre.querySelector('code') || pre;
  const kw = {
    swift: 'import|let|var|func|try|throws|return|for|in|if|else|guard|struct|class|enum|case|public|static|nil|true|false|await',
    python: 'from|import|def|return|for|in|if|else|None|True|False|as|with|print',
    bash: 'cd|make|brew|git|python3?|pip|source|xcodegen|open|sqlite3',
    sql: 'SELECT|FROM|WHERE|GROUP BY|ORDER BY|JOIN|ON|AS|AND|OR|COUNT|SUM|ROUND|LIMIT|DESC|LEFT',
  }[lang];
  const comment = lang === 'sql' ? '--[^\\n]*' : lang === 'swift' ? '\\/\\/[^\\n]*' : '#[^\\n]*';
  const re = new RegExp(`(${comment})|("(?:[^"\\\\\\n]|\\\\.)*"|'(?:[^'\\\\\\n]|\\\\.)*')` +
    (kw ? `|\\b(${kw})\\b` : ''), 'g');
  const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const src = code.textContent;
  let out = '', last = 0, m;
  while ((m = re.exec(src))) {
    out += esc(src.slice(last, m.index));
    const cls = m[1] ? 'tok-c' : m[2] ? 'tok-s' : 'tok-k';
    out += `<span class="${cls}">${esc(m[0])}</span>`;
    last = re.lastIndex;
  }
  code.innerHTML = out + esc(src.slice(last));
}

function addCopyButtons() {
  document.querySelectorAll('.dx-content pre').forEach(pre => {
    highlight(pre);
    const b = document.createElement('button');
    b.className = 'copy-btn'; b.type = 'button'; b.textContent = 'Copy';
    b.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText((pre.querySelector('code') || pre).innerText);
        b.textContent = 'Copied';
      } catch (e) { b.textContent = 'Press ⌘C'; }
      setTimeout(() => (b.textContent = 'Copy'), 1400);
    });
    pre.append(b);
  });
}

// Wide tables scroll sideways; make each wrapper focusable so keyboard users can scroll it too.
function labelScrollRegions(content) {
  content.querySelectorAll('.table-wrap').forEach(w => {
    let h = w.previousElementSibling;
    while (h && !/^H[2-4]$/.test(h.tagName)) h = h.previousElementSibling;
    w.tabIndex = 0;
    w.setAttribute('role', 'region');
    w.setAttribute('aria-label', h ? `Table: ${h.firstChild.textContent.trim()}` : 'Table');
  });
}

document.addEventListener('DOMContentLoaded', () => {
  const main = document.querySelector('main.dx-main');
  const content = main.querySelector('.dx-content');
  const layout = document.createElement('div');
  layout.className = 'dx-layout';
  main.replaceWith(layout);
  layout.append(main);
  buildHeader();
  buildSidebar(layout);
  buildToc(layout, content);
  buildPager(content);
  addCopyButtons();
  labelScrollRegions(content);
});
