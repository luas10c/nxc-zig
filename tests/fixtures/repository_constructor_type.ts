export class Repository<T> {
  constructor(private Entity: new () => T) {}

  create(): T {
    return new this.Entity();
  }
}

export class ProtectedRepository<T> {
  constructor(protected Entity: new () => T) {}

  create(): T {
    return new this.Entity();
  }
}

export class ReadonlyRepository<T> {
  constructor(readonly Entity: new () => T) {}

  create(): T {
    return new this.Entity();
  }
}
