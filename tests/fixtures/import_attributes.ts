// static import with attribute
import db from './database.json' with { type: 'json' };
import schema from './schema.json' with { type: 'json' };

// side-effect import with attribute
import './polyfill.js' with { type: 'javascript' };

// dynamic import with attribute
export async function loadData() {
  const data = await import('./data.json', { with: { type: 'json' } });
  return data.default;
}

export { db, schema };
