'use client';

import { useState, useEffect } from 'react';
import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { Search, Download, Check, Layers, Sparkles } from 'lucide-react';

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
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <Navbar />

      <main className="flex-1 max-w-6xl mx-auto px-4 sm:px-6 py-10 w-full">
        {/* Header */}
        <div className="mb-8">
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-blue-500/10 border border-blue-500/30 text-blue-400 text-xs font-bold uppercase tracking-wider mb-2">
            <Sparkles className="w-3.5 h-3.5" />
            <span>Extension Hub</span>
          </div>
          <h1 className="text-3xl font-extrabold text-white tracking-tight">
            Extension Store
          </h1>
          <p className="mt-1 text-slate-400 text-xs sm:text-sm font-medium">
            Click <strong>Install in OpenClip</strong> to add extensions directly to your Mac.
          </p>
        </div>

        {/* Search & Category Filter Bar */}
        <div className="mb-8 flex flex-col md:flex-row items-center gap-3">
          <div className="relative w-full">
            <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-blue-400" />
            <input
              type="text"
              placeholder="Search extensions..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="w-full pl-10 pr-4 py-2.5 rounded-xl bg-slate-900 border border-blue-900/50 text-white placeholder-slate-500 focus:outline-none focus:border-blue-500 transition-colors text-xs font-medium"
            />
          </div>

          <div className="flex items-center gap-1.5 overflow-x-auto w-full md:w-auto">
            {categories.map(cat => (
              <button
                key={cat}
                onClick={() => setSelectedCategory(cat)}
                className={`px-3.5 py-2 rounded-xl text-xs font-bold capitalize whitespace-nowrap transition-all ${
                  selectedCategory === cat
                    ? 'bg-blue-600 text-white shadow-md shadow-blue-500/30'
                    : 'bg-slate-900 hover:bg-slate-800 text-slate-400 border border-blue-900/40'
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
              <div key={i} className="h-40 rounded-2xl bg-slate-900/40 border border-blue-900/30 animate-pulse" />
            ))}
          </div>
        ) : extensions.length === 0 ? (
          <div className="text-center py-16 bg-slate-900/40 rounded-2xl border border-blue-900/40">
            <Layers className="w-8 h-8 text-blue-500 mx-auto mb-2" />
            <h3 className="text-base font-bold text-white">No extensions published yet</h3>
            <p className="text-xs text-slate-400 mt-1 font-medium">Be the first to create and submit an extension!</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {extensions.map(ext => {
              const isTriggered = installedMap[ext.id];
              return (
                <div
                  key={ext.id}
                  className="flex flex-col justify-between p-5 rounded-2xl bg-slate-900/60 border border-blue-900/40 hover:border-blue-500/50 transition-all hover:-translate-y-0.5 shadow-lg shadow-black/20"
                >
                  <div>
                    <div className="flex items-start justify-between gap-2 mb-2">
                      <div>
                        <h3 className="font-bold text-white text-sm leading-snug">{ext.name}</h3>
                        <p className="text-[11px] text-slate-400 font-medium">by {ext.author}</p>
                      </div>
                      <span className="px-2.5 py-0.5 rounded-full bg-blue-500/10 border border-blue-500/30 text-blue-400 text-[10px] uppercase font-bold">
                        {ext.category}
                      </span>
                    </div>

                    <p className="text-xs text-slate-300 leading-relaxed mb-4 line-clamp-2 font-medium">
                      {ext.description}
                    </p>
                  </div>

                  <div className="pt-3 border-t border-blue-900/40 flex items-center justify-between gap-2 text-xs">
                    <span className="text-slate-400 text-[11px] font-semibold">
                      ⬇ {ext.downloadCount.toLocaleString()}
                    </span>

                    <div className="flex items-center gap-1.5">
                      <button
                        onClick={() => handleOneClickInstall(ext)}
                        className={`inline-flex items-center gap-1 px-3.5 py-1.5 rounded-xl text-xs font-bold transition-all ${
                          isTriggered
                            ? 'bg-emerald-600 text-white'
                            : 'bg-blue-600 hover:bg-blue-500 text-white shadow-md shadow-blue-500/25'
                        }`}
                      >
                        {isTriggered ? (
                          <>
                            <Check className="w-3.5 h-3.5" />
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
                        className="p-1.5 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors"
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
