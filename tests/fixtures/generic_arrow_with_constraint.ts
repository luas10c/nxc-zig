type GetTemplateTuple<T> = T extends string ? [T] : never;
type Message = string;

// Generic arrow with extends constraint (must work in JSX mode too)
export const printMessage =
  <ArgTypes extends GetTemplateTuple<Message>>(
    ...args: ArgTypes
  ) => {
    return args;
  };

// Generic arrow with extends and default
export const wrap = <T extends object, U = T>(value: T): U => {
  return value as unknown as U;
};

// Generic arrow with trailing comma (JSX disambiguator)
export const identity = <T,>(value: T): T => value;

// Nested generic constraint
export const pick = <T extends object, K extends keyof T>(obj: T, key: K): T[K] => {
  return obj[key];
};
