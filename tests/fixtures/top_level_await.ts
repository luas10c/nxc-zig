const source = Promise.resolve(41);

export const value = await source;
export const next = value + 1;
