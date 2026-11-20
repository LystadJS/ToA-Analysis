import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { build } from 'esbuild';
import { geoArea, geoEqualEarth, geoGraticule, geoPath } from 'd3-geo';

const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, '../artifacts');
const cache = path.join(output, 'atlas-build');
await mkdir(cache, { recursive: true });
const snapshot = JSON.parse(
  await readFile(path.join(cache, 'snapshot.json'), 'utf8'),
);
const geoFile = path.join(cache, 'map-units.geojson');
const digest =
  'b8d421aca6e9e08e8cdf09cc26af111cc3e0deba4fe915611d58ade71e8a4db0';
const geoURL =
  'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_50m_admin_0_map_units.geojson';
const hash = (buf) => createHash('sha256').update(buf).digest('hex');
let geo = await readFile(geoFile).catch(() => Buffer.alloc(0));
if (hash(geo) !== digest) {
  execFileSync('curl', [
    '-fsSL',
    '--retry',
    '3',
    geoURL,
    '-o',
    geoFile + '.tmp',
  ]);
  geo = await readFile(geoFile + '.tmp');
  if (hash(geo) !== digest)
    throw Error('Natural Earth archive failed checksum verification');
  await rename(geoFile + '.tmp', geoFile);
}
const index = new Map(snapshot.countries.map((c) => [c.iso3, c]));
const projection = geoEqualEarth().fitExtent(
  [
    [7, 8],
    [993, 477],
  ],
  { type: 'Sphere' },
);
const draw = geoPath(projection).digits(1);
const shapes = [];
const largest = new Map();
for (const feature of JSON.parse(geo).features) {
  const p = feature.properties;
  const code =
    p.GU_A3 === 'KOS'
      ? 'XKX'
      : [p.GU_A3, p.ISO_A3_EH, p.ISO_A3, p.ADM0_A3].find((c) => index.has(c));
  const polygons =
    feature.geometry.type === 'Polygon'
      ? [feature.geometry.coordinates]
      : feature.geometry.coordinates;
  for (const coordinates of polygons) {
    if (geoArea({ type: 'Polygon', coordinates }) > 2 * Math.PI)
      coordinates.forEach((r) => r.reverse());
  }
  const area = draw.area(feature);
  shapes.push({ code: code ?? null, path: draw(feature) });
  if (code && area > (largest.get(code) ?? -1)) {
    largest.set(code, area);
    Object.assign(index.get(code), {
      point: projection([p.LABEL_X, p.LABEL_Y]),
      region: p.SUBREGION,
      area,
    });
  }
}
// Representative selector positions for map units missing at 1:50m. UMI uses Wake Island.
for (const [code, lon, lat, region] of [
  ['BVT', 3.35, -54.42, 'South Atlantic'],
  ['GIB', -5.35, 36.14, 'Southern Europe'],
  ['UMI', 166.63, 19.29, 'Pacific islands'],
])
  Object.assign(index.get(code), {
    point: projection([lon, lat]),
    region,
    area: 0,
  });
if (snapshot.countries.some((c) => !c.point))
  throw Error('A country is missing its map selector');
snapshot.map = {
  shapes,
  grid: draw(geoGraticule().step([30, 20])()),
  outline: draw({ type: 'Sphere' }),
};
const js = await build({
  entryPoints: [path.join(here, 'app.js')],
  bundle: true,
  minify: true,
  write: false,
  target: 'es2020',
  legalComments: 'inline',
});
const fonts = await readFile(path.join(cache, 'fonts.css'), 'utf8');
const licenses = [];
for (const pkg of [
  'd3-geo',
  'd3-zoom',
  'd3-selection',
  'd3-array',
  'internmap',
  'd3-color',
  'd3-dispatch',
  'd3-drag',
  'd3-ease',
  'd3-interpolate',
  'd3-timer',
  'd3-transition',
  'fflate',
]) {
  licenses.push(
    pkg +
      '\n' +
      (await readFile(path.join(here, 'node_modules', pkg, 'LICENSE'), 'utf8')),
  );
}
const stylesheet = await readFile(path.join(here, 'style.css'), 'utf8');
const template = await readFile(path.join(here, 'index.html'), 'utf8');
const html = template
  .replace('/* ATLAS_CSS */', () => fonts + '\n' + stylesheet)
  .replace('ATLAS_SNAPSHOT', () =>
    JSON.stringify(snapshot).replace(/</g, '\\u003c'),
  )
  .replace('/* ATLAS_JS */', () =>
    js.outputFiles[0].text.replace(/<\/script/gi, '<\\/script'),
  )
  .replace('ATLAS_LICENSES', () =>
    licenses.join('\n\n').replace(/&/g, '&amp;').replace(/</g, '&lt;'),
  );
const target = path.join(output, 'Trade-over-Aid-Atlas.html');
await writeFile(target + '.tmp', html);
await rename(target + '.tmp', target);
console.log(target, (Buffer.byteLength(html) / 1048576).toFixed(1) + ' MiB');
