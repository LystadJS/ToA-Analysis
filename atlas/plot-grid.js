// Place neutral guides beneath the interactive marks. Minor guides bisect
// adjacent axis breaks, the same convention used by ggplot2 continuous scales.
export function plotGrid(xs, ys, left, right, top, bottom) {
  const middle = (positions) => positions.slice(1).map((p, i) => (p + positions[i]) / 2);
  const path = (x, y) => [
    ...x.map((p) => `M${p} ${top}V${bottom}`),
    ...y.map((p) => `M${left} ${p}H${right}`),
  ].join(' ');
  return `<g aria-hidden="true"><path class="plotGrid minor" d="${path(middle(xs), middle(ys))}"/><path class="plotGrid" d="${path(xs, ys)}"/></g>`;
}
