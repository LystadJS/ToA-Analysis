import { esc, money, compact, safeLink } from './format.js';

const measures = {
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
  const ticks = [...new Set([low,0,high])];
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
  const maximum = Math.max(1,Math.abs(a ?? 0),Math.abs(b ?? 0));
  const entries=[['Funding agency file',a],['Atlas sector file',b]];
  return `<section class="panel vintageCheck"><div><h3>How the two U.S. totals compare</h3>
    <p class="hint">${year === 'all' ? 'All available fiscal years in each file.' : 'FY ' + year + '.'} Both files report all-sector disbursements. Different release dates can revise the total.</p></div>
    <div class="vintageBars">${entries.map(([label,value]) => `<div><span>${label}</span><b>${value == null ? 'No record' : usd(value)}</b>
      <div class="vintageTrack"><i style="width:${100*Math.abs(value ?? 0)/maximum}%"></i></div></div>`).join('')}</div>
    <p class="hint">${safeLink(sources.get('us_sector_review').download_url,'Atlas sector file')}</p></section>`;
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
  return `<div class="sectionhead"><div><h2 class="sectiontitle">U.S. contributors</h2><p class="sectionnote">Explore who funded ${esc(scope)} and how each share changed.</p></div></div>
    ${tools}<div class="contributorSummary"><div><span>${esc(m.total)}</span><strong>${slice.length ? short(total) : 'No records'}</strong>
    <small>${esc(scope)} · ${year==='all' ? 'All reported years' : m.period+' '+year}${total != null ? ' · '+usd(total) : ''}</small></div>
    <div class="contributorBasis"><p>${esc(m.note)}</p><small>${actors.length} recorded contributor${actors.length===1?'':'s'} · ${known.toLocaleString()}/${count.toLocaleString()} amounts disclosed${all ? ' · Regional and worldwide allocations excluded' : ''}</small></div></div>
    ${slice.length ? `<div class="contributorCharts">${ranked(actors,total,selected,filters.expanded)}${history(rows,selected,year,m)}</div>` : '<p class="bigempty">No contributor records for this selection. An empty series gives no estimate of funding.</p>'}
    ${src==='funding_agency' ? vintageCheck(slice,benchmark.filter(chosen),year,sources) : ''}
    <p class="contributorSource">${esc(source.title)} · ${safeLink(source.download_url,'Pinned source file')}</p>`;
}
