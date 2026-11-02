// Сальдо — the offer and the privacy policy. The legal text exists in Russian (the binding one) and in
// English; the other site languages read the English text with a note in their own language.
(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch { /* private mode */ } },
  };

  let li = 0;
  const tr = (key) => { const v = T[key]; return v ? (v[li] ?? v[0]) : key; };
  function pickLang() {
    const saved = store.get('lang');
    if (saved && LANGS.includes(saved)) return saved;
    for (const l of navigator.languages || [navigator.language || 'ru']) {
      const code = l.toLowerCase().slice(0, 2);
      if (LANGS.includes(code)) return code;
    }
    return 'ru';
  }
  const sel = $('#lang');
  LANGS.forEach((l, i) => sel.append(new Option(LANG_NAMES[i], l)));
  const root = document.documentElement;
  const savedTheme = store.get('theme');
  if (savedTheme) root.dataset.theme = savedTheme;
  $('#theme').addEventListener('click', () => {
    const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    store.set('theme', root.dataset.theme);
  });
  addEventListener('scroll', () => $('#top').classList.toggle('scrolled', scrollY > 8), { passive: true });

  function applyLang(lang) {
    li = Math.max(0, LANGS.indexOf(lang));
    root.lang = lang;
    sel.value = lang;
    const text = lang === 'ru' || lang === 'kk' ? 'ru' : 'en';
    $$('article[data-lang]').forEach((a) => { a.hidden = a.dataset.lang !== text; });
    $('#lgNote').hidden = lang === 'ru' || lang === 'en';
    $$('[data-i18n]').forEach((el) => { el.textContent = tr(el.dataset.i18n); });
    $$('[data-i18n-title]').forEach((el) => { el.title = tr(el.dataset.i18nTitle); });
    document.title = $(`article[data-lang="${text}"] h1`).textContent;
  }
  sel.addEventListener('change', () => { store.set('lang', sel.value); applyLang(sel.value); });
  applyLang(pickLang());
})();
