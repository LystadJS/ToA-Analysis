import { esc, money, safeLink } from './format.js';

function years(row) {
  return [row.first_year, row.last_year].filter((v, i, a) => v != null && a.indexOf(v) === i).join('–');
}

export function countryProfile(profile) {
  const { agreements, organizations, evidence, goods } = profile;
  const agreementList = agreements.map(r => `<li><strong>${esc(r.name)}</strong> · ${esc(r.status)}
    ${r.first_year ? ' · ' + esc(years(r)) : ''}<p class="hint">${esc(r.detail)} ${safeLink(r.citation,'Source')}</p></li>`).join('');
  const usFTA = agreements.some(r => r.kind === 'Trade agreement');
  const programs = organizations.map(r => `<tr><th scope="row">${esc(r.name)}</th><td>${esc(r.status)}</td><td class="mnum">${years(r) || 'Undated'}</td>
    <td>${safeLink(r.citation, 'Source')}</td></tr>`).join('');
  const shortlist = [['MCC', /millennium challenge/i], ['DFC', /development finance corporation/i], ['EXIM', /export.import bank/i]];
  const highlights = shortlist.map(([key, match]) => {
    const records = organizations.filter(r => match.test(r.name));
    return `<li><strong>${key}</strong> · ${records.length ? esc([...new Set(records.map(r => r.status))].join(' · ')) : 'No matching record in this release'}</li>`;
  }).join('');
  const results = evidence.map(r => `<li><strong>${esc(r.indicator)}</strong> · ${esc(r.statement)}<p>${esc(r.project)}. ${esc(r.interpretation)}</p>
    <button class="linkBtn" data-record-kind="result" data-record-id="${esc(r.id)}" data-provider="USA">${esc(r.method)} · Inspect evidence →</button></li>`).join('');
  const flows = goods.length ? `<details><summary>Annual goods trade in current USD</summary><div class="tablewrap"><table><thead><tr><th>Calendar year</th><th>U.S. imports from partner</th><th>U.S. exports to partner</th></tr></thead><tbody>${goods.map(r => `<tr><td>${r.year}</td><td class="mnum">${money(r.imports_usd)}</td><td class="mnum">${money(r.exports_usd)}</td></tr>`).join('')}</tbody></table></div></details>` : '';
  return `<div class="countryProfile"><section class="panel"><h3>U.S. bilateral goods trade</h3><p>${esc(profile.trade)}</p>${flows}<p class="hint">Full calendar years, excluding services. ${safeLink('https://www.census.gov/foreign-trade/balance/country.xlsx','U.S. Census Bureau')}</p></section>
    <section class="panel"><h3>Trade agreements, preferences and initiatives</h3><ul>${agreementList}</ul>${usFTA ? '' : '<p class="hint">No comprehensive U.S. free trade agreement is listed here through 2025.</p>'}</section>
    <section class="panel"><h3>U.S. agencies and organizations</h3><ul>${highlights}</ul>${programs ? `<details><summary>All ${organizations.length} organizational relationships</summary><div class="tablewrap"><table><thead><tr><th>Organization</th><th>Documented role</th><th>Recorded years</th><th>Evidence</th></tr></thead><tbody>${programs}</tbody></table></div></details>` : ''}<button class="linkBtn" data-jump="U.S. contributors">View annual contributions →</button></section>
    <section class="panel"><h3>Evidence of benefit from U.S.-linked programs</h3><p>${esc(profile.assessment)}</p>${results ? `<ul>${results}</ul>` : ''}<p class="hint">The USUN roster supplies no measure of the impact of joining Trade over Aid.</p></section></div>`;
}
