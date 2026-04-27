type RouteSchemaOptions = Record<string, unknown>;

declare const openapiMetadata: RouteSchemaOptions | undefined;
declare const validator:
  | {
      source: string;
      schema: unknown;
    }
  | undefined;

const routeOptions: RouteSchemaOptions | undefined = (() => {
  const options: RouteSchemaOptions = { ...(openapiMetadata ?? {}) };

  if (validator) {
    options[validator.source] = validator.schema;
  }

  return Object.keys(options).length > 0 ? options : undefined;
})();

const a = (() => 123)();

const b = (() => {
  return 456;
})();

const c = (async () => {
  return 789;
})();

const d = ((x: number) => x * 2)(10);

const e = (({ x }: { x: number }) => x)({ x: 1 });

const f = (() => ({ value: 1 }))();

const g = (() => {
  const obj = { ...(openapiMetadata ?? {}) };
  return obj;
})();

const h = (() => {
  return () => 1;
})()();

const i = 1 + (() => 2)();

function call(fn: () => number) {
  return fn();
}

const j = call((() => 42));
