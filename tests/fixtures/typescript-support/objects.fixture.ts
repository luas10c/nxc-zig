// object spread
export function merge<T extends object>(a: T, b: Partial<T>): T {
  return { ...a, ...b };
}

// conditional spread
export function buildQuery(isAdmin: boolean, storeId: string) {
  return {
    select: ["id", "name"],
    ...(isAdmin ? {} : { where: { storeId } }),
  };
}

// Object.fromEntries
export function fromPairs<V>(pairs: [string, V][]): Record<string, V> {
  return Object.fromEntries(pairs);
}

// array spread with conditional
const base = ["a", "b"];
export const extended = [...base, ...(Math.random() > 0.5 ? ["c"] : [])];
