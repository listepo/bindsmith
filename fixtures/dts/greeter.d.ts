/** Options accepted by {@link Greeter}. */
export interface GreeterOptions {
  /** Text placed before the name. */
  prefix?: string;
  loud: boolean;
  tone: 'formal' | 'casual';
  onGreet?: (message: string) => void;
  [extra: string]: unknown;
}

/** Greets people. */
export declare class Greeter {
  static readonly version: string;
  readonly name: string;
  constructor(name: string, options?: GreeterOptions);
  /** Returns the greeting. */
  greet(): string;
  greet(times: number): string[];
  /**
   * Greets after a delay.
   *
   * @param delayMs How long to wait, in milliseconds.
   * @returns the greeting, once the delay has passed.
   */
  greetLater(delayMs: number): Promise<string>;
  get uppercase(): boolean;
  set uppercase(value: boolean);
  private secret(): void;
}

export declare function createGreeter(name: string, options?: GreeterOptions): Greeter;

export declare const VERSION: string;

export declare enum Tone {
  Formal = 'formal',
  Casual = 'casual',
}

export type GreetCallback = (message: string) => void;

export declare namespace utils {
  function shout(text: string): string;
}

export declare class Box<T> {
  value: T;
  map<U>(transform: (value: T) => U): Box<U>;
}
