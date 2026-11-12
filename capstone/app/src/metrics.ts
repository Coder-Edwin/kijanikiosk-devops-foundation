// Minimal Prometheus text-format metrics without an external client library.
type Labels = Record<string, string>;
const counters = new Map<string, { help: string; values: Map<string, number> }>();

function key(labels: Labels): string {
  return Object.keys(labels).sort().map((k) => `${k}="${labels[k].replace(/"/g, '\\"')}"`).join(",");
}

export function defineCounter(name: string, help: string): void {
  if (!counters.has(name)) counters.set(name, { help, values: new Map() });
}

export function inc(name: string, labels: Labels, by = 1): void {
  const c = counters.get(name);
  if (!c) throw new Error(`unknown counter ${name}`);
  const k = key(labels);
  c.values.set(k, (c.values.get(k) ?? 0) + by);
}

export function render(extra: string[] = []): string {
  const out: string[] = [];
  for (const [name, c] of counters) {
    out.push(`# HELP ${name} ${c.help}`, `# TYPE ${name} counter`);
    for (const [k, v] of c.values) out.push(`${name}{${k}} ${v}`);
  }
  return out.concat(extra).join("\n") + "\n";
}
