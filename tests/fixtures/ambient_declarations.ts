declare const declaredValue: string;

declare function declaredFn(value: number): void;

declare class AmbientService {
  name: string;
  run(): Promise<void>;
}

declare namespace AmbientNamespace {
  const value: number;
}

export declare const exportedDeclaredValue: number;

export const runtimeValue = 1;
