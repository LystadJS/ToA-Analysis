
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
