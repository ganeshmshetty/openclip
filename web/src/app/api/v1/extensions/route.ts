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

async function loadExtensionsFromGitHub(): Promise<ExtensionItem[]> {
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
      return [];
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
        const dirName = node.path.split('/')[1]; // e.g. SearchYouTube.openclipext

        return {
          id:
            data.identifier ||
            data.id ||
            `com.openclip.${dirName.replace('.openclipext', '').toLowerCase()}`,
          name: data.name || action.title || dirName.replace('.openclipext', ''),
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
          downloadURL: `${RAW_BASE}/${dirName}.zip`,
        } as ExtensionItem;
      })
    );

    return results
      .filter(
        (r): r is PromiseFulfilledResult<ExtensionItem> =>
          r.status === 'fulfilled' && r.value !== null
      )
      .map((r) => r.value);
  } catch (err) {
    console.error('Failed to load extensions from GitHub:', err);
    return [];
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
