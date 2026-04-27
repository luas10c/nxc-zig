// Basic for await...of
async function processAll(list: AsyncIterable<string>): Promise<void> {
  for await (const e of list) {
    console.log(e);
  }
}

// for await with expression body
async function processEach(list: AsyncIterable<number>, fn: (n: number) => Promise<void>): Promise<void> {
  for await (const e of list) await fn(e);
}

// Regular for...of still works
function processSync(list: Iterable<string>): void {
  for (const e of list) {
    console.log(e);
  }
}
