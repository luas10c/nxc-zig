function register(target: unknown) {
  return target;
}

@register
export class Fixture {
  constructor() {}
}
