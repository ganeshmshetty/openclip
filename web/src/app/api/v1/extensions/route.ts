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

const REAL_EXTENSIONS: ExtensionItem[] = [
  {
    id: "com.openclip.youtube",
    name: "Search YouTube",
    description: "Search YouTube instantly for selected text in your browser.",
    author: "OpenClip Team",
    icon: "play.circle",
    category: "productivity",
    downloadCount: 3420,
    downloadURL: "https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/SearchAppleMusic.openclipext"
  },
  {
    id: "com.openclip.uppercase",
    name: "Uppercase Converter",
    description: "Convert selected text to UPPERCASE using high-speed JavaScript engine.",
    author: "OpenClip Team",
    icon: "textformat.size",
    category: "text tools",
    downloadCount: 2890,
    downloadURL: "https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/SearchAppleMusic.openclipext"
  },
  {
    id: "com.openclip.applemusic",
    name: "Apple Music Controller",
    description: "Search and play tracks in Apple Music via AppleScript.",
    author: "OpenClip Team",
    icon: "music.note",
    category: "productivity",
    downloadCount: 1980,
    downloadURL: "https://raw.githubusercontent.com/openclip-app/openclip/main/Extensions/AppleMusicApp.openclipext"
  }
];

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const q = (searchParams.get('q') || '').toLowerCase().trim();
  const category = (searchParams.get('category') || 'all').toLowerCase().trim();
  const page = parseInt(searchParams.get('page') || '1', 10);
  const limit = parseInt(searchParams.get('limit') || '12', 10);

  let filtered = REAL_EXTENSIONS;

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
      'Cache-Control': 'public, s-maxage=60, stale-while-revalidate=300'
    }
  });
}
