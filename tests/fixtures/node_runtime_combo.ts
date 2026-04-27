const extras = ["b", ...((Math.random() > -1 ? ["c"] : []))];

function readValues({ a, b } = { a: 4, b: 6 }) {
  return { a, b };
}

const { a, b } = readValues();

class Runner {
  async compute(obj) {
    await Promise.resolve();
    const base = obj?.a ?? 0;
    const bonus = extras.includes("c") ? 1 : 0;
    return base + a + b + bonus;
  }
}

async function main() {
  const runner = new Runner();
  const result = await runner.compute(undefined);
  if (result !== 11) throw new Error(`unexpected:${result}`);
  console.log(`ok:${result}`);
}

main();
