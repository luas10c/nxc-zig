type Model = {
  value?: string;
};

const legacy: unknown = "legacy";
const modern: unknown = "modern";
const partialSource: Model = { value: "x" };

export const legacyString = <string>legacy;
export const legacyAny = <any>legacy;
export const legacyModel = <Model>partialSource;

export const modernString = modern as string;
export const modernAny = modern as any;
export const modernPartial = partialSource as Partial<Model>;
