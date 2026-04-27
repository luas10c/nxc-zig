// optional chaining
export function getNestedValue(obj?: { a?: { b?: number } }): number {
  return obj?.a?.b ?? 0;
}

// optional computed member
export function getFirst(arr?: string[]): string {
  return arr?.[0] ?? "";
}

// optional call
export function maybeCall(fn?: () => void): void {
  fn?.();
}

// nullish coalescing
export function withDefault(value: string | null | undefined): string {
  return value ?? "default";
}

// optional parameter
export function greet(name?: string): string {
  return `Hello ${name ?? "world"}`;
}

// optional property in interface
interface Options {
  timeout?: number;
  retries?: number;
  onError?: (err: Error) => void;
}

export function run(opts: Options = {}): void {
  const t = opts.timeout ?? 5000;
  const r = opts.retries ?? 3;
  console.log(t, r);
}

// destructuring with defaults
export function readValues({ a = 0, b = 0 }: { a?: number; b?: number } = {}): number {
  return a + b;
}
