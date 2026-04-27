export type Payload<T> = {
  value?: T;
};

const register = (value) => value;

export const pick = <T>(payload?: Payload<T>) => payload?.value;

@register
export class Fixture {
}
