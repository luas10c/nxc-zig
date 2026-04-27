// Simula enum (caso comum)
export enum StoreTypeEnum {
  MARKETPLACE = "marketplace",
  STORE = "store",
}

// Tambem cobre outros formatos equivalentes
export type StoreTypeUnion = "marketplace" | "store";

export namespace Types {
  export type StoreType = "marketplace" | "store";
}

// Caso principal (o seu erro)
export const mpTaxes = (type: StoreTypeEnum) => {
  return type;
};

// Variacoes importantes

// Type alias (union)
export const fn1 = (type: StoreTypeUnion) => {
  return type;
};

// Namespace type
export const fn2 = (type: Types.StoreType) => {
  return type;
};

// Retorno tipado
export const fn3 = (type: StoreTypeEnum): number => {
  return 1;
};

// Multiplos parametros
export const fn4 = (a: number, type: StoreTypeEnum, b: string) => {
  return type;
};

// Arrow function com corpo expressao
export const fn5 = (type: StoreTypeEnum) => type;

// Default value
export const fn6 = (type: StoreTypeEnum = StoreTypeEnum.MARKETPLACE) => {
  return type;
};

// Optional parameter
export const fn7 = (type?: StoreTypeEnum) => {
  return type;
};

// Rest parameter
export const fn8 = (...types: StoreTypeEnum[]) => {
  return types;
};

// Com destructuring (edge)
export const fn9 = ({ type }: { type: StoreTypeEnum }) => {
  return type;
};
