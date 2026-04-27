// Combines all major TypeScript features in one file

// Enums
export enum Direction {
  Up = "UP",
  Down = "DOWN",
}

// Namespace
export namespace Utils {
  export function noop(): void {}
}

// Interfaces with optional and index signature
export interface Store<T> {
  id: string;
  data?: T;
  meta: Record<string, unknown>;
}

// Type aliases with conditionals and indexed access
export type Nullable<T> = T | null;
export type Unwrap<T> = T extends Promise<infer U> ? U : T;
export type NoInfer<T> = [T][T extends any ? 0 : never];

// Generic class with constructor param properties
export class BaseService<T> {
  constructor(
    protected readonly name: string,
    private items: T[] = [],
  ) {}

  getAll(): T[] {
    return this.items;
  }
}

// Decorator
function singleton(target: any) { return target; }

@singleton
export class AppService extends BaseService<string> {
  constructor() {
    super("app");
  }

  async run(cb: () => Promise<void>): Promise<void> {
    await cb();
  }
}

// Constructor type
interface ServiceCtor<T> {
  new (name: string): T;
}

export function createService<T>(Ctor: ServiceCtor<T>, name: string): T {
  return new Ctor(name);
}

// Type assertions
const raw: unknown = {};
export const typed = raw as Store<string>;

// Non-null assertion
export function ensure<T>(val: T | null): T {
  return val!;
}

// Optional chaining + nullish coalescing
export function safeGet(store?: Store<string>): string {
  return store?.data ?? "fallback";
}

// Object spread + conditional spread
export function patch<T extends object>(base: T, override?: Partial<T>): T {
  return { ...base, ...(override ?? {}) };
}

// Arrow functions
export const double = (n: number): number => n * 2;
export const triple = n => n * 3;

// Array methods with typed arrows
const records: Store<number>[] = [];
export const ids = records.map(r => r.id);
export const hasData = records.filter(r => r.data != null).map(({ id }) => id);

// Regex
export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const digits = /\d+/g;
