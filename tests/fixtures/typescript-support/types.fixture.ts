// export type
export type UserId = string;
export type Maybe<T> = T | null;

// interface
export interface User {
  id: number;
  name: string;
  email?: string;
}

// keyof
type UserKey = keyof User;

// typeof in type position
declare const config: object;
type ConfigType = typeof config;

// Partial, Record, Exclude
type PartialUser = Partial<User>;
type Dict = Record<string, number>;
type ExcludeNull<T> = Exclude<T, null>;

// conditional types
type IsString<T> = T extends string ? true : false;
export type NoInfer<T> = [T][T extends any ? 0 : never];

// indexed access
type NameType = User["name"];
type First<T extends any[]> = T[0];

// optional property in type
interface Config {
  debug?: boolean;
  timeout?: number;
}

export function useConfig(cfg: Config): boolean {
  return cfg.debug ?? false;
}
