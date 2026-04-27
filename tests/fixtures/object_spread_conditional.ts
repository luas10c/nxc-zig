export function buildQuery(isAdmin: boolean, store: { id: number }) {
  return {
    ...(isAdmin ? {} : { store: { id: store.id } }),
  };
}
