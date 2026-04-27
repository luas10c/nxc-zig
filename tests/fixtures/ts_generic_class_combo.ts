interface BoxLike<T> {
  value: T;
}

interface BoxCtor<T> {
  new (value: T): BoxLike<T>;
}

export function identity<T>(value: T): T {
  return value;
}

export class Box<T> implements BoxLike<T> {
  constructor(public value: T) {}
}

export function createBox<T>(Ctor: BoxCtor<T>, value: T) {
  return new Ctor(identity(value));
}
