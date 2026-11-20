// v22 (Simon 2026-11-19): a small "Full screen" button, always visible, just below every video. Where the
// browser blocks real full screen (e.g. a page shown inside an app's preview frame, which also hides the native button),
// the video fills the window instead.
(() => {
  const vids = [...document.querySelectorAll('video')];
  if (!vids.length) return;
  const icon = '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M4 9V4h5M15 4h5v5M20 15v5h-5M9 20H4v-5"/></svg>';
  const ov = document.createElement('div');
  ov.className = 'fsov'; ov.hidden = true; ov.setAttribute('role', 'dialog'); ov.setAttribute('aria-label', 'Video, full window');
  const x = document.createElement('button');
  x.type = 'button'; x.className = 'fsx'; x.textContent = '×'; x.title = 'Close (Esc)'; x.setAttribute('aria-label', 'Close full window');
  ov.append(x); document.body.append(ov);

  let cur = null, ph = null;
  const fake = v => {  // the video moves into a window-filling layer in one step, so it keeps playing
    const r = v.getBoundingClientRect();
    ph = document.createElement('div'); ph.style.cssText = `width:${r.width}px;height:${r.height}px`;
    v.replaceWith(ph); ov.prepend(v); ov.hidden = false; cur = v; x.focus();
  };
  const close = () => { if (!cur) return; ph.replaceWith(cur); ov.hidden = true; cur.focus(); cur = ph = null; };
  const open = v => {
    if (document.fullscreenEnabled) v.requestFullscreen().catch(() => fake(v));
    else fake(v);
  };

  // v22b (Simon 2026-11-19): the button sits outside the video, right-aligned just below it; a clip whose camera labels are
  // laid out around it (.camtag) gets the button below that labelled box, so the labels keep their places
  vids.forEach((v, i) => {
    const b = document.createElement('button');
    b.type = 'button'; b.className = 'fsbtn'; b.dataset.fs = v.dataset.fs = i;
    b.setAttribute('aria-label', 'Play this video full screen'); b.innerHTML = icon + '<span>Full screen</span>';
    b.addEventListener('click', () => open(v));
    (v.closest('.camtag') || v).after(b);
    // the native double-click does nothing where full screen is blocked
    v.addEventListener('dblclick', e => { if (!document.fullscreenEnabled && !cur) { e.preventDefault(); fake(v); } });
  });
  x.addEventListener('click', close);
  addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
})();
