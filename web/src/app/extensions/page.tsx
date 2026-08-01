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
  downloadCount: number;
  downloadURL: string;
}

const CATEGORIES = ['all', 'productivity', 'developer', 'utilities', 'text tools'];

function CategoryBadge({ category }: { category: string }) {
  const colors: Record<string, string> = {
    productivity: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
    developer: 'bg-violet-500/10 text-violet-400 border-violet-500/20',
    utilities: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
    'text tools': 'bg-amber-500/10 text-amber-400 border-amber-500/20',
  };
  return (
    <span
      className={`inline-block px-2 py-0.5 rounded-md border text-[10.5px] font-medium uppercase tracking-wide ${colors[category] || 'bg-white/5 text-white/40 border-white/10'}`}
    >
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
    <div className="min-h-screen bg-[#050A14] text-white flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-6xl mx-auto px-5 sm:px-8 py-12 w-full">
        {/* Page header */}
        <div className="mb-10">
          <h1 className="text-2xl font-bold tracking-[-0.02em] text-white/95">
            Extension Store
          </h1>
          <p className="mt-1.5 text-[13.5px] text-white/40 max-w-lg">
            Auto-synced from GitHub. Every{' '}
            <code className="font-mono text-white/50">.openclipext</code> folder in the repo
            appears here automatically.
          </p>
        </div>

        {/* Toolbar */}
        <div className="mb-8 flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-white/25 pointer-events-none" />
            <input
              type="text"
              placeholder="Search extensions..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-white/[0.04] border border-white/8 text-white text-[13.5px] placeholder-white/25 focus:outline-none focus:border-blue-500/50 focus:bg-white/[0.06] transition-all"
            />
          </div>

          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5 sm:pb-0">
            {CATEGORIES.map((cat) => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3.5 py-2 rounded-xl text-[12.5px] font-medium capitalize whitespace-nowrap transition-all ${
                  selectedCategory === cat
                    ? 'bg-blue-600 text-white shadow-md shadow-blue-600/20'
                    : 'bg-white/[0.04] hover:bg-white/[0.07] text-white/45 border border-white/6'
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
              <div
                key={i}
                className="h-44 rounded-2xl bg-white/[0.02] border border-white/5 animate-pulse"
              />
            ))}
          </div>
        ) : extensions.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-24 text-center">
            <div className="w-14 h-14 rounded-2xl bg-white/4 border border-white/8 flex items-center justify-center mb-4">
              <PackageOpen className="w-6 h-6 text-white/20" />
            </div>
            <h3 className="text-[15px] font-semibold text-white/60">No extensions found</h3>
            <p className="text-[13px] text-white/30 mt-1">
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
                  className="group flex flex-col justify-between p-5 rounded-2xl bg-white/[0.025] border border-white/6 hover:border-white/12 hover:bg-white/[0.04] transition-all"
                >
                  <div>
                    <div className="flex items-start justify-between gap-3 mb-3">
                      <div>
                        <h3 className="text-[14px] font-semibold text-white/90 leading-snug">
                          {ext.name}
                        </h3>
                        <p className="text-[11.5px] text-white/30 mt-0.5">by {ext.author}</p>
                      </div>
                      <CategoryBadge category={ext.category} />
                    </div>

                    <p className="text-[12.5px] text-white/45 leading-relaxed line-clamp-2">
                      {ext.description}
                    </p>
                  </div>

                  <div className="flex items-center justify-between mt-5 pt-4 border-t border-white/5">
                    <span className="text-[11px] text-white/25 tabular-nums">
                      {ext.downloadCount > 0 ? `↓ ${ext.downloadCount.toLocaleString()}` : 'New'}
                    </span>

                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={() => handleInstall(ext)}
                        className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg text-[12.5px] font-semibold transition-all ${
                          triggered
                            ? 'bg-emerald-600/80 text-white'
                            : 'bg-blue-600 hover:bg-blue-500 text-white shadow-lg shadow-blue-600/15'
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
                        className="p-1.5 rounded-lg bg-white/4 hover:bg-white/8 text-white/30 hover:text-white/60 transition-all border border-white/6"
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
