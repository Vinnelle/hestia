// The frame is driven off location.hash so a reload, a bookmark or the back
// button all land on the same service. Only frameable services carry data-slug;
// the rest are plain target=_blank links and never reach this router.
const frame = document.getElementById('service-frame');
const empty = document.getElementById('frame-empty');
const back = document.getElementById('frame-back');
const frameTitle = document.getElementById('frame-title');
const routed = document.querySelectorAll('.service-link[data-slug]');

function show(slug) {
  let active = null;
  for (const el of routed) {
    const match = el.dataset.slug === slug;
    if (match) active = el;
    el.classList.toggle('active', match);
  }

  if (!active) {
    // Unknown or empty hash — fall back to the tile grid rather than a blank frame.
    frame.hidden = true;
    frame.removeAttribute('src');
    empty.hidden = false;
    back.hidden = true;
    document.title = 'admin — vinnel.cloud';
    return;
  }

  empty.hidden = true;
  frame.hidden = false;
  back.hidden = false;
  frameTitle.textContent = active.dataset.label;
  document.title = active.dataset.label + ' — vinnel.cloud';

  // Only reassign src on a real change: rewriting it reloads the app and would
  // throw away whatever the user had open.
  if (frame.getAttribute('src') !== active.dataset.url) {
    frame.setAttribute('src', active.dataset.url);
  }
}

addEventListener('hashchange', () => show(location.hash.slice(1)));
show(location.hash.slice(1));

document.getElementById('sidebar-toggle').addEventListener('click', () => {
  document.getElementById('sidebar').classList.toggle('sidebar--collapsed');
});

const menuBtn = document.getElementById('user-menu-btn');
menuBtn.addEventListener('click', () => {
  const expanded = menuBtn.getAttribute('aria-expanded') === 'true';
  document.getElementById('user-dropdown').hidden = expanded;
  menuBtn.setAttribute('aria-expanded', String(!expanded));
});
