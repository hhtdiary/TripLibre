// HHT Diary — shared header and footer for the organization pages. Pages sit at different
// depths (/, /vision/, /products/ios/), so every link is resolved against the site root,
// which is the folder above this script.

const ROOT = new URL('..', document.currentScript.src).href;
const REPO = 'https://github.com/zyang91/TripLibre';

const NAV = [
  { href: 'products/', title: 'Products' },
  { href: 'vision/', title: 'Vision' },
  { href: 'roadmap/', title: 'Roadmap' },
  { href: 'docs/', title: 'Docs' },
  { href: REPO, title: 'GitHub' },
];

const FOOTER = [
  { group: 'Organization', items: [
    { href: '', title: 'Home' },
    { href: 'vision/', title: 'Vision' },
    { href: 'roadmap/', title: 'Roadmap' },
    { href: 'backup/', title: 'Project story' },
  ] },
  { group: 'Products', items: [
    { href: 'products/', title: 'All products' },
    { href: 'products/ios/', title: 'TripLibre for iOS' },
    { href: 'installation.html', title: 'Install' },
  ] },
  { group: 'Docs', items: [
    { href: 'docs/', title: 'Overview' },
    { href: 'using-the-app.html', title: 'Using the app' },
    { href: 'architecture.html', title: 'Architecture' },
    { href: 'privacy.html', title: 'Privacy' },
  ] },
  { group: 'Community', items: [
    { href: REPO, title: 'GitHub' },
    { href: 'contributing.html', title: 'Contributing' },
    { href: `${REPO}/issues`, title: 'Issues' },
    { href: 'https://doi.org/10.5281/zenodo.23307589', title: 'Cite' },
  ] },
];

const ICONS = {
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  moon: '<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
  sun: '<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
};

const url = href => (/^https?:/.test(href) ? href : ROOT + href);

// "vision/" for /vision/ and /vision/index.html alike.
function currentPath() {
  const here = location.href.split(/[?#]/)[0];
  return here.startsWith(ROOT) ? here.slice(ROOT.length).replace(/index\.html$/, '') : '';
}

function buildHeader() {
  const here = currentPath();
  const h = document.createElement('header');
  h.className = 's-header';
  h.innerHTML = `
    <a class="skip" href="#main">Skip to content</a>
    <div class="wrap">
      <a class="s-brand" href="${url('')}"><img src="${url('assets/hht-logo.png')}" alt="" width="28" height="28">HHT Diary</a>
      <nav class="s-nav" id="site-nav" aria-label="Main">
        ${NAV.map(n => {
          const cur = here.startsWith(n.href) && !/^https?:/.test(n.href);
          return `<a href="${url(n.href)}"${cur ? ' aria-current="page"' : ''}>${n.title}</a>`;
        }).join('')}
      </nav>
      <div class="s-tools">
        <button class="icon-btn theme-btn" type="button" aria-label="Toggle dark mode">${ICONS.moon}${ICONS.sun}</button>
        <button class="icon-btn menu-btn" type="button" aria-label="Open navigation" aria-controls="site-nav" aria-expanded="false">${ICONS.menu}</button>
      </div>
    </div>`;
  document.body.prepend(h);

  const menu = h.querySelector('.menu-btn');
  menu.addEventListener('click', () => {
    const open = document.body.classList.toggle('nav-open');
    menu.setAttribute('aria-expanded', String(open));
  });
  h.querySelector('.theme-btn').addEventListener('click', () => {
    const root = document.documentElement;
    const dark = root.dataset.theme
      ? root.dataset.theme === 'dark'
      : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('hht-docs-theme', root.dataset.theme); } catch (e) {}
  });
}

function buildFooter() {
  const f = document.createElement('footer');
  f.className = 's-footer';
  f.innerHTML = `
    <div class="wrap">
      <div class="cols">
        <div class="about">
          <a class="s-brand" href="${url('')}"><img src="${url('assets/hht-logo.png')}" alt="" width="28" height="28">HHT Diary</a>
          <p>Open, local-first tools for understanding everyday travel. Free and Apache 2.0 licensed.</p>
        </div>
        ${FOOTER.map(g => `
          <div><h2>${g.group}</h2><ul>
            ${g.items.map(i => `<li><a href="${url(i.href)}">${i.title}</a></li>`).join('')}
          </ul></div>`).join('')}
      </div>
      <div class="base"><span>© HHT Diary · Apache 2.0</span><span>Every trip tells a story.</span></div>
    </div>`;
  document.body.append(f);
}

document.addEventListener('DOMContentLoaded', () => {
  buildHeader();
  buildFooter();
});
