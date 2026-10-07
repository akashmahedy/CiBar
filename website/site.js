// Tiny progressive enhancement. The page and downloads work without JavaScript.
const themeControl = document.querySelector('#theme');
const systemTheme = window.matchMedia('(prefers-color-scheme: dark)');
function applyTheme(value) {
  document.documentElement.dataset.theme = value;
  const dark = value === 'dark' || (value === 'system' && systemTheme.matches);
  document.querySelectorAll('.native-pill img').forEach(image => {
    image.src = dark ? 'assets/pill-dark.webp' : 'assets/pill-light.webp';
  });
  document.querySelectorAll('.native-card img').forEach(image => {
    image.src = dark ? 'assets/word-card-dark.webp' : 'assets/word-card.webp';
  });
  document.querySelectorAll('.native-pill source, .native-card source').forEach(source => {
    source.media = value === 'system' ? '(prefers-color-scheme: dark)' : 'not all';
  });
}
if (themeControl) {
  document.documentElement.classList.add('theme-ready');
  let preference = 'system';
  try { preference = localStorage.getItem('cibar-website-theme') || 'system'; } catch {}
  if (!['system', 'light', 'dark'].includes(preference)) preference = 'system';
  themeControl.value = preference;
  applyTheme(preference);
  themeControl.addEventListener('change', () => {
    applyTheme(themeControl.value);
    try { localStorage.setItem('cibar-website-theme', themeControl.value); } catch {}
  });
  systemTheme.addEventListener('change', () => {
    if (themeControl.value === 'system') applyTheme('system');
  });
}
