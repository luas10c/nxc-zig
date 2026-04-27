export function parse(result?: any) {
  const value = result?.[0]?.data ?? "";
  return value;
}
