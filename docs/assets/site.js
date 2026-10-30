// TripLibre — shared header and footer for the product pages (/, /story/). Pages sit at different depths,
// so every link is resolved against the site root, which is the folder above this script. The organization,
// HHT Diary, has its own site at hhtdiary.org (github.com/hhtdiary/hhtdiary.github.io); its links are absolute.

const ROOT = new URL('..', document.currentScript.src).href;
const ORG = 'https://hhtdiary.org/';
const REPO = 'https://github.com/zyang91/TripLibre';
const DOI = 'https://doi.org/10.5281/zenodo.23307589';

const BRAND = {
  name: 'TripLibre',
  logo: 'assets/triplibre-logo.png',
  home: '',
  byline: true,
  blurb: 'A free, open-source, local-first travel diary for iPhone. A product of HHT Diary.',
  base: '© HHT Diary · TripLibre is Apache 2.0 licensed',
  nav: [
    { href: '', title: 'Overview' },
    { href: 'docs/installation.html', title: 'Install' },
    { href: 'docs/', title: 'Docs', prefix: true },
    { href: 'story/', title: 'Story', prefix: true },
    { href: REPO, title: 'GitHub' },
  ],
  footer: [
    { group: 'TripLibre', items: [
      { href: '', title: 'Overview' },
      { href: 'docs/installation.html', title: 'Install' },
      { href: 'docs/privacy.html', title: 'Privacy' },
      { href: 'story/', title: 'Story' },
    ] },
    { group: 'Docs', items: [
      { href: 'docs/', title: 'Overview' },
      { href: 'docs/using-the-app.html', title: 'Using the app' },
      { href: 'docs/architecture.html', title: 'Architecture' },
      { href: 'docs/contributing.html', title: 'Contributing' },
    ] },
    { group: 'Code', items: [
      { href: REPO, title: 'GitHub' },
      { href: `${REPO}/issues`, title: 'Issues' },
      { href: DOI, title: 'Cite' },
    ] },
    { group: 'HHT Diary', items: [
      { href: ORG, title: 'Home' },
      { href: ORG + 'vision/', title: 'Vision' },
      { href: ORG + 'roadmap/', title: 'Roadmap' },
      { href: ORG + 'about/', title: 'About' },
    ] },
  ],
};

const ICONS = {
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  moon: '<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
  sun: '<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
};

// Absolute URLs (https:, mailto: …) pass through; everything else is relative to the site root.
const url = href => (/^[a-z][a-z0-9+.-]*:/i.test(href) ? href : ROOT + href);

// "story/" for /story/ and /story/index.html alike.
function currentPath() {
  const here = location.href.split(/[?#]/)[0];
  return here.startsWith(ROOT) ? here.slice(ROOT.length).replace(/index\.html$/, '') : '';
}

// The product's pages carry an "by HHT Diary" endorsement that links back to the organization.
function brandLink() {
  const by = BRAND.byline ? `<span class="by">by <a href="${ORG}">HHT Diary</a></span>` : '';
  return `<a class="brand" href="${url(BRAND.home)}"><img src="${url(BRAND.logo)}" alt="" width="42" height="42">${BRAND.name}</a>${by}`;
}

function buildHeader() {
  const here = currentPath();
  // First exact match, else the first section whose pages start with its path.
  const local = BRAND.nav.filter(n => !/^https?:/.test(n.href));
  const current = local.find(n => n.href === here) || local.find(n => n.prefix && here.startsWith(n.href));
  const h = document.createElement('header');
  h.className = 'nav';
  h.innerHTML = `
    <a class="skip" href="#main">Skip to content</a>
    ${brandLink()}
    <nav class="nav-links" id="site-nav" aria-label="Main">
      ${BRAND.nav.map(n => `<a href="${url(n.href)}"${n === current ? ' aria-current="page"' : ''}>${n.title}</a>`).join('')}
    </nav>
    <div class="tools">
      <button class="icon-btn theme-btn" type="button" aria-label="Toggle dark mode">${ICONS.moon}${ICONS.sun}</button>
      <button class="icon-btn menu-btn" type="button" aria-label="Open navigation" aria-controls="site-nav" aria-expanded="false">${ICONS.menu}</button>
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
    <div class="in">
      <div class="mega" aria-hidden="true">${BRAND.name}</div>
      <div class="fcols" style="--n: ${BRAND.footer.length}">
        <div class="about">
          ${brandLink()}
          <p>${BRAND.blurb}</p>
        </div>
        ${BRAND.footer.map(g => `
          <div><h2>${g.group}</h2><ul>
            ${g.items.map(i => `<li><a href="${url(i.href)}">${i.title}</a></li>`).join('')}
          </ul></div>`).join('')}
      </div>
      <div class="fbase"><span>${BRAND.base}</span><span>Every trip tells a story.</span></div>
    </div>`;
  document.body.append(f);
}

document.addEventListener('DOMContentLoaded', () => {
  buildHeader();
  buildFooter();
});
