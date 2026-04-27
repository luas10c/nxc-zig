type LengthAwareIterable<T = any> = Iterable<T> & { length: number };
type LengthAwareAsyncIterable<T = any> = AsyncIterable<T> & { length: number };

// Type predicate with generic type in return annotation
export const isLengthAwareAsyncIterable = <T>(
  value: unknown,
): value is LengthAwareAsyncIterable<T> => {
  return !!value && typeof value === "object" && "length" in value;
};

// Type predicate with double-cast generic function type
export const isLengthAwareIterable = ((value: unknown) => {
  return !!value && typeof value === "object" && "length" in value;
}) as unknown as <T = any>(
  value: unknown,
) => value is LengthAwareIterable<T>;

// Simple type predicate (no generics)
export function isString(value: unknown): value is string {
  return typeof value === "string";
}

// Type predicate in arrow without generics
export const isNumber = (value: unknown): value is number => {
  return typeof value === "number";
};

// `asserts` predicate
export function assertString(value: unknown): asserts value is string {
  if (typeof value !== "string") throw new Error("not a string");
}
