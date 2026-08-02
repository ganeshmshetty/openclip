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

// Cache the verified catalog so repeated searches don't hammer GitHub.
// Keyed by repo/branch; entries expire after a short TTL.
const CATALOG_TTL_MS = 5 * 60 * 1000;
let cachedCatalog: ExtensionItem[] | null = null;
let cachedCatalogAt = 0;

// Download counts are published nightly to extension-stats.json by the
// update-stats.yml workflow (Obsidian model). Serve from cache to avoid
// hammering raw.githubusercontent.com.
const STATS_TTL_MS = 60 * 60 * 1000;
let cachedStats: Record<string, number> | null = null;
let cachedStatsAt = 0;

async function loadStats(): Promise<Record<string, number>> {
  const now = Date.now();
  if (cachedStats && now - cachedStatsAt < STATS_TTL_MS) {
    return cachedStats;
  }
  try {
    const res = await fetch(STATS_URL, { next: { revalidate: 3600 } });
    if (!res.ok) return cachedStats ?? {};
    const data = (await res.json()) as { downloads?: Record<string, number> };
    cachedStats = data.downloads ?? {};
    cachedStatsAt = Date.now();
    return cachedStats;
  } catch {
    return cachedStats ?? {};
  }
}

async function loadCatalog(): Promise<ExtensionItem[]> {
  // Serve from cache unless it has expired.
  const now = Date.now();
  if (cachedCatalog && now - cachedCatalogAt < CATALOG_TTL_MS) {
    return cachedCatalog;
  }

  try {
    const res = await fetch(CATALOG_URL, { next: { revalidate: 300 } });
    if (!res.ok) {
      console.warn('Catalog fetch failed:', res.status);
      return cachedCatalog ?? [];
    }

    const data = (await res.json()) as {
      extensions?: Omit<ExtensionItem, 'downloadCount'>[];
    };

    // Merge GitHub Release download counts published nightly to extension-stats.json.
    const stats = await loadStats();

    cachedCatalog = (data.extensions ?? []).map((item) => ({
      ...item,
      downloadCount: stats[item.id] ?? 0,
    }));
    cachedCatalogAt = Date.now();
    return cachedCatalog;
  } catch (err) {
    console.error('Failed to load catalog:', err);
    return cachedCatalog ?? [];
  }
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = (searchParams.get('q') || '').toLowerCase().trim();
  const category = (searchParams.get('category') || 'all').toLowerCase().trim();
  const page = parseInt(searchParams.get('page') || '1', 10);
  const limit = parseInt(searchParams.get('limit') || '12', 10);

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
