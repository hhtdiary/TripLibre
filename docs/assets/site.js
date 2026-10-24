// HHT Diary — shared header and footer for the organization and TripLibre pages. Pages sit at different
// depths (/, /vision/, /products/ios/), so every link is resolved against the site root,
// which is the folder above this script.

const ROOT = new URL('..', document.currentScript.src).href;
// Two brands share this chrome: the organization (HHT Diary) and its product (TripLibre). A page picks one
// with <html data-brand="triplibre">; anything else is an organization page.
const ORG_GITHUB = 'https://github.com/hhtdiary';
const REPO = 'https://github.com/zyang91/TripLibre';
const DOI = 'https://doi.org/10.5281/zenodo.23307589';

const BRANDS = {
  org: {
    name: 'HHT Diary',
    logo: 'assets/hhtdiary-mark.png',
    home: '',
    blurb: 'Open, local-first tools for understanding everyday travel. Free and Apache 2.0 licensed.',
    base: '© HHT Diary · Apache 2.0',
    nav: [
      { href: 'products/', title: 'Products', prefix: true },
      { href: 'vision/', title: 'Vision', prefix: true },
      { href: 'roadmap/', title: 'Roadmap', prefix: true },
      { href: 'about/', title: 'About', prefix: true },
      { href: ORG_GITHUB, title: 'GitHub' },
    ],
    footer: [
      { group: 'Organization', items: [
        { href: '', title: 'Home' },
        { href: 'vision/', title: 'Vision' },
        { href: 'roadmap/', title: 'Roadmap' },
        { href: 'about/', title: 'About' },
      ] },
      { group: 'Products', items: [
        { href: 'products/', title: 'All products' },
        { href: 'triplibre/', title: 'TripLibre' },
      ] },
      { group: 'Community', items: [
        { href: ORG_GITHUB, title: 'GitHub' },
        { href: 'triplibre/docs/contributing.html', title: 'Contributing' },
        { href: 'mailto:zhanchao@upenn.edu', title: 'Contact' },
      ] },
    ],
  },
  triplibre: {
    name: 'TripLibre',
    logo: 'assets/triplibre-logo.png',
    home: 'triplibre/',
    byline: true,
    blurb: 'A free, open-source, local-first travel diary for iPhone. A product of HHT Diary.',
    base: '© HHT Diary · TripLibre is Apache 2.0 licensed',
    nav: [
      { href: 'triplibre/', title: 'Overview' },
      { href: 'triplibre/docs/installation.html', title: 'Install' },
      { href: 'triplibre/docs/', title: 'Docs', prefix: true },
      { href: 'triplibre/story/', title: 'Story', prefix: true },
      { href: REPO, title: 'GitHub' },
    ],
    footer: [
      { group: 'TripLibre', items: [
        { href: 'triplibre/', title: 'Overview' },
        { href: 'triplibre/docs/installation.html', title: 'Install' },
        { href: 'triplibre/docs/privacy.html', title: 'Privacy' },
        { href: 'triplibre/story/', title: 'Story' },
      ] },
      { group: 'Docs', items: [
        { href: 'triplibre/docs/', title: 'Overview' },
        { href: 'triplibre/docs/using-the-app.html', title: 'Using the app' },
        { href: 'triplibre/docs/architecture.html', title: 'Architecture' },
        { href: 'triplibre/docs/contributing.html', title: 'Contributing' },
      ] },
      { group: 'Code', items: [
        { href: REPO, title: 'GitHub' },
        { href: `${REPO}/issues`, title: 'Issues' },
        { href: DOI, title: 'Cite' },
      ] },
      { group: 'HHT Diary', items: [
        { href: '', title: 'Home' },
        { href: 'vision/', title: 'Vision' },
        { href: 'roadmap/', title: 'Roadmap' },
        { href: 'about/', title: 'About' },
      ] },
    ],
  },
};
const BRAND = BRANDS[document.documentElement.dataset.brand] || BRANDS.org;

const ICONS = {
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  moon: '<svg class="moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/></svg>',
  sun: '<svg class="sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
};

// Absolute URLs (https:, mailto: …) pass through; everything else is relative to the site root.
const url = href => (/^[a-z][a-z0-9+.-]*:/i.test(href) ? href : ROOT + href);

// "vision/" for /vision/ and /vision/index.html alike.
function currentPath() {
  const here = location.href.split(/[?#]/)[0];
  return here.startsWith(ROOT) ? here.slice(ROOT.length).replace(/index\.html$/, '') : '';
}

// The product's pages carry an "by HHT Diary" endorsement that links back to the organization.
function brandLink() {
  const by = BRAND.byline ? `<small class="by">by <a href="${url('')}">HHT Diary</a></small>` : '';
  return `<span class="s-brand"><a href="${url(BRAND.home)}"><img src="${url(BRAND.logo)}" alt="" width="28" height="28">${BRAND.name}</a>${by}</span>`;
}

function buildHeader() {
  const here = currentPath();
  // First exact match, else the first section whose pages start with its path.
  const local = BRAND.nav.filter(n => !/^https?:/.test(n.href));
  const current = local.find(n => n.href === here) || local.find(n => n.prefix && here.startsWith(n.href));
  const h = document.createElement('header');
  h.className = 's-header';
  h.innerHTML = `
    <a class="skip" href="#main">Skip to content</a>
    <div class="wrap">
      ${brandLink()}
      <nav class="s-nav" id="site-nav" aria-label="Main">
        ${BRAND.nav.map(n => `<a href="${url(n.href)}"${n === current ? ' aria-current="page"' : ''}>${n.title}</a>`).join('')}
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
      <div class="cols" style="--n: ${BRAND.footer.length}">
        <div class="about">
          ${brandLink()}
          <p>${BRAND.blurb}</p>
        </div>
        ${BRAND.footer.map(g => `
          <div><h2>${g.group}</h2><ul>
            ${g.items.map(i => `<li><a href="${url(i.href)}">${i.title}</a></li>`).join('')}
          </ul></div>`).join('')}
      </div>
      <div class="base"><span>${BRAND.base}</span><span>Every trip tells a story.</span></div>
    </div>`;
  document.body.append(f);
}

document.addEventListener('DOMContentLoaded', () => {
  buildHeader();
  buildFooter();
});
