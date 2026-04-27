// Class with class decorator + constructor param decorators
@Singleton()
class ServiceA {
  constructor(
    @Dep('TOKEN_A') private tokenA: string,
    @Dep('TOKEN_B') private tokenB: number,
  ) {}
}

// Class WITHOUT class decorator, only constructor param decorators
class ServiceB {
  constructor(
    @Dep('TOKEN') private token: string,
  ) {}
}

// Export class with constructor param decorators
@Singleton()
export class ServiceC {
  constructor(
    @Dep('DEP') private dep: ServiceA,
  ) {}
}

// Export class without class decorator
export class ServiceD {
  constructor(
    @Dep('DEP') private dep: ServiceA,
  ) {}
}

// Multiple decorators on same param
class ServiceE {
  constructor(
    @DecA() @DecB() private value: string,
  ) {}
}

// Mix: class decorator + method decorator + constructor param decorator
@Singleton()
class ServiceF {
  @Log()
  method(): void {}

  constructor(
    @Dep('CTOR') private dep: ServiceA,
  ) {}
}
