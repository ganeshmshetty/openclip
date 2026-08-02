'use client';

import { useState, useEffect, useCallback } from 'react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { Search, Download, Check, PackageOpen, ExternalLink } from 'lucide-react';

interface ExtensionItem {
  id: string;
  name: string;
  description: string;
  author: string;
  icon: string;
  category: string;
  version: string;
  downloadCount: number;
  downloadURL: string;
}

const CATEGORIES = ['all', 'search', 'writing', 'productivity', 'developer', 'utilities'];

function CategoryBadge({ category }: { category: string }) {
  return (
    <span className="inline-block px-2 py-0.5 rounded-full border-[1.5px] border-ink bg-tint text-ink font-mono text-[10.5px] uppercase tracking-wide">
      {category}
    </span>
  );
}

export default function ExtensionsPage() {
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [extensions, setExtensions] = useState<ExtensionItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [installedMap, setInstalledMap] = useState<Record<string, boolean>>({});

  const fetchExtensions = useCallback(async () => {
    setIsLoading(true);
    try {
      const params = new URLSearchParams({ q: search, category: selectedCategory, limit: '20' });
      const res = await fetch(`/api/v1/extensions?${params}`);
      if (res.ok) {
        const data = await res.json();
        setExtensions(data.extensions || []);
      }
    } catch (e) {
      console.error(e);
    } finally {
      setIsLoading(false);
    }
  }, [search, selectedCategory]);

  useEffect(() => {
    const t = setTimeout(fetchExtensions, 250);
    return () => clearTimeout(t);
  }, [fetchExtensions]);

  const handleInstall = (ext: ExtensionItem) => {
    const url = `openclip://install?id=${encodeURIComponent(ext.id)}&name=${encodeURIComponent(ext.name)}&url=${encodeURIComponent(ext.downloadURL)}`;
    window.location.href = url;
    setInstalledMap((prev) => ({ ...prev, [ext.id]: true }));
    setTimeout(() => {
      setInstalledMap((prev) => ({ ...prev, [ext.id]: false }));
    }, 3000);
  };

  return (
    <div className="min-h-screen text-ink flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-6xl mx-auto px-5 sm:px-8 py-16 w-full">
        {/* Page header */}
        <div className="mb-10">
          <p className="eyebrow mb-2">Extension Store</p>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-[-0.02em] text-ink">
            One-click superpowers.
          </h1>
          <p className="mt-1.5 text-[13.5px] text-ink/55 max-w-lg">
            Auto-synced from GitHub. Every{' '}
            <code className="font-mono text-[12px] bg-tint border border-ink/20 rounded px-1.5 py-0.5">.openclipext</code>{' '}
            folder in the repo appears here automatically.
          </p>
        </div>

        {/* Toolbar */}
        <div className="mb-8 flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-ink/30 pointer-events-none" />
            <input
              type="text"
              placeholder="Search extensions..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2.5 rounded-[10px] bg-card border-[1.5px] border-ink text-ink text-[13.5px] placeholder-ink/30 shadow-chunky-sm focus:outline-none focus:shadow-chunky transition-shadow"
            />
          </div>

          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5 sm:pb-0">
            {CATEGORIES.map((cat) => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3.5 py-2 rounded-[10px] border-[1.5px] border-ink text-[12.5px] font-medium capitalize whitespace-nowrap transition-all ${
                  selectedCategory === cat
                    ? 'bg-accent text-white shadow-chunky-sm'
                    : 'bg-card text-ink/60 hover:bg-tint'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {/* Grid */}
        {isLoading ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {[1, 2, 3, 4, 5, 6].map((i) => (
              <div key={i} className="h-44 card-chunky bg-tint animate-pulse" />
            ))}
          </div>
        ) : extensions.length === 0 ? (
          <div className="card-chunky flex flex-col items-center justify-center py-24 text-center">
            <div className="w-14 h-14 rounded-[12px] bg-tint border-[1.5px] border-ink flex items-center justify-center mb-4">
              <PackageOpen className="w-6 h-6 text-accent-deep" />
            </div>
            <h3 className="text-[15px] font-semibold text-ink">No extensions found</h3>
            <p className="text-[13px] text-ink/50 mt-1">
              {search ? 'Try a different search query.' : 'No extensions published yet.'}
            </p>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {extensions.map((ext) => {
              const triggered = installedMap[ext.id];
              return (
                <div
                  key={ext.id}
                  className="card-chunky flex flex-col justify-between p-5 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-chunky-lg transition-all"
                >
                  <div>
                    <div className="flex items-start justify-between gap-3 mb-3">
                      <div>
                        <h3 className="text-[14px] font-semibold text-ink leading-snug">
                          {ext.name}
                        </h3>
                        <p className="text-[11.5px] text-ink/45 mt-0.5">by {ext.author}</p>
                      </div>
                      <CategoryBadge category={ext.category} />
                    </div>

                    <p className="text-[12.5px] text-ink/60 leading-relaxed line-clamp-2">
                      {ext.description}
                    </p>
                  </div>

                  <div className="flex items-center justify-between mt-5 pt-4 border-t-[1.5px] border-ink/10">
                    <div className="flex items-center gap-2">
                      <span className="font-mono text-[11px] text-ink/45 tabular-nums">
                        ↓ {ext.downloadCount.toLocaleString()}
                      </span>
                      <span className="font-mono text-[10px] px-1.5 py-0.5 rounded bg-tint border border-ink/20 text-ink/60 tabular-nums">
                        v{ext.version}
                      </span>
                    </div>

                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={() => handleInstall(ext)}
                        className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-[8px] border-[1.5px] border-ink text-[12.5px] font-semibold transition-all ${
                          triggered
                            ? 'bg-tint text-ink shadow-chunky-sm'
                            : 'btn-chunky shadow-chunky-sm'
                        }`}
                      >
                        {triggered ? (
                          <>
                            <Check className="w-3.5 h-3.5" />
                            Opening…
                          </>
                        ) : (
                          'Install'
                        )}
                      </button>

                      <a
                        href={ext.downloadURL}
                        target="_blank"
                        rel="noopener noreferrer"
                        title="View on GitHub"
                        className="p-1.5 rounded-[8px] bg-card border-[1.5px] border-ink text-ink/40 hover:text-ink hover:bg-tint transition-all"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </a>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </main>

      <Footer />
    </div>
  );
}
