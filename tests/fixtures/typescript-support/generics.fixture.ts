// generic function
export function identity<T>(value: T): T {
  return value;
}

// generic function with constraint
export function getKey<T extends object, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

// generic async function with callback type
export async function transactional<T>(cb: () => T): Promise<T> {
  return cb();
}

// generic class
export class Repository<T> {
  constructor(private items: T[] = []) {}

  add(item: T): void {
    this.items.push(item);
  }

  getAll(): T[] {
    return this.items;
  }
}

// generic class with constructor type
interface Ctor<T> {
  new (): T;
}

export function create<T>(C: Ctor<T>): T {
  return new C();
}

// NoInfer utility type usage
export type NoInfer<T> = [T][T extends any ? 0 : never];

export function setDefault<T>(value: T, fallback: NoInfer<T>): T {
  return value ?? fallback;
}
