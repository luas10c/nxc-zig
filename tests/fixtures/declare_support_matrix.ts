// modules
declare module "pkg" {}
declare module "*.css" {}
declare module "*.json" {}

// namespace
declare namespace aa {}
declare namespace aa {
  function fn(): void
  const version: string
}

// variables
declare var a: string
declare let b: number
declare const c: boolean

// functions
declare function fn(): void
declare function fn2(a: number, b: number): number

// overload
declare function over(x: string): string
declare function over(x: number): number

// generics
declare function identity<T>(value: T): T

// classes
declare class A {}
declare class B {
  constructor(name: string)
  method(): void
}

// abstract class
declare abstract class Base {
  abstract run(): void
}

// static
declare class Config {
  static load(): Config
}

// interface
declare interface User {
  id: string
  name: string
}

// type
declare type ID = string | number

// enum
declare enum Direction {
  Up,
  Down
}

// const enum
declare const enum Colors {
  Red,
  Blue
}

// hybrid (function + namespace)
declare function lib(): void
declare namespace lib {
  let version: string
}

// global
declare global {
  interface Window {
    myProp: string
  }
}

// merging
declare namespace Merge {
  function a(): void
}
declare namespace Merge {
  function b(): void
}

// import/export inside module
declare module "pkg2" {
  import { A } from "other"
  export const value: A
}

// re-export
declare module "pkg3" {
  export * from "other"
}

// computed property
declare const obj: {
  [key: string]: number
}

// index signature interface
declare interface Dict {
  [key: string]: any
}

// callable interface
declare interface Fn {
  (a: number): string
}

// newable interface
declare interface Ctor {
  new (name: string): any
}

// intersection / union
declare type Mix = { a: number } & { b: string }
declare type Either = string | number

// tuple
declare type Tuple = [number, string]

// readonly
declare interface ReadonlyUser {
  readonly id: string
}

// optional
declare interface Opt {
  value?: number
}

// ambient class with property
declare class WithProps {
  prop: string
}

// ambient class with computed
declare class WithComputed {
  [key: string]: any
}

// ambient class with overload
declare class OverloadClass {
  method(a: string): string
  method(a: number): number
}

// export declare
export declare const exported: number
export declare function exportedFn(): void

// decorator
declare class Decorated {
  @dec prop: string
}

// typeof
declare const ref: { a: number }
declare type RefType = typeof ref

// keyof
declare type Keys = keyof { a: number; b: string }

// conditional type
declare type Cond<T> = T extends string ? true : false

// mapped type
declare type Mapped<T> = {
  [K in keyof T]: T[K]
}

// infer
declare type Infer<T> = T extends infer U ? U : never

// satisfies (type-level only usage context)
declare const config: {
  port: number
}

// function with this
declare function withThis(this: { x: number }): void

// async function typing
declare function asyncFn(): Promise<void>

// symbol
declare const sym: unique symbol

// bigint
declare const big: bigint

// template literal type
declare type EventName = `on${string}`

// module augmentation
declare module "pkg" {
  interface Request {
    permission?: string
  }
}
