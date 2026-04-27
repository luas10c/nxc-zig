interface User {
  id: number;
  name: string;
}

type A = string | number;
type UserKey = keyof User;

export async function loadUser(key: UserKey, value: A): Promise<User> {
  return {
    id: typeof value === "number" ? value : key.length,
    name: key,
  };
}
