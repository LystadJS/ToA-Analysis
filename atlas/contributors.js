import { timeline } from './contribution-timeline.js';
import { plotGrid } from './plot-grid.js';
import { esc, money, compact, safeLink } from './format.js';

const measures = {
  dfc: {
    name: 'DFC project commitments or exposure', total: 'Disclosed DFC commitments or exposure', period: 'FY',
    note: 'Active projects grouped by the fiscal year in the portfolio, including predecessor projects. Instruments include insurance. Undated projects are outside the timeline.',
  },
  exim: {
    name: 'EXIM export credit authorizations', total: 'EXIM approved export credit', period: 'FY',
    note: 'Approved, noncancelled authorizations by export market. Guarantees, insurance and loans can support U.S. exporters. FY2025 runs through Q3.',
  },
  usun_toa: {
    name: 'Trade over Aid participation', total: 'Annual dollar amount unreported', period: '',
    note: 'The USUN roster supplied on 19 November 2026 identifies participants. No annual funding series was supplied.',
  },
  funding_agency: {
    name: 'Federal disbursements', total: 'U.S. disbursements in funding file', period: 'FY',
    note: 'Payments allocated to the recipient, including military assistance. The agency is the funding agency on the account.',
  },
  greenbook: {
    name: 'Economic assistance obligations', total: 'U.S. economic obligations', period: 'FY',
    note: 'Greenbook economic assistance obligations by agency. Annual comparisons exclude the separate 1976 transition quarter.',
  },
  ppi: {
    name: 'Infrastructure sponsor equity', total: 'Disclosed U.S. sponsor equity', period: 'CY',
    note: 'Named U.S. sponsors at financial close. Shares use directly disclosed equity. Some listed stakes have no dollar value.',
  },
  gates: {
    name: 'Foundation grant commitments', total: 'Reviewed U.S. foundation grants', period: 'CY',
    note: 'This series covers reviewed Gates Foundation commitments to local grantees. Its coverage is limited to one foundation.',
  },
};

const usd = cents => cents == null ? 'Undisclosed' : money(cents / 100);
const short = cents => cents == null ? 'Undisclosed' : compact.format(cents / 100);
const share = (part, total) => part != null && total > 0 ? 100 * part / total : null;
const percent = n => n == null ? '—' : n !== 0 && Math.abs(n) < 0.1
  ? (n < 0 ? '−' : '') + '<0.1%' : n.toLocaleString('en-US', {maximumFractionDigits:1}) + '%';
const totalOf = rows => rows.some(r => r.cents != null) ? rows.reduce((s, r) => s + (r.cents ?? 0), 0) : null;

function field(label, key, options, selected) {
  return `<label>${label}<select data-contributor-filter="${key}">${options.map(([value,name]) =>
    `<option value="${esc(value)}"${String(value) === String(selected) ? ' selected' : ''}>${esc(name)}</option>`
  ).join('')}</select></label>`;
}

function groupActors(rows) {
  const groups = new Map();
  for (const r of rows) {
    if (!groups.has(r.actor)) groups.set(r.actor, { actor:r.actor, cents:null, known:0, records:0 });
    const g = groups.get(r.actor);
    g.known += r.known;
    g.records += r.records;
    if (r.cents != null) g.cents = (g.cents ?? 0) + r.cents;
  }
  return [...groups.values()].sort((a,b) =>
    (b.known > 0) - (a.known > 0) || b.cents - a.cents || a.actor.localeCompare(b.actor));
}

function ranked(rows, total, selected, expanded) {
  const lo = Math.min(0,...rows.map(r => r.cents ?? 0));
  const hi = Math.max(0,total ?? 0,...rows.map(r => r.cents ?? 0));
  const scale = hi - lo || 1;
  const origin = -100 * lo / scale;
  const visible = expanded ? rows : rows.slice(0,7);
  const bars = visible.map(r => {
    const value = r.cents ?? 0;
    const start = 100 * (Math.min(0,value) - lo) / scale;
    const width = 100 * Math.abs(value) / scale;
    return `<button type="button" class="actorRow" data-contributor-actor="${esc(r.actor)}" aria-pressed="${r.actor === selected}" title="${esc(r.actor)} · ${usd(r.cents)} · ${esc(percent(share(r.cents,total)))}">
      <span class="actorLabel">${esc(r.actor)}${r.known < r.records ? `<small>${r.known}/${r.records} amounts disclosed</small>` : ''}</span>
      <span class="actorAmount">${usd(r.cents)}</span><b>${esc(percent(share(r.cents,total)))}</b>
      <span class="actorTrack" aria-hidden="true"><i style="left:${origin}%"></i><span class="${value < 0 ? 'negative' : ''}" style="left:${start}%;width:${width}%"></span></span></button>`;
  }).join('');
  return `<section class="panel actorRank"><h3>Share by contributor</h3><p class="hint">Select a contributor to see its history.</p>
    <div class="actorHead"><span>Contributor</span><span>Current USD</span><span>Share</span></div>${bars}
    ${rows.length > 7 ? `<button class="linkBtn" data-more-contributors>${expanded ? 'Show top seven' : 'Show all ' + rows.length + ' contributors'}</button>` : ''}
    ${lo < 0 ? '<p class="hint">Negative amounts are net adjustments. Positive shares can exceed 100%.</p>' : ''}
    ${total <= 0 ? '<p class="hint">Shares require a positive disclosed total.</p>' : ''}</section>`;
}

function trendGraphic(points, selectedYear) {
  const defined = points.filter(p => p.share != null);
  if (!defined.length) return '<p class="emptymsg">No annual share can be calculated.</p>';
  const low = Math.min(0,...defined.map(p => p.share)), high = Math.max(100,...defined.map(p => p.share));
  const first=points[0].year, last=points.at(-1).year;
  const x=y => first === last ? 199 : 52+(y-first)/(last-first)*310;
  const y=p => 135-(p-low)/(high-low)*106;
  const ticks = [...new Set([low,0,high / 2,high])];
  const yearTicks = [...new Set([first, last])];
  let previous = null;
  const marks = points.map(p => {
    if (p.share == null) { previous = null; return ''; }
    const cx=x(p.year), cy=y(p.share);
    const line = previous ? `<line x1="${x(previous.year)}" y1="${y(previous.share)}" x2="${cx}" y2="${cy}" stroke="#367c76" stroke-width="2.5"/>` : '';
    previous = p;
    return line + `<circle cx="${cx}" cy="${cy}" r="${String(p.year) === selectedYear ? 5 : 2.6}" fill="#176963"><title>${p.year} · ${esc(percent(p.share))} · ${usd(p.cents)}</title></circle>`;
  }).join('');
  return `<svg class="actorTrend" viewBox="0 0 380 166" role="img" aria-label="Contributor share by year. Exact annual values follow in the table.">
    ${ticks.map(t => `<path d="M50 ${y(t)}H364" stroke="#d9e3dd" fill="none"/><text x="46" y="${y(t)+3}" text-anchor="end">${esc(percent(t))}</text>`).join('')}
    ${marks}<text x="${x(first)}" y="157" text-anchor="middle">${first}</text>${last === first ? '' : `<text x="${x(last)}" y="157" text-anchor="middle">${last}</text>`}</svg>`;
}

function history(rows, actor, selectedYear, measure) {
  const byYear = new Map();
  for (const r of rows) {
    if (!byYear.has(r.year)) byYear.set(r.year,[]);
    byYear.get(r.year).push(r);
  }
  const years = [...byYear.keys()];
  const points=[];
  for (let year=Math.min(...years);year<=Math.max(...years);year++) {
    const observations=byYear.get(year) ?? [];
    const matched=observations.find(r => r.actor===actor);
    const total=totalOf(observations);
    points.push({year, total, recorded:!!matched, cents:matched?.cents, share:share(matched?.cents,total)});
  }
  return `<section class="panel actorHistory"><h3>Share over time</h3><p class="trendName">${esc(actor)}</p>
    ${trendGraphic(points,selectedYear)}<p class="hint">Each point uses that year’s total. Gaps indicate an unavailable share.</p>
    <details><summary>Annual amounts and shares</summary><div class="tablewrap"><table><thead><tr><th>Year</th><th>Contributor</th><th>Series total</th><th>Share</th></tr></thead><tbody>
    ${points.slice().reverse().map(p => `<tr><td>${measure.period} ${p.year}</td><td>${p.recorded ? usd(p.cents) : 'No record'}</td><td>${p.total == null ? 'Unavailable' : usd(p.total)}</td><td>${esc(percent(p.share))}</td></tr>`).join('')}
    </tbody></table></div></details></section>`;
}

function vintageCheck(rows, benchmark, year, sources) {
  const a = totalOf(rows);
  const b = benchmark.length ? benchmark.reduce((v,r) => v+r.total_cents,0) : null;
  if (a == null && b == null) return '';
  const low = Math.min(0,a ?? 0,b ?? 0), high = Math.max(0,a ?? 0,b ?? 0);
  const span = high-low || 1;
  let comparison = '';
  if (a != null && b != null) {
    comparison = a === b ? 'The two totals agree.' : 'The funding-file total is ' + usd(Math.abs(a-b)) +
      (a < b ? ' lower' : ' higher') + ' than the atlas total' +
      (b > 0 ? ' (' + percent(share(a,b)) + ' of the atlas amount).' : '.');
  }
  const entries=[['Funding agency file',a],['Atlas sector file',b]];
  return `<section class="panel vintageCheck"><div><h3>How the two U.S. totals compare</h3>
    <p class="hint">${year === 'all' ? 'All available fiscal years in each file.' : 'FY ' + year + '.'} Both files report all-sector disbursements. Different release dates can revise the total. ${year === '2025' || year === 'all' ? 'FY2025 may be partial.' : ''}</p></div>
    <div class="vintageBars">${entries.map(([label,value]) => `<div><span>${label}</span><b>${value == null ? 'No record' : usd(value)}</b>
      <div class="vintageTrack"><i class="${value < 0 ? 'vintageNegative' : ''}" style="left:${100*(Math.min(0,value ?? 0)-low)/span}%;width:${100*Math.abs(value ?? 0)/span}%"></i></div></div>`).join('')}</div>
    <p class="hint">${esc(comparison)} ${safeLink(sources.get('us_sector_review').download_url,'Atlas sector file')}</p></section>`;
}

function exportCredit(rows, all, year, page) {
  const selected = rows.filter(r => year === 'all' || String(r.year) === year);
  if (!selected.length) return '';
  const size = 20;
  const start = Math.min(page, Math.ceil(selected.length / size) - 1) * size;
  const records = selected.slice(start, start + size).map(r =>
    `<tr>${all ? `<td>${esc(r.iso3)}</td>` : ''}<td>FY ${r.year}</td><td>${esc(r.name)}</td>
    <td>${esc(r.product)}</td><td>${esc(r.deal)}<small class="sourceLine">${esc(r.id)}</small></td><td>${usd(r.cents)}</td></tr>`
  ).join('');
  return `<section class="panel eximDeals"><h3>Named EXIM authorizations</h3>
    <p class="hint">These are approved authorizations for the selected export markets. A deal may have several authorizations.</p>
    <div class="tablewrap"><table><thead><tr>${all ? '<th scope="col">Market</th>' : ''}<th scope="col">Year</th>
    <th scope="col">Named party</th><th scope="col">Product</th><th scope="col">Deal / authorization</th>
    <th scope="col">Approved USD</th></tr></thead><tbody>${records}</tbody></table></div>
    <div class="pager"><span>${start + 1}–${Math.min(start + size,selected.length)} of ${selected.length.toLocaleString()}</span>
    <button class="smallbtn" data-exim-page="-1" ${start === 0 ? 'disabled' : ''}>Previous</button>
    <button class="smallbtn" data-exim-page="1" ${start + size >= selected.length ? 'disabled' : ''}>Next</button></div></section>`;
}

export function contributorView(data, filters, country, sources) {
  const src=filters.source, m=measures[src], all=filters.scope==='all';
  const scope=all ? 'All atlas recipients' : country;
  const rows=data.rows.filter(r => r.source===src);
  const benchmark=src==='funding_agency' ? data.benchmark : [];
  const years=[...new Set([...rows.map(r=>r.year),...benchmark.map(r=>r.year)])].sort((a,b)=>b-a);
  const year=filters.year ?? (['ppi','gates'].includes(src) || !years.length ? 'all' : String(years[0]));
  const chosen=r => year==='all' || String(r.year)===year;
  const slice=rows.filter(chosen);
  const actors=groupActors(slice), total=totalOf(slice);
  const selected=actors.find(r=>r.actor===filters.actor)?.actor ?? actors[0]?.actor;
  const count=slice.reduce((v,r)=>v+r.records,0), known=slice.reduce((v,r)=>v+r.known,0);
  const scopeOptions=[['country',country],['all','All atlas recipients']];
  const tools=`<div class="contributorControls">${field('Recipient scope','scope',scopeOptions,filters.scope)}
    ${field('Funding measure','source',Object.entries(measures).map(([k,v])=>[k,v.name]),src)}
    ${field('Period','year',[['all','All reported years'],...years.map(y=>[y,m.period+' '+y])],year)}</div>`;
  const source=sources.get(src);
  return `<div class="sectionhead"><div><h2 class="sectiontitle">U.S. contributors</h2><p class="sectionnote">${esc(scope)} · Reported contributions in current U.S. dollars.</p></div></div>
    ${tools}${timeline(rows,filters.timeline,m.period,src)}<div class="contributorSummary"><div><span>${esc(m.total)}</span><strong>${slice.length ? short(total) : src === 'usun_toa' ? 'Unreported' : 'No records'}</strong>
    <small>${esc(scope)} · ${year==='all' ? 'All reported years' : m.period+' '+year}${total != null ? ' · '+usd(total) : ''}</small></div>
    <div class="contributorBasis"><p>${esc(m.note)}</p><small>${actors.length} recorded contributor${actors.length===1?'':'s'} · ${known.toLocaleString()}/${count.toLocaleString()} amounts disclosed${all ? ' · Regional and worldwide allocations excluded' : ''}</small></div></div>
    ${src === 'usun_toa' ? '' : slice.length ? `<div class="contributorCharts">${ranked(actors,total,selected,filters.expanded)}${history(rows,selected,year,m)}</div>` : '<p class="bigempty">No contributor records for this selection. An empty series gives no estimate of funding.</p>'}
    ${src==='funding_agency' ? vintageCheck(slice,benchmark.filter(chosen),year,sources) : ''}
    ${src==='exim' ? exportCredit(data.exim,all,year,filters.eximPage) : ''}
    <p class="contributorSource">${esc(source.title)} · ${safeLink(source.download_url,'Pinned source file')}</p>`;
}

export function contributorPreview(data) {
  const rows = data.rows.filter(r => r.source === 'funding_agency');
  if (!rows.length) return '';
  const year = Math.max(...rows.map(r => r.year));
  const actors = groupActors(rows.filter(r => r.year === year));
  const total = totalOf(actors);
  if (total == null || total <= 0) return '';
  const top = actors[0];
  const positive = actors.every(r => r.cents >= 0);
  const key = actors.slice(0, 3);
  if (actors.length > 3) key.push({actor:'Other funding agencies', cents:totalOf(actors.slice(3))});
  const colors = ['#246c69','#649c8a','#ae824c','#8193a6'];
  const strip = positive ? `<div class="agencyMix" aria-hidden="true">${key.map((r,i) =>
    `<span style="width:${share(r.cents,total)}%;background:${colors[i]}"></span>`).join('')}</div>
    <div class="mixKey">${key.map((r,i) => `<span><i style="background:${colors[i]}"></i>${esc(r.actor)} <b>${esc(percent(share(r.cents,total)))}</b></span>`).join('')}</div>` : '';
  const benchmark = data.benchmark.find(r => r.year === year);
  return `<section class="panel agencyPreview"><div class="previewHeading"><div><h3>U.S. funding agencies</h3><p class="hint">FY ${year} · Funding-file total ${usd(total)}${benchmark ? ' · Atlas sector total '+usd(benchmark.total_cents) : ''}</p></div>
    <button class="linkBtn" data-jump="U.S. contributors">Explore contributors →</button></div>
    ${strip || `<p>${esc(top.actor)} recorded ${usd(top.cents)}, or ${esc(percent(share(top.cents,total)))} of net disbursements. This period includes negative adjustments.</p>`}</section>`;
}
