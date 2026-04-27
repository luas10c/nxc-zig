declare global {
  interface Array<T> {
    first(): T | undefined;
  }
}

export const ok = 1;
