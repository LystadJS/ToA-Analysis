const $ = id => document.getElementById(id);
const data = JSON.parse($('data').textContent);
$('data').remove();
const sources = new Map(data.sources.map(s => [s.source_id, s]));
const countries = data.countries.map((c, i) => ({ ...c, index: i + 1 }));
const allSeries = new Map(data.series.map(s => [s.sid, s]));
const metrics = new Map(), activeYears = new Map(), us = new Map();
for (const [sid, country, year, n, known, reported, zeroes, eligible] of data.cells) {
  if (!metrics.has(sid)) { metrics.set(sid,new Map()); activeYears.set(sid,new Set()); }
  metrics.get(sid).set([country,year].join('/'),{n, known, reported, zeroes, eligible});
  activeYears.get(sid).add(year);
}
for (const [country, year, db, sector] of data.usa) us.set([country,year].join('/'),{db,sector});
const $num = new Intl.NumberFormat('en-US',{maximumFractionDigits:0});
const $usd = new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:2});
const billions = new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',notation:'compact',maximumFractionDigits:2});
const money = n => n == null ? 'No observation' : $usd.format(n);
const fmt = n => n == null ? '—' : $num.format(n);
const esc = s => String(s ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const link = (url,title) => /^https?:\/\//i.test(url) ? `<a href="${esc(url)}" target="_blank" rel="noopener noreferrer">${esc(title)}</a>` : '';
const sourceNames = {fa:'ForeignAssistance.gov',gcdf:'AidData GCDF',clg:'AidData CLG',ppi:'World Bank PPI',agoa:'AGOA',mcc:'MCC',export:'Export',import:'Import',dfc:'DFC',ftf:'Feed the Future',gates:'Gates Foundation',greenbook:'USAID Greenbook',moz:'Mozambique evaluation',sector:'USAID GeoCenter'};
const labels = {agree:'Amounts agree',higher:'Higher in sector file',lower:'Lower in sector file',new:'Sector file only',old:'Database only',empty:'No country row',outside:'No rows in series that year',missing:'No numeric values',partial:'Some numeric values',complete:'All rows have numeric values',present:'Record present'};
const state = {view:'compare',page:0,selected:'ISR',year:2024,from:2016,to:2025,sid:null};
const pageSize=16;
let filtered = [], periods = [];
function options(el, items) {
  el.replaceChildren(...items.map(([value,label]) => new Option(label,value)));
}
function seriesMenus(resetKind=false) {
  const items = data.series.filter(s=>s.provider===$('donor').value);
  const before=$('kind').value;
  options($('kind'), [...new Set(items.map(s=>s.kind))].sort().map(v=>[v,v]));
  $('kind').value = !resetKind && items.some(s=>s.kind===before) ? before : (items.some(s=>s.kind==='Funding') ? 'Funding':items[0].kind);
  const list=items.filter(s=>s.kind===$('kind').value).sort((a,b)=>a.source_id.localeCompare(b.source_id)||a.series.localeCompare(b.series));
  options($('series'),list.map(s=>[s.sid,`${sourceNames[s.source_id] ?? s.source_id} · ${s.series}`]));
  const preferred=list.find(s=>s.source_id===($('donor').value==='CHN'?'gcdf':'fa') && ['adjusted commitment','disbursement'].includes(s.series));
  $('series').value=(preferred ?? list[0]).sid;
  state.sid=Number($('series').value);
}
function setYears(reset=false) {
  const compare=state.view==='compare', s=allSeries.get(state.sid);
  const first=compare?2001:Math.min(s?.first_year??2000,2000);
  const last=compare?Math.max(...data.national.map(r=>r.year)):Math.max(2026,s?.last_year??0);
  const choices=Array.from({length:last-first+1},(_,i)=>[first+i,first+i]);
  options($('from'),choices);options($('to'),choices);
  if(reset) {
    if(compare){state.from=2016;state.to=2025;}
    else if(s.first_year==null){state.from=2018;state.to=2026;}
    else {state.from=Math.max(first,s.last_year-10,s.first_year-1);state.to=Math.min(last,s.last_year+2);}
  }
  $('from').value=state.from;$('to').value=state.to;
}
function compareCell(c,y) {
  const {db,sector}=us.get([c,y].join('/'))??{};
  const status=db==null?(sector==null?'empty':'new') : sector==null?'old' : db===sector?'agree':sector>db?'higher':'lower';
  return {status,db,sector};
}
function observationCell(c,y) {
  const row=metrics.get(state.sid).get([c,y].join('/'));
  if (!row) return {status:activeYears.get(state.sid).has(y)?'empty':'outside'};
  const status=allSeries.get(state.sid).kind==='Programs'?'present':
    row.known===row.n?'complete':row.known===0?'missing':'partial';
  return {status,...row};
}
function cell(c,y) {return state.view==='compare'?compareCell(c,y):observationCell(c,y);}
function statusLabel(status) {return state.view==='compare'&&status==='empty'?'Neither release':labels[status];}
const yearName = y => y==null?'Undated':String(y);
function rank(c) {
  if(state.view==='compare') return Math.max(0,...periods.map(y=>{
    const v=compareCell(c.index,y);
    return v.db!=null && v.sector!=null?Math.abs(v.sector-v.db):0;
  }));
  return periods.reduce((acc,y)=>{const r=observationCell(c.index,y);return acc+(r.n!=null?r.n-r.known:0);},0);
}
const normalize=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();
function render() {
  periods=Array.from({length:state.to-state.from+1},(_,i)=>state.from+i);
  const compare=state.view==='compare', s=allSeries.get(state.sid);
  if(!compare)periods.push(null);
  const term=normalize($('query').value);
  filtered=countries.filter(c=>normalize(c.name+' '+c.iso3).includes(term));
  const ranks=new Map(filtered.map(c=>[c.index,$('sort').value==='priority'?rank(c):0]));
  filtered.sort((a,b)=>ranks.get(b.index)-ranks.get(a.index)||a.name.localeCompare(b.name));
  state.page=Math.min(state.page,Math.max(0,Math.ceil(filtered.length/pageSize)-1));
  const visible=filtered.slice(state.page*pageSize,(state.page+1)*pageSize);
  if(!visible.some(c=>c.iso3===state.selected))state.selected=visible[0]?.iso3;
  if(!periods.includes(state.year))state.year=compare?periods.at(-1):(s.undated===s.records?null:Math.min(s.last_year??state.to,state.to));
  if(!periods.includes(state.year))state.year=periods[0];
  $('heading').textContent=compare?'Country × U.S. fiscal year':'Country × observation year';
  $('subtitle').textContent=compare?'Current USD. Select a cell to compare the country file in the database with the separately archived U.S. sector report.':
    `${sources.get(s.source_id).title}. ${fmt(s.records)} records across ${fmt(s.countries)} jurisdictions. ${fmt(s.undated)} have no year.`;
  const keys=compare?['agree','higher','lower','new','old','empty']:s.kind==='Programs'?['present','empty','outside']:['complete','partial','missing','empty','outside'];
  $('legend').innerHTML=keys.map(k=>`<span><i class="${k}"></i>${esc(statusLabel(k))}</span>`).join('');
  $('matrix').innerHTML='<thead><tr><th scope="col">Country</th>'+periods.map(y=>`<th scope="col">${yearName(y)}</th>`).join('')+'</tr></thead><tbody>'+
    visible.map(c=>`<tr><th scope="row">${esc(c.name)}</th>${periods.map(y=>{
      const r=cell(c.index,y), label=c.name+' · '+yearName(y)+' · '+statusLabel(r.status);
      return `<td><button class="cell ${r.status}" data-country="${c.iso3}" data-year="${y??''}" aria-pressed="${c.iso3===state.selected && y===state.year}" aria-label="${esc(label)}" title="${esc(label)}"></button></td>`;
    }).join('')}</tr>`).join('')+'</tbody>';
  $('pageInfo').textContent=filtered.length?`${state.page*pageSize+1}–${Math.min(filtered.length,(state.page+1)*pageSize)} of ${filtered.length} jurisdictions`:'No matching country or territory';
  $('prev').disabled=state.page===0;$('next').disabled=(state.page+1)*pageSize>=filtered.length;
  $('export').disabled=!filtered.length;
  detail();
}
function detail() {
  const c=countries.find(c=>c.iso3===state.selected);
  if(!c){$('detail').innerHTML='<h2>No selection</h2>';return;}
  const r=cell(c.index,state.year),s=allSeries.get(state.sid);
  const top=`<h2>${esc(c.name)}</h2><p>${c.iso3} · ${yearName(state.year)}</p><h3 class="status"><i class="swatch ${r.status}"></i>${esc(statusLabel(r.status))}</h3>`;
  const dl=rows=>'<dl>'+rows.map(([k,v])=>`<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')+'</dl>';
  if(state.view==='compare'){
    const matched=r.db!=null && r.sector!=null;
    $('detail').innerHTML=top+dl([['Database',money(r.db)],['Sector file',money(r.sector)],['Sector minus database',matched?money(r.sector-r.db):'—']])+
      '<p>'+(matched?'Difference between published snapshots, in nominal USD.':'A missing observation has no amount for calculating a paired difference.')+'</p>'+
      link(sources.get('us_sector_review').download_url,'Sector report extract');
  } else {
    const details=r.n==null?'':dl([['Source records',fmt(r.n)],...(s.kind==='Programs'?[]:[
      ['Numeric values',fmt(r.known)],['Numeric disclosure',fmt(100*r.known/r.n)+'%'],['Text-only values',fmt(r.reported-r.known)],['Unreported values',fmt(r.n-r.reported)],['Reported zeroes',fmt(r.zeroes)]]),...(s.kind==='Funding'?[['Summary-eligible rows',fmt(r.eligible)]]:[])]);
    $('detail').innerHTML=top+details+'<p>'+esc(r.status==='outside'?'No record in any jurisdiction for this series and period.':r.status==='empty'?'The series contains observations elsewhere for this period. The country’s activity is unverified.':state.year==null?'The database cannot assign these observations to a year.':s.kind==='Results'?'Year is the indicator observation year.':'Values describe the retained source records. An undisclosed amount stays unknown.')+'</p>'+
      link(sources.get(s.source_id).download_url,'Pinned source file');
  }
}
function mode(view) {
  state.view=view;state.page=0;
  ['compare','observe'].forEach(id=>$(id).setAttribute('aria-pressed',String(view===id)));
  ['donorField','kindField','seriesField'].forEach(id=>$(id).hidden=view==='compare');
  $('sort').options[0].textContent=view==='compare'?'Largest paired difference':'Most missing numeric values';
  if(view==='observe')seriesMenus();setYears(true);render();
}
$('compare').onclick=()=>mode('compare');$('observe').onclick=()=>mode('observe');
$('donor').onchange=()=>{seriesMenus(true);setYears(true);state.page=0;render();};
$('kind').onchange=()=>{seriesMenus();setYears(true);state.page=0;render();};
$('series').onchange=()=>{state.sid=Number($('series').value);setYears(true);state.page=0;render();};
$('query').oninput=$('sort').onchange=()=>{state.page=0;render();};
$('from').onchange=$('to').onchange=e=>{
  state.from=Number($('from').value);state.to=Number($('to').value);
  if(state.to<state.from){if(e.target.id==='from')state.to=state.from;else state.from=state.to;}
  $('from').value=state.from;$('to').value=state.to;state.page=0;render();
};
$('prev').onclick=()=>{state.page--;render();};$('next').onclick=()=>{state.page++;render();};
$('matrix').onclick=e=>{
  const b=e.target.closest('.cell');if(!b)return;
  $('matrix').querySelector('[aria-pressed=true]')?.setAttribute('aria-pressed','false');
  b.setAttribute('aria-pressed','true');state.selected=b.dataset.country;state.year=b.dataset.year===''?null:Number(b.dataset.year);
  detail();
  if(matchMedia('(max-width:900px)').matches)$('detail').scrollIntoView({block:'nearest'});
};
$('export').onclick=()=>{
  const compare=state.view==='compare', s=allSeries.get(state.sid);
  const rows=[compare?['iso3','fiscal_year','status','database_usd','sector_report_usd','paired_difference_usd']:['iso3','year','provider','type','source','measure','status','records','numeric_or_present','reported','zeroes','summary_eligible']];
  for(const c of filtered)for(const y of periods){
    const r=cell(c.index,y);
    rows.push(compare?[c.iso3,y,statusLabel(r.status),r.db,r.sector,r.db!=null&&r.sector!=null?r.sector-r.db:null]:[c.iso3,y,s.provider,s.kind,s.source_id,s.series,statusLabel(r.status),r.n,r.known,r.reported,r.zeroes,r.eligible]);
  }
  const csv=rows.map(row=>row.map(v=>'"'+String(v??'').replace(/"/g,'""')+'"').join(',')).join('\r\n');
  const url=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'})),a=document.createElement('a');
  a.href=url;a.download='coverage-'+(compare?'US-spending':s.provider+'-'+s.source_id)+'-'+state.from+'-'+state.to+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1500);
};
const recent=data.national.filter(r=>r.release==='sector_archive' && r.year>=2020);
$('nationalTable').innerHTML='<thead><tr><th>U.S. FY</th><th>Database · country rows</th><th>Sector file · country rows</th><th>Sector file · outside registry</th><th>Sector file · all geography</th></tr></thead><tbody>'+recent.map(r=>`<tr><th>${r.year}</th>${[r.database_usd,r.report_in_registry_usd,r.report_outside_registry_usd,r.report_world_usd].map(v=>`<td class="val" title="${money(v)}">${v==null?'No observation':billions.format(v)}</td>`).join('')}</tr>`).join('')+'</tbody>';
$('usLinks').innerHTML=[link(sources.get('fa').download_url,'Database country-file vintage'), link(sources.get('us_sector_review').download_url,'Sector-file vintage'),link(sources.get('fa').publisher_url,'U.S. reporting portal')].join(' · ');
const kenya=sources.get('kenya_debt');
$('kenyaLinks').innerHTML=[link(kenya.download_url+'#page=1','Archived national creditor summary, p. 1'),link(kenya.download_url+'#page=23','Loan 2014006_1, p. 23'),link(kenya.publisher_url,'National Treasury')].join(' · ');
seriesMenus(true);mode('compare');
