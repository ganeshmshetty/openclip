import { NextResponse } from 'next/server';
import fs from 'fs';
import path from 'path';

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

// Automatically scans the Extensions/ directory on disk/repo to parse openclip.json manifests dynamically!
function loadExtensionsFromDirectory(): ExtensionItem[] {
  const items: ExtensionItem[] = [];
  const extensionsDir = path.join(process.cwd(), '..', 'Extensions');

  if (!fs.existsSync(extensionsDir)) {
    return items;
  }

  try {
    const entries = fs.readdirSync(extensionsDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isDirectory() && entry.name.endsWith('.openclipext')) {
        const manifestPath = path.join(extensionsDir, entry.name, 'openclip.json');
        if (fs.existsSync(manifestPath)) {
          try {
            const raw = fs.readFileSync(manifestPath, 'utf8');
            const data = JSON.parse(raw);
            const action = data.action || data.actions?.[0] || {};
            
            items.push({
              id: data.identifier || data.id || `com.openclip.${entry.name.replace('.openclipext', '').toLowerCase()}`,
              name: data.name || action.title || entry.name.replace('.openclipext', ''),
              description: data.description || action.description || `Native ${action.script ? 'script' : 'url'} extension for OpenClip.`,
              author: data.author || 'Community',
              icon: action.icon || 'puzzlepiece',
              category: data.category || 'productivity',
              downloadCount: 0,
              downloadURL: `https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/${entry.name}/openclip.json`
            });
          } catch (e) {
            console.error(`Failed to parse manifest at ${manifestPath}`, e);
          }
        }
      }
    }
  } catch (err) {
    console.error('Error reading Extensions directory:', err);
  }

  return items;
}

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = (searchParams.get('q') || '').toLowerCase().trim();
  const category = (searchParams.get('category') || 'all').toLowerCase().trim();
  const page = parseInt(searchParams.get('page') || '1', 10);
  const limit = parseInt(searchParams.get('limit') || '12', 10);

  // Dynamically loaded from Extensions/ directory
  let filtered = loadExtensionsFromDirectory();

  // Fallback if running standalone web build without parent repo dir
  if (filtered.length === 0) {
    filtered = [
      {
        id: "com.openclip.youtube",
        name: "Search YouTube",
        description: "Search YouTube instantly for your highlighted text in your browser.",
        author: "OpenClip Team",
        icon: "play.circle",
        category: "productivity",
        downloadCount: 0,
        downloadURL: "https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/SearchYouTube.openclipext/openclip.json"
      },
      {
        id: "com.openclip.applemusic",
        name: "Search Apple Music",
        description: "Search and play tracks directly in Apple Music using native AppleScript integration.",
        author: "OpenClip Team",
        icon: "music.note",
        category: "productivity",
        downloadCount: 0,
        downloadURL: "https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/AppleMusic.openclipext/openclip.json"
      }
    ];
  }

  if (category !== 'all') {
    filtered = filtered.filter(ext => ext.category.toLowerCase() === category);
  }

  if (q) {
    filtered = filtered.filter(
      ext =>
        ext.name.toLowerCase().includes(q) ||
        ext.description.toLowerCase().includes(q) ||
        ext.author.toLowerCase().includes(q)
    );
  }

  const totalCount = filtered.length;
  const totalPages = Math.ceil(totalCount / limit) || 1;
  const startIndex = (page - 1) * limit;
  const paginatedExtensions = filtered.slice(startIndex, startIndex + limit);

  const response: ExtensionsPageResponse = {
    extensions: paginatedExtensions,
    page,
    totalPages,
    totalCount
  };

  return NextResponse.json(response, {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'public, s-maxage=10, stale-while-revalidate=30'
    }
  });
}
