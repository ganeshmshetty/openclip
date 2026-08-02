import { NextResponse } from 'next/server';

export interface ExtensionItem {
  id: string;
  name: string;
  description: string;
  author: string;
  icon: string;
  category: string;
  downloadCount: number;
  downloadURL: string;
}

export interface ExtensionsPageResponse {
  extensions: ExtensionItem[];
  page: number;
  totalPages: number;
  totalCount: number;
}

const REPO = 'ganeshmshetty/openclip';
const BRANCH = 'main';
const CATALOG_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/catalog.json`;
const STATS_URL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/extension-stats.json`;

// Optional GitHub token (set as GH_TOKEN in the Vercel environment) to raise
// api.github.com rate limits if raw.githubusercontent ever throttles us.
const GITHUB_TOKEN = process.env.GITHUB_TOKEN || '';

function githubHeaders(): HeadersInit {
  return GITHUB_TOKEN ? { Authorization: `Bearer ${GITHUB_TOKEN}` } : {};
}

// Download counts are published nightly to extension-stats.json by the
// update-stats.yml workflow (Obsidian model). Serve from a short cache to
// avoid re-fetching on every request; stats only change once a day.
const STATS_TTL_MS = 60 * 60 * 1000;
let cachedStats: Record<string, number> | null = null;
let cachedStatsAt = 0;
const CATALOG_TTL_MS = 5 * 60 * 1000;
let cachedCatalog: ExtensionItem[] | null = null;
let cachedCatalogAt = 0;async function loadStats(): Promise<Record<string, number> | null> {
  const now = Date.now();
  if (cachedStats && now - cachedStatsAt < STATS_TTL_MS) {
    return cachedStats;
  }
  try {
    const res = await fetch(STATS_URL, {
      headers: githubHeaders(),
      cache: 'no-store',
    });
    if (!res.ok) return cachedStats;
    const data = (await res.json()) as { downloads?: Record<string, number> };
    cachedStats = data.downloads ?? {};
    cachedStatsAt = Date.now();
    return cachedStats;
  } catch {
    return cachedStats;
  }
}

async function loadCatalog(): Promise<ExtensionItem[]> {
  const now = Date.now();
  if (cachedCatalog && now - cachedCatalogAt < CATALOG_TTL_MS) {
    return cachedCatalog;
  }

  try {
    const res = await fetch(CATALOG_URL, {
      headers: githubHeaders(),
      cache: 'no-store',
    });
    if (!res.ok) {
      console.warn('Catalog fetch failed:', res.status);
      return cachedCatalog ?? [];
    }

    const data = (await res.json()) as {
      extensions?: Omit<ExtensionItem, 'downloadCount'>[];
    };

    // Merge GitHub Release download counts published nightly to extension-stats.json.
    const stats = await loadStats();
    if (stats === null) {
      // Statistics are unavailable and there is no prior valid snapshot: don't cache a
      // zeroed catalog for five minutes. Fall back to the last valid merged catalog.
      console.warn('Stats unavailable; serving last valid catalog');
      return cachedCatalog ?? [];
    }

    const merged = (data.extensions ?? []).map((item) => ({
      ...item,
      downloadCount: stats[item.id] ?? 0,
    }));
    cachedCatalog = merged;
    cachedCatalogAt = Date.now();
    return merged;
  } catch (err) {
    console.error('Failed to load catalog:', err);
    return cachedCatalog ?? [];
  }
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = (searchParams.get('q') || '').toLowerCase().trim();
  const category = (searchParams.get('category') || 'all').toLowerCase().trim();
  // Number() rejects malformed input ("2abc") and non-integers ("1.9") as NaN,
  // so only well-formed integer values are normalized into the valid range.
  const rawPage = Number(searchParams.get('page') ?? '1');
  const rawLimit = Number(searchParams.get('limit') ?? '12');
  const page = Number.isInteger(rawPage) ? Math.max(1, rawPage) : 1;
  const limit = Number.isInteger(rawLimit) ? Math.min(100, Math.max(1, rawLimit)) : 12;

  let filtered = await loadCatalog();

  if (category !== 'all') {
    filtered = filtered.filter((ext) => ext.category.toLowerCase() === category);
  }

  if (q) {
    filtered = filtered.filter(
      (ext) =>
        ext.name.toLowerCase().includes(q) ||
        ext.description.toLowerCase().includes(q) ||
        ext.author.toLowerCase().includes(q)
    );
  }

  const totalCount = filtered.length;
  const totalPages = Math.ceil(totalCount / limit) || 1;
  const startIndex = (page - 1) * limit;
  const paginatedExtensions = filtered.slice(startIndex, startIndex + limit);

  return NextResponse.json(
    { extensions: paginatedExtensions, page, totalPages, totalCount },
    {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Cache-Control': 'public, s-maxage=60, stale-while-revalidate=300',
      },
    }
  );
}
