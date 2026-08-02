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
const RAW_BASE = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/Extensions`;
const API_TREE_URL = `https://api.github.com/repos/${REPO}/git/trees/${BRANCH}?recursive=1`;

// Cache the verified catalog so repeated searches don't hammer GitHub.
// Keyed by repo/branch; entries expire after a short TTL.
const CACHE_TTL_MS = 60_000;
let cachedCatalog: ExtensionItem[] | null = null;
let cachedAt = 0;

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
    const res = await fetch(
      `https://raw.githubusercontent.com/${REPO}/${BRANCH}/extension-stats.json`,
      { next: { revalidate: 3600 } }
    );
    if (!res.ok) return cachedStats ?? {};
    const data = (await res.json()) as { downloads?: Record<string, number> };
    cachedStats = data.downloads ?? {};
    cachedStatsAt = Date.now();
    return cachedStats;
  } catch {
    return cachedStats ?? {};
  }
}

async function headExists(url: string): Promise<boolean> {
  try {
    const res = await fetch(url, { method: 'HEAD', next: { revalidate: 60 } });
    return res.ok;
  } catch {
    return false;
  }
}

async function loadExtensionsFromGitHub(): Promise<ExtensionItem[]> {
  // Serve from cache unless it has expired.
  const now = Date.now();
  if (cachedCatalog && now - cachedAt < CACHE_TTL_MS) {
    return cachedCatalog;
  }

  try {
    const treeRes = await fetch(API_TREE_URL, {
      headers: {
        Accept: 'application/vnd.github.v3+json',
        'User-Agent': 'OpenClip-Website',
      },
      next: { revalidate: 60 },
    });

    if (!treeRes.ok) {
      console.warn('GitHub tree fetch failed:', treeRes.status);
      return cachedCatalog ?? [];
    }

    const tree: { tree: { path: string; type: string }[] } = await treeRes.json();

    // Find all openclip.json manifest paths inside .openclipext directories
    const manifests = tree.tree.filter(
      (node) =>
        node.type === 'blob' &&
        node.path.startsWith('Extensions/') &&
        node.path.endsWith('/openclip.json') &&
        node.path.includes('.openclipext/')
    );

    const results = await Promise.allSettled(
      manifests.map(async (node) => {
        const rawURL = `https://raw.githubusercontent.com/${REPO}/${BRANCH}/${node.path}`;
        const res = await fetch(rawURL, { next: { revalidate: 60 } });
        if (!res.ok) return null;

        const data = await res.json();
        const action = data.action || data.actions?.[0] || {};
        // Manifest paths look like "Extensions/raw/AppleMusic.openclipext/openclip.json".
        // The published zip lives next to the raw dir at "Extensions/AppleMusic.openclipext.zip".
        const pathParts = node.path.split('/');
        const pkgDir = pathParts.find((part) => part.endsWith('.openclipext')) ?? pathParts[1];

        // The zip filename is the .openclipext folder name + .zip. Verify it actually
        // exists before exposing it, so the API never returns a 404 download URL.
        const downloadURL = `${RAW_BASE}/${pkgDir}.zip`;
        if (!(await headExists(downloadURL))) {
          console.warn(`Extension zip not found, skipping: ${downloadURL}`);
          return null;
        }

        return {
          id:
            data.identifier ||
            data.id ||
            `com.openclip.${pkgDir.replace('.openclipext', '').toLowerCase()}`,
          name: data.name || action.title || pkgDir.replace('.openclipext', ''),
          description:
            data.description ||
            action.description ||
            (action.url
              ? `Opens ${action.url.split('/')[2]} for your selected text.`
              : 'A native OpenClip extension.'),
          author: data.author || 'OpenClip Team',
          icon: action.icon || data.icon || 'puzzlepiece',
          category: data.category || 'productivity',
          downloadCount: 0,
          downloadURL,
        } as ExtensionItem;
      })
    );

    const nextCatalog = results
      .filter(
        (r): r is PromiseFulfilledResult<ExtensionItem> =>
          r.status === 'fulfilled' && r.value !== null
      )
      .map((r) => r.value);

    // Merge GitHub Release download counts published nightly to extension-stats.json.
    const stats = await loadStats();

    cachedCatalog = nextCatalog.map((item) => ({
      ...item,
      downloadCount: stats[item.id] ?? 0,
    }));
    cachedAt = Date.now();
    return cachedCatalog;
  } catch (err) {
    console.error('Failed to load extensions from GitHub:', err);
    return cachedCatalog ?? [];
  }
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = (searchParams.get('q') || '').toLowerCase().trim();
  const category = (searchParams.get('category') || 'all').toLowerCase().trim();
  const page = parseInt(searchParams.get('page') || '1', 10);
  const limit = parseInt(searchParams.get('limit') || '12', 10);

  let filtered = await loadExtensionsFromGitHub();

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
