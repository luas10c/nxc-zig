// legacy type assertions
const raw: unknown = "hello";
export const asString = <string>raw;
export const asAny = <any>raw;

// as assertions
export const modern = raw as string;
export const modernAny = raw as any;

// non-null assertion
export function unwrap<T>(val: T | null): T {
  return val!;
}

// as const
export const directions = ["up", "down", "left", "right"] as const;

// satisfies
const palette = { red: [255, 0, 0] } satisfies Record<string, number[]>;
