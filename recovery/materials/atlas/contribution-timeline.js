import { esc, money, compact } from './format.js';
import { plotGrid } from './plot-grid.js';

const palette = ['#11756c','#965723','#5865a0','#94486a','#527032','#326b92','#806124'];
const numeric = new Intl.NumberFormat('en-US', {maximumFractionDigits: 0});

// Annual net disclosed amounts. A missing actor/year interrupts the line.
export function timeline(rows, selection, period, source) {
  const heading = '<h3>Annual contributions by organization</h3>';
  if (!rows.length) return `<section class="panel orgTimeline">${heading}<p>${source === 'usun_toa' ? 'The USUN roster records participation. It provides no annual dollar contributions.' : 'No dated amounts are available for this measure and recipient.'}</p></section>`;
  const actors = new Map(), totals = new Map();
  for (const r of rows) {
    if (!actors.has(r.actor)) actors.set(r.actor, new Map());
    actors.get(r.actor).set(r.year, r);
    const t = totals.get(r.year) ?? {cents:null, known:0, records:0};
    if (r.cents != null) t.cents = (t.cents ?? 0) + r.cents;
    t.known += r.known;
    t.records += r.records;
    totals.set(r.year,t);
  }
  const names = [...actors.keys()].sort((a,b) => a.localeCompare(b));
  const magnitude = name => [...actors.get(name).values()].reduce((n,r) => n + Math.abs(r.cents ?? 0),0);
  const chosen = actors.has(selection) ? [selection] : selection === 'all-actors' ? names :
    [...names].sort((a,b) => magnitude(b)-magnitude(a)).slice(0,3);
  const controls = `<label>Organizations shown<select data-contributor-filter="timeline"><option value="leaders">Leading three</option><option value="all-actors" ${selection==='all-actors'?'selected':''}>All organizations</option>
    ${names.map(n=>`<option value="${esc(n)}" ${selection===n?'selected':''}>${esc(n)}</option>`).join('')}</select></label>`;
  const series = [{name:'Total · all organizations',values:totals,color:'#202f36',total:true},
    ...chosen.map((name,i)=>({name,values:actors.get(name),color:palette[i%palette.length]}))];
  const years = [...totals.keys()].sort((a,b)=>a-b), first=years[0], last=years.at(-1);
  const amounts=series.flatMap(s=>[...s.values.values()].filter(r=>r.cents!=null).map(r=>r.cents/100));
  const lineKey = series.map(s=>`<span><i style="background:${s.color}"></i>${esc(s.name)}</span>`).join('');
  let graphic = '<p>No disclosed amounts for these series.</p>';
  if (amounts.length) {
    const lo=Math.min(0,...amounts), hi=Math.max(0,...amounts);
    const x=yr=>first===last?370:75+(yr-first)*600/(last-first);
    const y=value=>178-(value-lo)*147/(hi-lo || 1);
    const xt=[...new Set([first,Math.round((first+last)/2),last])];
    const yt=[...new Set([lo,(lo+hi)/2,hi])];
    const marks=series.map(s=>{
      let previous;
      const points=[], paths=[];
      for(const yr of years) {
        const r=s.values.get(yr);
        if(r?.cents==null) { previous=null; continue; }
        const cx=x(yr),cy=y(r.cents/100);
        if(previous?.yr===yr-1) paths.push(`M${previous.cx} ${previous.cy}L${cx} ${cy}`);
        points.push(`<circle cx="${cx}" cy="${cy}" r="${s.total?3.4:2.7}" fill="${s.total?'white':s.color}" stroke="${s.color}"><title>${esc(s.name)} · ${period} ${yr} · ${money(r.cents/100)} · ${r.known}/${r.records} disclosed</title></circle>`);
        previous={yr,cx,cy};
      }
      return `<path d="${paths.join(' ')}" fill="none" stroke="${s.color}" stroke-width="${s.total?2.8:1.8}" ${s.total?'stroke-dasharray="6 4"':''}/>${points.join('')}`;
    });
    // Paint the dashed total last so it stays visible when one actor accounts for 100%.
    graphic=`<svg viewBox="0 0 710 207" role="img" aria-label="Annual current U.S. dollars for selected organizations and the total. Exact amounts follow.">
      ${plotGrid(xt.map(x),yt.map(y),75,675,31,178)}
      ${xt.map(v=>`<text x="${x(v)}" y="198" text-anchor="middle">${v}</text>`).join('')}
      ${yt.map(v=>`<text x="69" y="${y(v)+4}" text-anchor="end">${compact.format(v)}</text>`).join('')}
      ${marks.slice(1).join('')}${marks[0]}</svg>`;
  }
  const cells=years.slice().reverse().map(yr=>`<tr><th scope="row">${period} ${yr}</th>${series.map(s=>{
    const r=s.values.get(yr); return `<td>${!r?'No record':r.cents==null?'Undisclosed':money(r.cents/100)}${r && r.known<r.records?`<small>${numeric.format(r.known)}/${numeric.format(r.records)} disclosed</small>`:''}</td>`;
  }).join('')}</tr>`).join('');
  return `<section class="panel orgTimeline"><div class="timelineHead"><div>${heading}<p class="hint">Current USD · ${period} ${first}–${last}. The dashed line totals all disclosed amounts in the selected measure. Gaps indicate missing records or amounts.</p></div>${controls}</div>
    ${graphic}<div class="timelineKey">${lineKey}</div><details><summary>Annual amounts and disclosure by organization</summary><div class="tablewrap"><table><thead><tr><th>Period</th>${series.map(s=>`<th>${esc(s.name)}</th>`).join('')}</tr></thead><tbody>${cells}</tbody></table></div></details></section>`;
}
