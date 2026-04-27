type Request = {
  body: unknown;
  params: Record<string, string>;
  query?: Record<string, string>;
};

type Response = {
  status(code: number): Response;
  json(value: unknown): void;
};

type Context = {
  req: Request;
  res: Response;
};

const routeHandler = async ({
  req,
  res,
}: Context) => {
  return res.status(200).json({
    body: req.body,
    params: req.params,
  });
};

const handler1 = async ({ req, res }: Context) => {
  return res.json(req.body);
};

const handler2 = async ({
  req,
  res,
}: {
  req: Request;
  res: Response;
}) => {
  return res.status(201).json(req.params);
};

const handler3 = async ({ req }: { req: Request }) => {
  return req.body;
};

const handler4 = async ({ req, res }: Context = defaultContext) => {
  return res.json(req.query);
};

const handler5 = async (
  {
    req,
    res,
  }: Context,
) => {
  return res.status(204).json(null);
};

declare const defaultContext: Context;
