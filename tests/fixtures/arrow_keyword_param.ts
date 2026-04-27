type OptionsSchema = {
  from: string;
};

type ParsedOptions = {
  from: string;
};

export const transform = (from: OptionsSchema): ParsedOptions => {
  return from;
};
