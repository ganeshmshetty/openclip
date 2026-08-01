'use client';

import { useState, useEffect } from 'react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { Search, Download, Check, Layers } from 'lucide-react';

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

export default function ExtensionsPage() {
  const [search, setSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');
  const [extensions, setExtensions] = useState<ExtensionItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [installedMap, setInstalledMap] = useState<Record<string, boolean>>({});

  const categories = ['all', 'productivity', 'developer', 'utilities', 'text tools'];

  useEffect(() => {
    async function fetchExtensions() {
      setIsLoading(true);
      try {
        const queryParams = new URLSearchParams({
          q: search,
          category: selectedCategory,
          limit: '20'
        });
        const res = await fetch(`/api/v1/extensions?${queryParams.toString()}`);
        if (res.ok) {
          const data = await res.json();
          setExtensions(data.extensions || []);
        }
      } catch (err) {
        console.error('Failed to fetch extensions:', err);
      } finally {
        setIsLoading(false);
      }
    }

    const timer = setTimeout(fetchExtensions, 200);
    return () => clearTimeout(timer);
  }, [search, selectedCategory]);

  const handleOneClickInstall = (ext: ExtensionItem) => {
    const installURL = `openclip://install?id=${encodeURIComponent(ext.id)}&name=${encodeURIComponent(ext.name)}&url=${encodeURIComponent(ext.downloadURL)}`;
    window.location.href = installURL;
    setInstalledMap(prev => ({ ...prev, [ext.id]: true }));
  };

  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100 flex flex-col font-sans">
      <Navbar />

      <main className="flex-1 max-w-6xl mx-auto px-4 sm:px-6 py-10 w-full">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-2xl sm:text-3xl font-bold text-neutral-100 tracking-tight">
            Extensions Directory
          </h1>
          <p className="mt-1 text-neutral-400 text-xs sm:text-sm">
            Click <strong>Install in OpenClip</strong> to add any extension directly to your Mac.
          </p>
        </div>

        {/* Search & Category Filter Bar */}
        <div className="mb-8 flex flex-col md:flex-row items-center gap-3">
          <div className="relative w-full">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-neutral-500" />
            <input
              type="text"
              placeholder="Search extensions..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="w-full pl-9 pr-4 py-2 rounded-md bg-neutral-900 border border-neutral-800 text-neutral-100 placeholder-neutral-500 focus:outline-none focus:border-neutral-600 transition-colors text-xs"
            />
          </div>

          <div className="flex items-center gap-1.5 overflow-x-auto w-full md:w-auto">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3 py-1.5 rounded-md text-xs font-medium capitalize whitespace-nowrap transition-colors ${
                  selectedCategory === cat
                    ? 'bg-neutral-100 text-neutral-950 font-semibold'
                    : 'bg-neutral-900 hover:bg-neutral-800 text-neutral-400 border border-neutral-800'
                }`}
              >
                {cat}
              </button>
            ))}
          </div>
        </div>

        {/* Extensions Grid */}
        {isLoading ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {[1, 2, 3].map(i => (
              <div key={i} className="h-40 rounded-md bg-neutral-900/40 border border-neutral-800 animate-pulse" />
            ))}
          </div>
        ) : extensions.length === 0 ? (
          <div className="text-center py-16 bg-neutral-900/30 rounded-md border border-neutral-800">
            <Layers className="w-8 h-8 text-neutral-600 mx-auto mb-2" />
            <h3 className="text-sm font-semibold text-neutral-200">No extensions found</h3>
            <p className="text-xs text-neutral-500 mt-1">Try adjusting your search query.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {extensions.map(ext => {
              const isTriggered = installedMap[ext.id];
              return (
                <div
                  key={ext.id}
                  className="flex flex-col justify-between p-5 rounded-md bg-neutral-900/50 border border-neutral-800 hover:border-neutral-700 transition-colors"
                >
                  <div>
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <div>
                        <h3 className="font-semibold text-neutral-100 text-sm leading-snug">{ext.name}</h3>
                        <p className="text-[11px] text-neutral-500">by {ext.author}</p>
                      </div>
                      <span className="px-2 py-0.5 rounded bg-neutral-800 text-neutral-400 text-[10px] uppercase font-medium">
                        {ext.category}
                      </span>
                    </div>

                    <p className="text-xs text-neutral-400 leading-relaxed mb-4 line-clamp-2">
                      {ext.description}
                    </p>
                  </div>

                  <div className="pt-3 border-t border-neutral-800/80 flex items-center justify-between gap-2 text-xs">
                    <span className="text-neutral-500 text-[11px]">
                      ⬇ {ext.downloadCount.toLocaleString()}
                    </span>

                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={() => handleOneClickInstall(ext)}
                        className={`inline-flex items-center gap-1 px-3 py-1.5 rounded text-xs font-medium transition-colors ${
                          isTriggered
                            ? 'bg-emerald-700 text-white'
                            : 'bg-neutral-100 hover:bg-neutral-200 text-neutral-950'
                        }`}
                      >
                        {isTriggered ? (
                          <>
                            <Check className="w-3 h-3" />
                            <span>Opening...</span>
                          </>
                        ) : (
                          <span>Install in OpenClip</span>
                        )}
                      </button>

                      <a
                        href={ext.downloadURL}
                        download
                        title="Download package file"
                        className="p-1.5 rounded bg-neutral-800 hover:bg-neutral-700 text-neutral-400 hover:text-neutral-200 transition-colors"
                      >
                        <Download className="w-3.5 h-3.5" />
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
