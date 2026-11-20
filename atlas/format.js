const esc = (v) =>
  String(v ?? '').replace(
    /[&<>"']/g,
    (c) =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[
        c
      ],
  );
const fmt = new Intl.NumberFormat('en-US', { maximumFractionDigits: 9 });
const compact = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  notation: 'compact',
  maximumFractionDigits: 2,
});
const precise = new Intl.NumberFormat('en-US', {
  style: 'currency',
  currency: 'USD',
  maximumFractionDigits: 2,
});
const missing = '—';
const present = (v) => v !== null && v !== undefined && v !== '';
const num = (v) => (present(v) ? fmt.format(v) : missing);
const money = (v) => (present(v) ? precise.format(v) : 'Undisclosed');
const safeLink = (url, label) =>
  /^https?:\/\//i.test(url ?? '')
    ? `<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(label)} ↗</a>`
    : '';

export { esc, fmt, compact, missing, present, num, money, safeLink };
