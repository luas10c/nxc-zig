// Class method overloads
class Resolver {
  resolve(value: string): string;
  resolve(value: number): number;
  resolve(value: string | number): string | number {
    return value;
  }

  static create(id: string): Resolver;
  static create(id: number): Resolver;
  static create(id: string | number): Resolver {
    return new Resolver();
  }

  get name(): string;
  get name(): string {
    return "resolver";
  }
}

// Constructor overloads
class Point {
  constructor(x: number, y: number);
  constructor(coords: [number, number]);
  constructor(xOrCoords: number | [number, number], y?: number) {
    // implementation
  }
}

// Interface (should be fully stripped)
interface Formatter {
  format(value: string): string;
  format(value: number): string;
}

// Standalone function overloads
function parse(value: string): string[];
function parse(value: number): number[];
function parse(value: string | number) {
  return [value];
}

export async function load(id: string): Promise<string>;
export async function load(id: number): Promise<string>;
export async function load(id: string | number): Promise<string> {
  return String(id);
}
