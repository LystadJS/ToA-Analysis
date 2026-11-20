import { esc, money, num, safeLink } from './format.js';
import { plotGrid } from './plot-grid.js';

const archives = {
  threeie: '3ie impact evaluations · June 2023',
  usaid_dec: 'USAID evaluations · September 2014',
  ieg: 'World Bank IEG completion reviews · June 2026',
  mcc_catalog: 'MCC evaluation catalogue · May 2013',
  gao_catalog: 'GAO report index · November 2026',
  aea_registry: 'AEA trial registry · November 2026',
};
export const reviewSources = Object.keys(archives);
const by = (rows, key) => [...new Set(rows.map(r => r[key]))].map(v => [v, rows.filter(r => r[key] === v)]);
const shortNumber = new Intl.NumberFormat('en-US', {maximumFractionDigits: 2});
const label = x => shortNumber.format(x);
function quantitative(panel, rows) {
  const unit = rows[0].unit, values = rows.map(r => r.value);
  const extent = Math.max(...values.map(Math.abs));
  const power = 10 ** Math.floor(Math.log10(extent || 1));
  const bound = unit === 'of 13 indices' ? 13 : Math.ceil(extent / power * 2) * power / 2;
  const min = Math.min(...values) < 0 ? -bound : 0, max = Math.max(...values) > 0 ? bound : 0;
  const pos = x => 12 + (x - min) / (max - min || 1) * 200;
  const ticks = [min, (min + max)/2, max];
  const marks = rows.map(r => {
    const at = pos(r.value), base = pos(0);
    return `<div class="evalPlotRow"><span>${esc(r.indicator)}</span><svg viewBox="0 0 224 26" preserveAspectRatio="none" aria-hidden="true">${plotGrid(ticks.map(pos),[],12,212,0,26)}<line x1="${base}" y1="13" x2="${at}" y2="13" class="evalLine"/><circle cx="${at}" cy="13" r="4" class="evalMark"/></svg><b>${num(r.value)}</b></div>`;
  }).join('');
  return `<figure class="evalFigure"><figcaption>${esc(panel)} <small>${esc(unit)}</small></figcaption>${marks}<div class="evalPlotTicks" aria-hidden="true"><span>${label(min)}</span><span>${label((min+max)/2)}</span><span>${label(max)}</span></div></figure>`;
}
function directions(panel, rows) {
  // A categorical matrix keeps an imprecise/null estimate distinct from numerical zero.
  const order = ['Lower','No detectable change','Higher','Separate reform','Negative or inconclusive'];
  const values = order.filter(v => rows.some(r => r.result === v));
  const heads = values.map(v => `<th scope="col">${esc(v)}</th>`).join('');
  const body = rows.map(r => `<tr><th scope="row">${esc(r.indicator)}</th>${values.map(v =>
    `<td>${v === r.result ? `<span class="evalDot" title="${esc(r.interpretation)}"><span class="evalSr">${esc(v)}</span></span>` : ''}</td>`).join('')}</tr>`).join('');
  return `<figure class="evalFigure"><figcaption>${esc(panel)}</figcaption><table class="evalMatrix"><thead><tr><th scope="col">Outcome</th>${heads}</tr></thead><tbody>${body}</tbody></table></figure>`;
}
function renderReport(r, findings, catalogue) {
  const figures = by(findings.filter(f => f.report_id === r.report_id), 'panel').map(([panel, rows]) =>
    rows.every(f => f.value !== null) ? quantitative(panel,rows) : directions(panel,rows)).join('');
  const citation = catalogue.get(r.source_id);
  return `<article class="evalReport"><div class="evalKicker">${esc(r.eligibility)} · ${r.published}</div><h4>${esc(r.title)}</h4><p>${esc(r.summary)}</p>${figures}<p class="evalCaveat">${esc(r.limitation)}</p><details class="evalMethods"><summary>Evaluator, timing and sources</summary><dl>
  <dt>Evaluator</dt><dd>${esc(r.evaluator)}</dd><dt>Donor or host role</dt><dd>${esc(r.authority)}</dd><dt>Intervention</dt><dd>${esc(r.scope)}</dd><dt>Follow-up</dt><dd>${esc(r.timing)}</dd><dt>Method</dt><dd>${esc(r.method)}</dd><dt>Source location</dt><dd>${esc(r.evidence)}</dd></dl></details>
  <p class="evalLinks">${safeLink(r.url,'Published evaluation')} ${safeLink(citation?.download_url,r.source_id==='moz'?'Archived full report':'Archived study catalogue')}</p></article>`;
}
function searchDetails(p, review, catalogue) {
  const searches = review.searches.filter(s => s.project_key === p.project_key);
  return `<details class="evalMethods"><summary>Search record and financing source</summary>
    <p><strong>Search terms</strong> · ${esc(p.search_name)}<br><strong>Financing record</strong> · ${esc(p.locator)} · ${safeLink(p.citation,'View source')}</p>
    <ul>${searches.map(s => {
      const leads = JSON.parse(s.leads);
      return `<li>${safeLink(catalogue.get(s.source_id)?.download_url,archives[s.source_id])} · ${s.match_count} candidate${s.match_count===1?'':'s'}${leads.length ? `<ul>${leads.map(l=>`<li>${safeLink(l.url,l.title) || esc(l.title)} · ${esc(l.id)}</li>`).join('')}</ul>` : ''}</li>`;
    }).join('')}</ul><p class="hint">Up to four candidate titles per archive are shown. Matching text can refer to another project, an interim study or a trial plan.</p></details>`;
}
export function evaluationReview(review, country, options, catalogue) {
  const programs = review.programs;
  const verified = programs.filter(p => p.status==='Post-completion evaluation found').length;
  const pick = options.map(c=>`<option value="${esc(c.iso3)}">${esc(c.name)}</option>`).join('');
  const cards = programs.map(p => {
    const reports=review.reports.filter(r=>r.project_key===p.project_key);
    return `<details class="evalProgram" data-rank="${p.rank}" ${reports.length?'open':''}><summary>
      <span class="evalNumber">${p.rank}</span><span class="evalIdentity"><strong>${esc(p.title)}</strong><small>${esc(p.organization)}</small><span class="evalStatus ${p.status==='Post-completion evaluation found'?'verified':''}">${esc(p.status)}</span></span>
      <span class="evalMoney">${money(p.amount_cents/100)}</span></summary><div class="evalBody"><p class="evalBasis">${esc(p.measure)}${p.year?' · '+p.year:''}</p>
      ${p.screening_note ? `<p>${esc(p.screening_note)}</p>` : ''}${reports.map(r=>renderReport(r,review.findings,catalogue)).join('')}${searchDetails(p,review,catalogue)}</div></details>`;
  }).join('');
  return `<section class="evaluationReview" aria-label="Post-completion evaluations"><div class="evalHead"><div><h2 class="sectiontitle">Post-completion evaluations</h2><p class="sectionnote">Highest-value identifiable U.S.-linked programs and financing deals in ${esc(country.name)}</p></div>
    <label class="evalPicker">Browse countries with a verified evaluation<select id="evaluationCountry"><option value="">Select a country</option>${pick}</select></label></div>
    ${programs.length ? `<p class="evalCount"><strong>${verified} of ${programs.length}</strong> ranked programs have a verified donor or host evaluation.</p>` : '<p class="evalCount">No program in the collected sources has a country-attributed, disclosed amount eligible for ranking here.</p>'}
    ${cards}<details class="evalMethods evalScope"><summary>How the top five and evaluations were selected</summary>
    <p>Programs are ranked by their source’s nominal U.S. dollar measure. A loan authorization, grant, equity stake, budget and disbursement measure different things. National and sector totals cannot identify an individual project. A component evaluation applies only to the activity and population it studied.</p>
    <p>The 19 November 2026 review searched six archived catalogues using country names, project names, aliases and financing identifiers. A qualifying report documents follow-up after the intervention or a named component ended, plus a U.S. donor or participant-country research role. The search covers published catalogue records. Coverage of national repositories, recent reports and commercially confidential evaluations varies.</p></details></section>`;
}
