import { evaluationReview, reviewSources } from './evaluations.js';
import { countryProfile } from './profile.js';
import { plotGrid } from './plot-grid.js';
import { esc, fmt, compact, missing, present, num, money, safeLink } from './format.js';
import { contributorPreview, contributorView } from './contributors.js';
import { select } from 'd3-selection';
import { zoom, zoomIdentity } from 'd3-zoom';
import { decompressSync, strFromU8 } from 'fflate';

const $ = (id) => document.getElementById(id);
const snap = JSON.parse($('snapshot').textContent);
$('snapshot').remove();
const countries = new Map(snap.countries.map((c) => [c.iso3, c]));
const catalogue = new Map(snap.sources.map((s) => [s.source_id, s]));
const agencySource = snap.contributors.source;
catalogue.set(agencySource.source_id, agencySource);
const contributorPrefs = { scope: 'country', source: 'funding_agency', year: null, actor: null, timeline: 'leaders', expanded: false, eximPage: 0 };
const donors = { USA: 'United States', CHN: 'China' };
const sourceNames = {
  greenbook: 'Greenbook',
  dfc: 'DFC',
  fa: 'ForeignAssistance.gov · archived country file',
  us_sector_review: 'ForeignAssistance.gov · sector file', kenya_debt: 'Kenya National Treasury', pacific: 'Lowy Pacific Aid Map', mcc_calendar: 'MCC compact calendars',
  sector: 'USAID GeoCenter',
  gcdf: 'AidData GCDF 3.0',
  clg: 'AidData CLG 1.0',
  ppi: 'World Bank PPI',
  gates: 'Gates Foundation',
  mcc: 'MCC indicators',
  agoa: 'AGOA',
  ftf: 'Feed the Future',
  moz: 'MCC evaluation',
  export: 'World Bank',
  import: 'World Bank',
};
const state = {
  code: 'HND',
  tab: 'Overview',
  provider: 'all',
  source: 'all',
  query: '',
  page: 0,
};
const tabs = ['Overview', 'U.S. contributors', 'Funding', 'Results', 'Programs', 'Trade context'];
const icons = {
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
  pin: '<path d="M19 10c0 5-7 11-7 11S5 15 5 10a7 7 0 1 1 14 0Z"/><circle cx="12" cy="10" r="2.3"/>',
  reset: '<path d="M4 9a8 8 0 1 1 1 9M4 3v6h6"/>',
  download: '<path d="M12 3v12m-5-5 5 5 5-5M4 16v4h16v-4"/>',
  Overview:
    '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  'U.S. contributors': '<path d="M4 4v16h17M7 7h12M7 11h8M7 15h4"/>',
  Funding: '<path d="M3 20h18M6 16v-5m6 5V4m6 12V8"/>',
  Results: '<path d="M4 18 9 12l4 2 7-9m-6 0h6v6"/>',
  Programs:
    '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M8 8h8M8 12h8m-8 4h5"/>',
  'Trade context': '<path d="M3 8h17m-5-5 5 5-5 5M21 16H4m5 5-5-5 5-5"/>',
};
const icon = (name) =>
  `<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">${icons[name]}</svg>`;
document
  .querySelectorAll('[data-icon]')
  .forEach((el) => (el.innerHTML = icon(el.dataset.icon)));
const sourceLabel = (id) => sourceNames[id] ?? id;
const providerBadge = (d) =>
  `<span class="provider ${d === 'CHN' ? 'chn' : ''}">${donors[d]}</span>`;
const coverage = (c) =>
  c.us && c.cn
    ? 'Both providers'
    : c.us
      ? 'U.S. only'
      : c.cn
        ? 'China only'
        : 'No records';
const mapKeys = {
  coverage: {
    'Both providers': '#a2c3aa',
    'U.S. only': '#729db5',
    'China only': '#c18462',
    'No records': '#566f71',
  },
  equity: {
    'U.S. higher': '#729db5',
    'China higher': '#c18462',
    'Equal disclosed totals': '#a2c3aa',
    'No paired amounts': '#566f71',
    'Incomplete sponsor disclosures': '#c3ae83',
  },
};
function mapCategory(c) {
  if ($('mapMode').value === 'coverage') return coverage(c);
  if (c.us_equity == null || c.cn_equity == null) return 'No paired amounts';
  if (!c.us_equity_complete || !c.cn_equity_complete) return 'Incomplete sponsor disclosures';
  if (c.us_equity === c.cn_equity) return 'Equal disclosed totals';
  return c.us_equity > c.cn_equity ? 'U.S. higher' : 'China higher';
}
function color(c) {
  return mapKeys[$('mapMode').value][mapCategory(c)];
}
const buttons = ['sourcesBtn', 'methodsBtn'];
let localContributions, overallContributions;
let data, review, programs, byFinance, byResult, series, pageRows, focused;
function decodeBundle(blob) {
  const bytes = Uint8Array.from(atob(blob), (c) =>
    c.charCodeAt(0),
  );
  return JSON.parse(strFromU8(decompressSync(bytes)));
}
const key = (provider, id) => provider + '|' + id;
function indexRows(rows, id) {
  const index = new Map();
  for (const r of rows) {
    const k = key(r.provider, r[id]);
    if (!index.has(k)) index.set(k, []);
    index.get(k).push(r);
  }
  return index;
}
function parent(row) {
  return programs.get(key(row.provider, row.program_id ?? row.id));
}
function aggregate(rows) {
  const known = rows.filter((f) => f.usd !== null);
  return {
    n: rows.length,
    known: known.length,
    value: known.length ? known.reduce((a, f) => a + f.usd, 0) : null,
  };
}
const definitions = [
  {
    id: 'us_sector_review',
    provider: 'USA',
    label: 'All-sector disbursements',
    period: 'FY',
  },
  {
    id: 'greenbook',
    provider: 'USA',
    label: 'Economic assistance obligations',
    period: 'FY',
  },
  { id: 'clg', provider: 'CHN', label: 'Face-value commitments', period: 'CY' },
  {
    id: 'gcdf',
    provider: 'CHN',
    label: 'Adjusted official commitments',
    period: 'CY',
  },
];
function annual(def) {
  const groups = new Map();
  for (const f of data.finance) {
    if (
      f.provider !== def.provider ||
      parent(f).source_id !== def.id ||
      !f.eligible_for_summary ||
      f.flow_year == null
    )
      continue;
    if (def.id === 'greenbook' && f.period_ref === '1976 transition quarter')
      continue;
    if (def.id === 'clg' && f.measure !== 'face-value commitment (CLG)')
      continue;
    if (def.id === 'gcdf' && f.measure !== 'adjusted commitment') continue;
    if (!groups.has(f.flow_year)) groups.set(f.flow_year, []);
    groups.get(f.flow_year).push(f);
  }
  return [...groups]
    .sort((a, b) => a[0] - b[0])
    .map(([year, rows]) => ({ year, ...aggregate(rows) }));
}

// All database jurisdictions can be selected by name or ISO code. Tiny polygons also get point targets.
const svg = select('#map'),
  layer = svg.append('g'),
  mapPaths = layer.append('g');
layer
  .insert('path', ':first-child')
  .attr('class', 'watergrid')
  .attr('d', snap.map.grid);
function addGeo(node, code) {
  const c = countries.get(code);
  node.attr('class', 'geo').attr('fill', c ? color(c) : '#566f71');
  if (!c) return;
  node
    .attr('data-code', code)
    .attr('aria-label', c.name)
    .on('click', (event) => {
      if (!event.defaultPrevented) choose(code);
    })
    .on('pointermove', (event) => {
      const tip = $('maptip'),
        box = $('map').parentElement.getBoundingClientRect();
      tip.textContent =
        $('mapMode').value === 'equity'
          ? c.name +
            ' · U.S. ' +
            (c.us_equity == null ? 'no disclosed total' : money(c.us_equity)) +
            ' · China ' +
            (c.cn_equity == null ? 'no disclosed total' : money(c.cn_equity))
          : c.name + ' · ' + coverage(c);
      tip.hidden = false;
      tip.style.left =
        Math.max(
          0,
          Math.min(
            event.clientX - box.left + 10,
            box.width - tip.offsetWidth - 4,
          ),
        ) + 'px';
      tip.style.top = Math.max(0, event.clientY - box.top - 32) + 'px';
      node.classed('hover', true);
    })
    .on('pointerleave', () => {
      node.classed('hover', false);
      $('maptip').hidden = true;
    });
}
for (const f of snap.map.shapes)
  addGeo(mapPaths.append('path').attr('d', f.path), f.code);
for (const c of snap.countries.filter((c) => c.area < 8)) {
  const dot = layer
    .append('circle')
    .attr('cx', c.point[0])
    .attr('cy', c.point[1])
    .attr('r', 2.3);
  addGeo(dot, c.iso3);
  dot.classed('point', true);
}
function paintMap() {
  const mode = $('mapMode').value;
  svg.selectAll('[data-code]').attr('fill', function () {
    return color(countries.get(this.dataset.code));
  });
  $('legend').innerHTML = Object.entries(mapKeys[mode])
    .map(
      ([label, fill]) =>
        `<span><i style="background:${fill}"></i>${label}</span>`,
    )
    .join('');
  if (mode === 'equity')
    $('legend').insertAdjacentHTML(
      'afterbegin',
      '<b>Disclosed equity · 1999–2023</b>',
    );
}
$('mapMode').onchange = paintMap;
paintMap();
const marker = layer.append('g').attr('class', 'marker');
const badge = marker.append('g');
badge
  .append('circle')
  .attr('r', 8)
  .attr('fill', '#f9cf79')
  .attr('fill-opacity', '.28');
badge
  .append('circle')
  .attr('r', 3.5)
  .attr('fill', '#ffdb80')
  .attr('stroke', '#18323a')
  .attr('stroke-width', 1);
const labelBox = badge
  .append('rect')
  .attr('y', -21)
  .attr('height', 17)
  .attr('rx', 3)
  .attr('fill', '#ffdb80');
const mapLabel = badge
  .append('text')
  .attr('y', -9)
  .attr('fill', '#19343c')
  .attr('font-size', 11)
  .attr('font-weight', 600);
let transform = zoomIdentity;
const zoomer = zoom()
  .scaleExtent([1, 12])
  .extent([
    [0, 0],
    [1000, 485],
  ])
  .translateExtent([
    [-70, -40],
    [1070, 525],
  ])
  .on('zoom', (event) => {
    transform = event.transform;
    layer.attr('transform', transform);
    badge.attr('transform', `scale(${1 / transform.k})`);
    $('maptip').hidden = true;
  });
svg.call(zoomer).on('dblclick.zoom', null);
$('zoomIn').onclick = () => svg.call(zoomer.scaleBy, 1.7);
$('zoomOut').onclick = () => svg.call(zoomer.scaleBy, 1 / 1.7);
$('resetMap').onclick = () => svg.call(zoomer.transform, zoomIdentity);
function mark(c) {
  svg.selectAll('.geo.active').classed('active', false);
  svg.selectAll(`[data-code="${c.iso3}"]`).classed('active', true);
  marker.attr('transform', `translate(${c.point.join(',')})`);
  const useCode = c.name.length > 30;
  mapLabel.attr('font-family', useCode ? 'var(--mono)' : 'var(--sans)')
    .text(useCode ? c.iso3 : c.name);
  const w = mapLabel.node().getComputedTextLength() + 14;
  const x = c.point[0] > 770 ? -w - 5 : 6;
  labelBox.attr('x', x).attr('width', w);
  mapLabel.attr('x', x + 7);
}
// Country picker supports keyboard selection independently of the map.
const normalize = (s) =>
  s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim();
const aliases = {
  USA: 'united states america us',
  CHN: 'prc china',
  KOR: 'south korea',
  PRK: 'north korea',
  GBR: 'uk britain united kingdom',
  CIV: 'ivory coast',
  TUR: 'turkey',
  VNM: 'vietnam',
  PSE: 'palestine west bank gaza',
  TWN: 'taiwan',
  COD: 'dr congo',
  COG: 'republic of congo',
  MMR: 'burma',
  SWZ: 'swaziland',
};
const sorted = [...countries.values()].sort((a, b) =>
  a.name.localeCompare(b.name),
);
let options = [],
  active = -1;
function search() {
  const term = normalize($('search').value);
  options = sorted.filter((c) =>
    normalize(c.name + ' ' + c.iso3 + ' ' + (aliases[c.iso3] ?? '')).includes(
      term,
    ),
  );
  active = -1;
  $('matches').innerHTML = options.length
    ? options
        .map(
          (c, i) =>
            `<button type="button" role="option" tabindex="-1" id="opt-${i}" data-code="${c.iso3}" aria-selected="false">${esc(c.name)}<small>${c.iso3}</small></button>`,
        )
        .join('')
    : '<p class="emptymsg">No matching country</p>';
  $('matches').hidden = false;
  $('search').setAttribute('aria-expanded', 'true');
  $('search').removeAttribute('aria-activedescendant');
}
function closeSearch() {
  $('matches').hidden = true;
  $('search').setAttribute('aria-expanded', 'false');
  $('search').removeAttribute('aria-activedescendant');
}
$('search').addEventListener('focus', search);
$('search').addEventListener('input', search);
$('matches').addEventListener('pointerdown', (e) => e.preventDefault());
$('matches').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (b) choose(b.dataset.code, true);
});
$('search').addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    closeSearch();
    return;
  }
  if (e.key === 'Enter' && !$('matches').hidden && options.length) {
    e.preventDefault();
    choose(options[Math.max(0, active)].iso3, true);
    return;
  }
  if (!['ArrowDown', 'ArrowUp'].includes(e.key)) return;
  e.preventDefault();
  if ($('matches').hidden) search();
  if (!options.length) return;
  active = Math.max(
    0,
    Math.min(options.length - 1, active + (e.key === 'ArrowDown' ? 1 : -1)),
  );
  [...$('matches').children].forEach((b, i) =>
    b.setAttribute('aria-selected', i === active),
  );
  $('search').setAttribute('aria-activedescendant', 'opt-' + active);
  $('opt-' + active).scrollIntoView({ block: 'nearest' });
});
document.addEventListener('focusin', (e) => {
  if (!e.target.closest('.lookup')) closeSearch();
});
document.addEventListener('pointerdown', (e) => {
  if (!e.target.closest('.lookup')) closeSearch();
});
document.addEventListener('keydown', (e) => {
  if (
    e.key === '/' &&
    !$('drawer').open &&
    !e.target.closest('input,textarea,select')
  ) {
    e.preventDefault();
    $('search').focus();
    search();
  }
});
function choose(code, fromSearch = false) {
  const c = countries.get(code);
  if (!c) return;
  const changed = state.code !== code;
  state.code = code;
  state.page = 0;
  state.query = '';
  state.provider = 'all';
  state.source = 'all';
  closeSearch();
  $('search').value = '';
  if (fromSearch) svg.call(zoomer.transform, zoomIdentity);
  if (changed || !data) {
    data = decodeBundle(snap.bundles[code]);
    review = decodeBundle(snap.evaluations[code]);
    localContributions = decodeBundle(snap.contributors.scopes[code]);
    Object.assign(contributorPrefs, { scope: 'country', year: null, actor: null, timeline: 'leaders', expanded: false, eximPage: 0 });
    programs = new Map(data.program.map((p) => [key(p.provider, p.id), p]));
    byFinance = indexRows(data.finance, 'program_id');
    byResult = indexRows(data.result, 'program_id');
    series = Object.fromEntries(definitions.map((d) => [d.id, annual(d)]));
  }
  $('countryName').textContent = c.name;
  $('location').textContent = c.region + ' · ' + code;
  mark(c);
  renderProfile();
  renderEvidence();
  $('announce').textContent =
    c.name +
    ' selected. ' +
    c.us +
    ' U.S. and ' +
    c.cn +
    ' Chinese source records.';
}
function renderProfile() {
  $('profileStats').innerHTML = ['USA', 'CHN']
    .map((provider) => {
      const order = provider === 'USA' ? ['us_sector_review', 'greenbook'] : ['clg', 'gcdf'];
      const id = order.find((id) => series[id].length),
        r = id ? series[id].at(-1) : null;
      const def = definitions.find((d) => d.id === id);
      return `<div class="profileStat"><div class="statLine">${providerBadge(provider)}<span class="metric ${r?.value == null ? 'empty' : ''}">${r?.value != null ? compact.format(r.value) : r ? 'Undisclosed' : 'No observation'}</span></div><p class="statNote">${r ? `${esc(def.label)} · ${def.period} ${r.year}${r.known < r.n ? ` · ${r.known}/${r.n} amounts disclosed` : ''}` : 'No annual public finance figure in the selected series'}</p></div>`;
    })
    .join('');
}
function download(name, contents, type) {
  const url = URL.createObjectURL(new Blob([contents], { type })),
    a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1500);
}
$('download').onclick = () => {
  const ids = new Set([
    'iso',
    ...data.program.map((r) => r.source_id),
    ...snap.profiles[state.code].agreements.map(r => r.source_id),
    ...snap.profiles[state.code].organizations.map(r => r.source_id),
    ...(snap.profiles[state.code].goods.length ? ['census_goods','schedule_c'] : []),
    ...reviewSources, ...review.programs.map(r => r.source_id), ...review.reports.map(r => r.source_id),
    ...data.context.map((r) => r.source_id),
    ...data.result.map((r) => r.timing_source_id).filter(Boolean),
  ]);
  download(
    state.code + '-country-evidence.json',
    JSON.stringify(
      {
        country: countries.get(state.code).name,
        iso3: state.code,
        code_system: countries.get(state.code).code_system,
        sources: snap.sources.filter(s => ids.has(s.source_id)),
        us_relationship_profile: snap.profiles[state.code],
        post_completion_review: review,
        us_contributors: localContributions,
        ...data,
      },
      null,
      2,
    ),
    'application/json',
  );
};
$('tabs').innerHTML = tabs
  .map((t) => `<button data-tab="${t}">${icon(t)} ${t}</button>`)
  .join('');
function activate(tab, source = 'all') {
  state.tab = tab;
  state.source = source;
  state.query = '';
  state.provider = 'all';
  state.page = 0;
  renderEvidence();
}
$('tabs').onclick = (e) => {
  const t = e.target.closest('[data-tab]');
  if (t) activate(t.dataset.tab);
};
function section(title, sub = '', tools = '') {
  return `<div class="sectionhead"><div><h2 class="sectiontitle">${esc(title)}</h2>${sub ? `<p class="sectionnote">${esc(sub)}</p>` : ''}</div>${tools}</div>`;
}
function resultValue(r) {
  if (r.actual == null) return r.actual_text ?? 'Unreported';
  const sign = r.comparator === '>' ? '> ' : r.comparator === '<' ? '< ' : '';
  if (r.unit === 'USD per year')
    return sign + compact.format(r.actual) + ' / year';
  if (r.unit === 'current USD') return sign + compact.format(r.actual);
  return sign + fmt.format(r.actual) + (r.unit ? ' ' + r.unit : '');
}
function rankResults(a, b) {
  const priorities = [
    'Difference in differences',
    'Program report',
    'Reported before/after',
    'Reported operational output',
    'Quarterly program monitoring',
    'Program monitoring',
    'Customs records',
  ];
  const rank = (r) =>
    (r.actual == null ? 100 : 0) +
    (r.level === 'Outcome' ? 0 : r.level === 'Output' ? 10 : 20) +
    (priorities.includes(r.method)
      ? priorities.indexOf(r.method)
      : priorities.length);
  return rank(a) - rank(b) || (b.observed_year ?? 0) - (a.observed_year ?? 0) || a.id.localeCompare(b.id);
}
function equity() {
  const vals = ['USA', 'CHN'].map((provider) =>
    aggregate(
      data.finance.filter(
        (f) =>
          f.provider === provider &&
          parent(f).source_id === 'ppi' &&
          f.eligible_for_summary,
      ),
    ),
  );
  const top = Math.max(1, ...vals.map((r) => r.value ?? 0));
  return `<section class="panel"><h3>Infrastructure sponsor equity</h3><p class="hint">Disclosed subtotal for listed stakes at financial close · 1999–2023 · includes state-owned sponsors</p>${vals.map((r, i) => `<div class="equityrow"><div>${providerBadge(i ? 'CHN' : 'USA')}<b>${r.value !== null ? compact.format(r.value) : r.n ? 'Undisclosed' : 'No records'}</b></div><div class="track ${i ? 'chn' : ''}"><b style="width:${((r.value ?? 0) / top) * 100}%"></b></div><small>${r.known} of ${r.n} sponsor records disclose equity</small></div>`).join('')}<button class="linkBtn" data-jump="Funding" data-filter="ppi">Inspect sponsor records →</button></section>`;
}
function featured() {
  const eligible = data.result
    .filter(
      (r) =>
        r.actual != null && (parent(r).source_id !== 'mcc' || r.observed_year != null) &&
        ['Outcome', 'Output', 'Preference use'].includes(r.level),
    )
    .sort(rankResults);
  const r = eligible[0];
  if (r?.provider === 'USA' && snap.profiles[state.code].evidence.some(e => e.id === r.id)) return '';
  return `<section class="panel"><h3>Reported country result</h3>${r ? `<div class="featured"><span class="sourcetag">${donors[r.provider]} · ${esc(r.method)} · ${esc(sourceLabel(parent(r).source_id))}${r.observed_year ? ' · ' + r.observed_year : ' · Observation year unreported'}</span><p class="value">${esc(resultValue(r))}</p><h4>${esc(r.indicator)}</h4></div><button class="linkBtn" data-record-kind="result" data-record-id="${esc(r.id)}" data-provider="${r.provider}">Read evidence and source →</button>` : '<p class="emptymsg">No numeric outcome, output or preference-use observation in this release.</p>'}</section>`;
}
function history(def) {
  const rows = series[def.id],
    known = rows.filter((r) => r.value != null);
  let chart = '<p class="emptymsg">No disclosed annual amount.</p>';
  if (known.length) {
    const years = rows.map((r) => r.year),
      low = Math.min(0, ...known.map((r) => r.value)),
      high = Math.max(0, ...known.map((r) => r.value));
    const lo = years[0],
      hi = years.at(-1),
      x = (year) => lo === hi ? 214 : 53 + ((year - lo) / (hi - lo)) * 323,
      y = (v) => 70 - ((v - low) / Math.max(1, high - low)) * 56;
    const ticks = [...new Set([low, high])];
    const yearTicks = [...new Set([lo, hi])];
    chart = `<svg class="miniChart" viewBox="0 0 400 96" role="img" aria-label="${esc(def.label)} by year"><title>${esc(def.label)} in current USD, ${lo}–${hi}</title>
      ${plotGrid(yearTicks.map(x), ticks.map(y), 53, 376, 14, 70)}
      ${ticks.map((v) => `<text class="chartlabel" x="48" y="${y(v) + 3}" text-anchor="end">${compact.format(v)}</text>`).join('')}
      ${known.map((r) => `<line x1="${x(r.year)}" x2="${x(r.year)}" y1="${y(0)}" y2="${y(r.value)}" stroke="${def.provider === 'USA' ? '#327b78' : '#a55732'}" stroke-width="${Math.min(9, 170 / Math.max(1, hi - lo))}"/><circle cx="${x(r.year)}" cy="${y(r.value)}" r="2.8" fill="${def.provider === 'USA' ? '#327b78' : '#a55732'}"><title>${r.year} · ${money(r.value)} · ${r.known}/${r.n} amounts</title></circle>`).join('')}
      ${yearTicks.map((year) => `<text class="chartlabel" x="${x(year)}" y="91" text-anchor="middle">${year}</text>`).join('')}</svg>`;
  }
  return `<section class="panel"><span class="sourcetag">${donors[def.provider]} · ${esc(sourceLabel(def.id))}</span><h3>${esc(def.label)}</h3>${chart}<button class="linkBtn" data-history="${def.id}">Annual values →</button></section>`;
}
function paymentsOverview() {
  const draws = data.finance.filter(f => f.measure === 'borrower-reported drawdown');
  const payments = data.finance.filter(f => f.provider === 'CHN' && f.measure === 'disbursement');
  if (!draws.length && !payments.length) return '';
  const amounts = new Map();
  for (const f of draws) {
    const k = [f.period_ref, f.reported_currency].join(' · ');
    amounts.set(k, (amounts.get(k) ?? 0) + f.reported_amount);
  }
  const lines = [...amounts].map(([k,v]) => esc(k) + ' ' + v.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2}));
  return '<section class="panel"><h3>Reported Chinese payments</h3>' +
    (draws.length ? `<p>Kenya’s Treasury reports ${draws.length} facility drawdowns. ${lines.join(' · ')}</p><button class="linkBtn" data-jump="Funding" data-filter="kenya_debt">Inspect the facilities →</button>` : '') +
    (payments.length ? `<p>AidData reports ${payments.length} dated disbursement observations. These cover selected facilities.</p>` : '') + '</section>';
}
function overview() {
  return (
    section('Country overview') + countryProfile(snap.profiles[state.code], localContributions) + contributorPreview(localContributions) +
    `<div class="overviewGrid">${equity()}${featured()}${paymentsOverview()}</div>` +
    section(
      'Public finance over time',
      'Current U.S. dollars. Each series has its own scale, reporting basis and years of coverage.',
    ) +
    `<div class="charts">${definitions.map(history).join('')}</div>`
  );
}
function renderContributors() {
  if (contributorPrefs.scope === 'all' && !overallContributions)
    overallContributions = decodeBundle(snap.contributors.scopes.ALL);
  const all = contributorPrefs.scope === 'all';
  return contributorView(all ? overallContributions : localContributions, contributorPrefs, countries.get(state.code).name, catalogue);
}

function contextView() {
  const rows = data.context;
  if (!rows.length)
    return (
      section('Trade context') +
      '<p class="bigempty">No national import or export lead-time observations in these releases.</p>'
    );
  const years = [...new Set(rows.map((r) => r.year))].sort((a, b) => a - b),
    values = new Map(rows.map((r) => [r.source_id + r.year, r.days]));
  return (
    section(
      'Trade context',
      'National median logistics lead times in survey years. These observations cover the country as a whole.',
    ) +
    `<div class="tablewrap"><table><thead><tr><th>Survey year</th><th>Import lead time</th><th>Export lead time</th></tr></thead><tbody>${years
      .map(
        (year) =>
          `<tr><td>${year}</td>${['import', 'export']
            .map((s) => {
              const v = values.get(s + year);
              return `<td>${v == null ? 'No observation' : num(v) + ' days'}</td>`;
            })
            .join('')}</tr>`,
      )
      .join('')}</tbody></table></div>
    <p class="hint">World Bank Logistics Performance Index · ${safeLink(catalogue.get('import').publisher_url, 'Import series')} · ${safeLink(catalogue.get('export').publisher_url, 'Export series')}</p>`
  );
}
const ledgerInfo = {
  Funding: {
    name: 'Funding records',
    type: 'finance',
    desc: 'Inspect the amount, instrument and reporting basis for each entry.',
    headers: [
      'Provider',
      'Program or project',
      'Measure',
      'Period',
      'Reported amount',
    ],
  },
  Results: {
    name: 'Reported results',
    type: 'result',
    desc: 'Inspect the baseline, target, actual value and evidence method.',
    headers: ['Provider', 'Indicator', 'Method', 'Actual'],
  },
  Programs: {
    name: 'Program records',
    type: 'program',
    desc: 'Source records include projects, country accounts and trade-preference observations.',
    headers: ['Provider', 'Program or project', 'Channel', 'Year'],
  },
};
function ledger() {
  const info = ledgerInfo[state.tab];
  const ids = [...new Set(data[info.type].map((row) => parent(row).source_id))];
  if (state.source !== 'all' && !ids.includes(state.source))
    ids.push(state.source);
  const choices = ids
    .sort((a, b) => sourceLabel(a).localeCompare(sourceLabel(b)))
    .map((id) => `<option value="${esc(id)}">${esc(sourceLabel(id))}</option>`)
    .join('');
  const filters = `<div class="filters"><input id="rowQuery" type="search" aria-label="Search records" placeholder="Search records" value="${esc(state.query)}"><select id="donor" aria-label="Filter by provider"><option value="all">Both providers</option><option value="USA">United States</option><option value="CHN">China</option></select><select id="sourceFilter" aria-label="Filter by source"><option value="all">All sources</option>${choices}</select></div>`;
  return section(info.name, info.desc, filters) + '<div id="records"></div>';
}
function renderTable() {
  const info = ledgerInfo[state.tab],
    rows = data[info.type],
    term = normalize(state.query);
  pageRows = rows.filter((r) => {
    if (state.provider !== 'all' && r.provider !== state.provider) return false;
    const p = parent(r);
    if (state.source !== 'all' && p.source_id !== state.source) return false;
    if (!term) return true;
    return normalize(
      [
        p.name,
        p.id,
        p.actor,
        p.status,
        p.channel,
        p.sector,
        p.source_id,
        sourceLabel(p.source_id),
        p.locator,
        r.measure,
        r.instrument,
        r.period_ref,
        r.id,
        r.indicator,
        r.method,
        r.year ?? r.flow_year ?? r.observed_year,
      ]
        .filter(present)
        .join(' '),
    ).includes(term);
  });
  if (info.type === 'result') pageRows.sort(rankResults);
  const total = pageRows.length,
    pageSize = 12;
  state.page = Math.min(
    state.page,
    Math.max(0, Math.ceil(total / pageSize) - 1),
  );
  const start = state.page * pageSize;
  if (!total) {
    $('records').innerHTML =
      '<p class="bigempty">' +
      (rows.length
        ? 'No records match these filters.'
        : 'No ' + esc(info.name.toLowerCase()) + ' in these releases.') +
      '</p>';
    return;
  }
  const body = pageRows
    .slice(start, start + pageSize)
    .map((r, i) => {
      const p = parent(r),
        main = info.type === 'result' ? r.indicator : p.name;
      const rest =
        info.type === 'finance'
          ? `<td>${esc(r.measure)}</td><td>${esc(r.period_ref)}</td><td class="mnum">${esc(reportedMoney(r))}</td>`
          : info.type === 'result'
            ? `<td>${esc(r.method)}</td><td class="mnum">${esc(resultValue(r))}</td>`
            : `<td>${esc(p.channel)}</td><td>${p.year ?? missing}</td>`;
      return `<tr><td>${providerBadge(r.provider)}</td><td><button class="rowlink" data-row="${start + i}">${esc(main)}</button><div class="sourceLine">${esc(sourceLabel(p.source_id))}</div></td>${rest}</tr>`;
    })
    .join('');
  $('records').innerHTML =
    `<div class="tablewrap"><table><thead><tr>${info.headers.map((t) => '<th>' + t + '</th>').join('')}</tr></thead><tbody>${body}</tbody></table></div>
    <div class="pager"><span>${fmt.format(start + 1)}–${fmt.format(Math.min(start + pageSize, total))} of ${fmt.format(total)}</span><button class="smallbtn" data-page="-1" ${start === 0 ? 'disabled' : ''}>Previous</button><button class="smallbtn" data-page="1" ${start + pageSize >= total ? 'disabled' : ''}>Next</button></div>`;
}
function renderEvidence() {
  $('tabs')
    .querySelectorAll('button')
    .forEach((b) =>
      b.setAttribute('aria-current', String(b.dataset.tab === state.tab)),
    );
  $('evidence').innerHTML =
    state.tab === 'Overview'
      ? overview()
      : state.tab === 'U.S. contributors'
        ? renderContributors()
        : state.tab === 'Trade context'
        ? contextView()
        : (state.tab === 'Results' ? evaluationReview(review, countries.get(state.code), snap.reviewed_countries.map(code => countries.get(code)), catalogue) : '') + ledger();
  const jump = document.getElementById('evaluationCountry');
  if (jump) jump.onchange = () => { if (jump.value) choose(jump.value, true); };
  if (ledgerInfo[state.tab]) {
    $('sourceFilter').value = state.source;
    $('sourceFilter').onchange = (e) => {
      state.source = e.target.value;
      state.page = 0;
      renderTable();
    };
    $('donor').value = state.provider;
    $('donor').onchange = (e) => {
      state.provider = e.target.value;
      state.page = 0;
      renderTable();
    };
    $('rowQuery').oninput = (e) => {
      state.query = e.target.value;
      state.page = 0;
      renderTable();
    };
    renderTable();
  }
}
function dl(fields) {
  return (
    '<dl>' +
    fields
      .filter(([, v]) => present(v))
      .map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`)
      .join('') +
    '</dl>'
  );
}
function showDialog(title, html) {
  if (!$('drawer').open) focused = document.activeElement;
  $('drawerTitle').textContent = title;
  $('drawerBody').innerHTML = html;
  if (!$('drawer').open) $('drawer').showModal();
  $('drawer').scrollTop = 0;
}
$('closeDrawer').onclick = () => $('drawer').close();
$('drawer').addEventListener('click', (e) => {
  if (
    e.target === $('drawer') &&
    e.clientX < $('drawer').getBoundingClientRect().left
  )
    $('drawer').close();
});
$('drawer').addEventListener('close', () => {
  if (focused?.isConnected) focused.focus({ preventScroll: true });
});
function citations(p) {
  const s = catalogue.get(p.source_id);
  return `<h3>Source</h3><p>${esc(s.title)}</p>${dl([
    ['Record locator', p.locator],
    ['Source ID', s.source_id],
  ])}
    <p>${[safeLink(p.citation, 'Project citation'), safeLink(s.download_url, 'Pinned source file'), safeLink(s.publisher_url, 'Publisher')].filter(Boolean).join(' · ')}</p>`;
}
function reportedMoney(f) {
  return f.reported_currency && f.reported_amount != null
    ? f.reported_currency + ' ' + new Intl.NumberFormat('en-US', {minimumFractionDigits:2, maximumFractionDigits:2}).format(f.reported_amount)
    : money(f.usd);
}
function financeDetail(f) {
  return dl([
    ['Measure', f.measure],
    ['Reported amount', reportedMoney(f)], ['Period start', f.period_start], ['Period end', f.period_end],
    ['Period', f.period_ref],
    ['Instrument', f.instrument],
    ['Estimated amount', f.amount_estimated],
    ['Included in source summary', f.eligible_for_summary ? 'Yes' : 'No'],
  ]);
}
function resultDetail(r) {
  const p = parent(r);
  return (
    `<h3>${esc(r.indicator)}</h3>` +
    dl([
      ['Actual', resultValue(r)],
      ['Baseline', r.baseline_text ?? r.baseline],
      ['Baseline year', r.baseline_year],
      ['Target', r.target_text ?? r.target],
      ['Observed year', r.observed_year ?? 'Unreported'], ['Period start', r.period_start], ['Period end', r.period_end], ['Dating basis', r.dating_basis],
      ['Indicator level', r.level],
      ['Method', r.method],
      ['Unit', r.unit],
      ['Indicator ID', r.id],
    ]) +
    `<p>${esc(r.interpretation)}</p>${r.timing_source_id ? safeLink(catalogue.get(r.timing_source_id).download_url, "Timing source") : ""}<p class="hint">${esc(p.name)}</p>`
  );
}
function openRecord(r, kind) {
  const p = parent(r),
    id = key(p.provider, p.id);
  const intro = `<span class="provider ${p.provider === 'CHN' ? 'chn' : ''}">${donors[p.provider]}</span> <span class="sourcetag"> · ${esc(countries.get(state.code).name)}</span>`;
  const info = dl([
    ['Program', p.name],
    ['Actor', p.actor], ['Sponsor ownership (%)', p.sponsor_ownership_pct],
    ['Implied stake from 100% sole ownership of reported equity', p.implied_sole_sponsor_equity_usd == null ? null : money(p.implied_sole_sponsor_equity_usd)],
    ['Channel', p.channel],
    ['Sector', p.sector],
    ['Status', p.status],
    ['Period', p.period ?? p.year],
    ['Source record ID', p.id],
    [
      'Entire project investment',
      p.project_investment_usd == null ? null : money(p.project_investment_usd),
    ],
  ]);
  if (kind === 'result') {
    showDialog(
      'Result evidence',
      intro +
        resultDetail(r) +
        citations(p) +
        `<button class="linkBtn" data-program="${esc(p.id)}" data-provider="${p.provider}">View linked program →</button>`,
    );
    return;
  }
  const finance = byFinance.get(id) ?? [],
    results = byResult.get(id) ?? [];
  showDialog(
    kind === 'finance' ? 'Funding record' : 'Program record',
    intro +
      (kind === 'finance' ? financeDetail(r) : '') +
      info +
      (p.details ? `<h3>Source description</h3><p>${esc(p.details)}</p>` : '') +
      (finance.length
        ? `<details><summary>All linked financial observations (${finance.length})</summary>${finance.map(financeDetail).join('<hr>')}</details>`
        : '') +
      (results.length
        ? `<details><summary>Linked result indicators (${results.length})</summary>${results.map(resultDetail).join('<hr>')}</details>`
        : '') +
      citations(p),
  );
}
$('drawerBody').addEventListener('click', (e) => {
  const b = e.target.closest('[data-program]');
  if (b)
    openRecord(
      programs.get(key(b.dataset.provider, b.dataset.program)),
      'program',
    );
});
function showHistory(id) {
  const def = definitions.find((d) => d.id === id),
    s = catalogue.get(id),
    rows = series[id];
  showDialog(
    def.label,
    `<p>${esc(countries.get(state.code).name)} · ${donors[def.provider]} · current USD</p>
    ${
      rows.length
        ? `<div class="tablewrap"><table><thead><tr><th>Year</th><th>Reported amount</th><th>Amounts disclosed</th></tr></thead><tbody>${[
            ...rows,
          ]
            .reverse()
            .map(
              (r) =>
                `<tr><td>${def.period} ${r.year}</td><td>${money(r.value)}</td><td>${r.known} / ${r.n}</td></tr>`,
            )
            .join('')}</tbody></table></div>`
        : '<p class="emptymsg">No observations in this release.</p>'
    }
    <h3>Source</h3><p>${esc(s.title)} · ${safeLink(s.download_url, ['usun_toa','ustr_fta','cofa'].includes(s.source_id) ? 'Reference' : 'Pinned file')}</p>`,
  );
}
$('evidence').addEventListener('change', (e) => {
  const name = e.target.dataset.contributorFilter;
  if (!name) return;
  contributorPrefs[name] = e.target.value;
  contributorPrefs.eximPage = 0;
  if (name !== 'actor' && name !== 'timeline') {
    contributorPrefs.actor = null;
    contributorPrefs.expanded = false;
    if (name !== 'year') {
      contributorPrefs.year = null;
      contributorPrefs.timeline = 'leaders';
    }
  }
  renderEvidence();
  document.querySelector('[data-contributor-filter="' + name + '"]')?.focus({preventScroll:true});
});
$('evidence').addEventListener('click', (e) => {
  const b = e.target.closest('button');
  if (!b) return;
  if (b.hasAttribute('data-exim-page')) {
    contributorPrefs.eximPage += Number(b.dataset.eximPage);
    renderEvidence();
    const next = document.querySelector(`[data-exim-page="${b.dataset.eximPage}"]:not(:disabled)`);
    (next ?? document.querySelector('[data-exim-page]:not(:disabled)'))?.focus({preventScroll:true});
    return;
  }
  if (b.hasAttribute('data-contributor-actor') || b.hasAttribute('data-more-contributors')) {
    if (b.hasAttribute('data-more-contributors')) contributorPrefs.expanded = !contributorPrefs.expanded;
    else contributorPrefs.actor = b.dataset.contributorActor;
    renderEvidence();
    const selector = b.hasAttribute('data-more-contributors') ? '[data-more-contributors]' : '[data-contributor-actor][aria-pressed="true"]';
    document.querySelector(selector)?.focus({preventScroll:true});
    return;
  }
  if (b.dataset.chartSource) {
    Object.assign(contributorPrefs, {scope:'country', source:b.dataset.chartSource,
      timeline:b.dataset.chartActor || 'leaders', actor:b.dataset.chartActor || null, year:null, expanded:false, eximPage:0});
    activate('U.S. contributors');
    document.querySelector('.orgTimeline')?.scrollIntoView({block:'start'});
    return;
  }
  if (b.dataset.jump) {
    activate(b.dataset.jump, b.dataset.filter);
    $('tabs').scrollIntoView({ block: 'nearest' });
    return;
  }
  if (b.dataset.history) {
    showHistory(b.dataset.history);
    return;
  }
  if (b.dataset.recordKind) {
    const r = data.result.find(
      (r) => r.provider === b.dataset.provider && r.id === b.dataset.recordId,
    );
    openRecord(r, 'result');
    return;
  }
  if (b.dataset.row !== undefined) {
    openRecord(pageRows[Number(b.dataset.row)], ledgerInfo[state.tab].type);
    return;
  }
  if (b.dataset.page) {
    state.page += Number(b.dataset.page);
    renderTable();
  }
});
function sources() {
  const ids = new Set(
    [...data.program, ...data.context].map((r) => r.source_id).concat(data.result.map((r) => r.timing_source_id).filter(Boolean)),
  );
  if (localContributions.rows.some(r => r.source === agencySource.source_id)) ids.add(agencySource.source_id);
  if (state.tab === 'Results') [...reviewSources, ...review.programs.map(r => r.source_id), ...review.reports.map(r => r.source_id)].forEach(id => ids.add(id));
  const profile = snap.profiles[state.code];
  for (const row of [...profile.organizations, ...profile.agreements]) ids.add(row.source_id);
  if (profile.goods.length) { ids.add('census_goods'); ids.add('schedule_c'); }
  const sourceRows = [...catalogue.values()].sort(
    (a, b) =>
      Number(ids.has(b.source_id)) - Number(ids.has(a.source_id)) ||
      a.title.localeCompare(b.title),
  );
  showDialog(
    'Sources and coverage',
    `<p>Both databases index 249 ISO countries and territories plus Kosovo. The coverage map shows where a provider appears in the sources. The equity map compares disclosed sponsor stakes only where every listed stake for both providers has a published dollar amount. A record can describe a pledge, a cancellation or an ineligible year.</p>
    <h3>Comparing financing</h3><p>Disbursements measure reported payments. Commitments measure financing agreements. The profile shows the latest available year in the U.S. disbursement series and the PRC commitment series, with the Greenbook obligation series as a U.S. fallback. Final years may be partial.</p>
    <p>World Bank PPI provides a common definition for named sponsor equity. Coverage includes state-owned sponsors. The bars sum disclosed stakes only. A missing stake stays unknown. Sources and years differ across the other financial series.</p>
    <h3>Reading results</h3><p>Monitoring indicators, evaluation estimates and reported project outputs have different evidentiary strength. AGOA customs values measure preference use. National logistics lead times provide context. These data do not measure political influence or predict the effect of joining Trade over Aid.</p>
    <h3>Source files</h3>${sourceRows.map((s) => `<details><summary>${esc(s.title)}</summary><p>${ids.has(s.source_id) ? 'Contains observations for this country.' : 'Release reference.'}</p><p>${safeLink(s.publisher_url, 'Publisher')} · ${safeLink(s.download_url, ['usun_toa','ustr_fta','cofa'].includes(s.source_id) ? 'Reference' : 'Pinned file')}</p><p class="hint">${['usun_toa','ustr_fta','cofa'].includes(s.source_id) ? 'Bundled transcription or crosswalk' : 'Source file'} SHA-256 · ${esc(s.sha256)}</p></details>`).join('')}
    <details><summary>Country matching exclusions</summary><p>Source labels recorded outside the country registry, by database. Shared national context sources appear in both.</p><div class="tablewrap"><table><thead><tr><th>Database / source</th><th>Label / reason</th><th>Rows</th></tr></thead><tbody>${snap.exclusions.map((r) => `<tr><td>${donors[r.provider]} · ${esc(sourceLabel(r.source_id))}</td><td>${esc(r.label)}<br><small>${esc(r.reason)}</small></td><td>${num(r.n)}</td></tr>`).join('')}</tbody></table></div></details>
    <h3>Geography and software</h3><p>Public-domain Natural Earth 1:50m map units, v5.1.2. Boundaries follow the cartographic source. Small territories have point selectors. The U.S. Minor Outlying Islands selector is placed at Wake Island. Unassigned disputed shapes are neutral.</p><details><summary>Open-source notices</summary>${$('licenses').innerHTML}</details>`,
  );
}
buttons.forEach((id) => ($(id).onclick = sources));
window.matchMedia('(max-width:650px)').addEventListener('change', () => {
  if (state.tab === 'U.S. contributors') renderEvidence();
});
choose('HND');
// Re-measure the label after the embedded faces replace the browser's first-paint fonts.
document.fonts.ready.then(() => mark(countries.get(state.code)));
