// Object.fromEntries
export function zipToRecord(keys: string[], values: number[]): Record<string, number> {
  return Object.fromEntries(keys.map((k, i) => [k, values[i]]));
}

// array includes
export function isAllowed(role: string): boolean {
  return ["admin", "editor", "viewer"].includes(role);
}

// arrow functions in array methods
const items = [{ id: 1, name: "Alice" }, { id: 2, name: "Bob" }];

export const names = items.map(item => item.name);
export const filtered = items.filter(item => item.id > 1);
export const ids = items.map(({ id }) => id);

// async/await
export async function fetchData(url: string): Promise<string> {
  const result = await Promise.resolve(url);
  return result;
}

// Promise.all
export async function parallel<T>(tasks: Promise<T>[]): Promise<T[]> {
  return Promise.all(tasks);
}
