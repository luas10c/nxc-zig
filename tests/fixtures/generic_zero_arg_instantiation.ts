type LengthAwareIterable<T = any> = Iterable<T> & { length: number };
type LengthAwareAsyncIterable<T = any> = AsyncIterable<T> & { length: number };

const isLengthAwareAsyncIterable = <T = any>(value: unknown): value is LengthAwareAsyncIterable<T> => {
  return !!value && typeof value === "object" && "length" in value;
};

const isLengthAwareIterable = <T = any>(value: unknown): value is LengthAwareIterable<T> => {
  return !!value && typeof value === "object" && "length" in value;
};

export const LengthAwareAsyncIterable = <T = any>() => isLengthAwareAsyncIterable<T>;
export const LengthAwareIterable = <T = any>() => isLengthAwareIterable<T>;
