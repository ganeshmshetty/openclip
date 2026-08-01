'use client';

import { use, useState, useEffect } from 'react';
import Link from 'next/link';
import Navbar from '../../components/Navbar';
import Footer from '../../components/Footer';
import { Sparkles, Download, ArrowLeft, Check, Terminal, User, Calendar, Layers } from 'lucide-react';

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

export default function ExtensionDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const resolvedParams = use(params);
  const [extension, setExtension] = useState<ExtensionItem | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [installed, setInstalled] = useState(false);

  useEffect(() => {
    async function loadExtension() {
      try {
        const res = await fetch(`/api/v1/extensions`);
        if (res.ok) {
          const data = await res.json();
          const found = (data.extensions || []).find((e: ExtensionItem) => e.id === resolvedParams.id);
          setExtension(found || null);
        }
      } catch (err) {
        console.error(err);
      } finally {
        setIsLoading(false);
      }
    }
    loadExtension();
  }, [resolvedParams.id]);

  const handleInstall = () => {
    if (!extension) return;
    const installURL = `openclip://install?id=${encodeURIComponent(extension.id)}&name=${encodeURIComponent(extension.name)}&url=${encodeURIComponent(extension.downloadURL)}`;
    window.location.href = installURL;
    setInstalled(true);
  };

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <Navbar />

      <main className="flex-1 max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12 w-full">
        <Link
          href="/extensions"
          className="inline-flex items-center gap-2 text-sm text-slate-400 hover:text-white transition-colors mb-8"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Extensions</span>
        </Link>

        {isLoading ? (
          <div className="h-64 rounded-2xl bg-slate-900/50 border border-slate-800 animate-pulse" />
        ) : !extension ? (
          <div className="text-center py-20 bg-slate-900/40 rounded-2xl border border-slate-800">
            <h2 className="text-xl font-bold text-white">Extension not found</h2>
            <p className="text-sm text-slate-400 mt-2">The requested extension could not be located.</p>
          </div>
        ) : (
          <div className="space-y-8">
            {/* Header Card */}
            <div className="p-8 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-xl flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
              <div className="flex items-center gap-5">
                <div className="w-16 h-16 rounded-2xl bg-purple-500/10 border border-purple-500/20 flex items-center justify-center text-purple-400 text-3xl font-bold">
                  ✨
                </div>
                <div>
                  <h1 className="text-2xl sm:text-3xl font-bold text-white">{extension.name}</h1>
                  <div className="flex items-center gap-3 text-sm text-slate-400 mt-1">
                    <span className="flex items-center gap-1">
                      <User className="w-3.5 h-3.5 text-slate-500" />
                      {extension.author}
                    </span>
                    <span>•</span>
                    <span className="capitalize px-2 py-0.5 rounded bg-slate-800 text-slate-300 text-xs font-medium">
                      {extension.category}
                    </span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-3 w-full sm:w-auto">
                <button
                  onClick={handleInstall}
                  className={`flex-1 sm:flex-none inline-flex items-center justify-center gap-2 px-6 py-3 rounded-xl text-sm font-semibold transition-all ${
                    installed
                      ? 'bg-emerald-600 text-white'
                      : 'bg-gradient-to-r from-purple-600 to-indigo-600 hover:from-purple-500 hover:to-indigo-500 text-white shadow-lg shadow-purple-500/25'
                  }`}
                >
                  {installed ? (
                    <>
                      <Check className="w-4 h-4" />
                      <span>Opening OpenClip...</span>
                    </>
                  ) : (
                    <>
                      <Sparkles className="w-4 h-4" />
                      <span>Install in OpenClip</span>
                    </>
                  )}
                </button>

                <a
                  href={extension.downloadURL}
                  download
                  title="Download raw package file"
                  className="p-3 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors"
                >
                  <Download className="w-4 h-4" />
                </a>
              </div>
            </div>

            {/* Description & Overview Section */}
            <div className="p-8 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-xl space-y-6">
              <div>
                <h2 className="text-lg font-bold text-white mb-2">Description</h2>
                <p className="text-slate-300 leading-relaxed text-base">
                  {extension.description}
                </p>
              </div>

              <div className="pt-6 border-t border-slate-800/60 grid grid-cols-2 sm:grid-cols-3 gap-6 text-sm">
                <div>
                  <span className="text-xs text-slate-500 uppercase font-semibold block mb-1">Downloads</span>
                  <span className="font-semibold text-white">⬇ {extension.downloadCount.toLocaleString()}</span>
                </div>

                <div>
                  <span className="text-xs text-slate-500 uppercase font-semibold block mb-1">Format</span>
                  <span className="font-semibold text-white">OpenClip Extension (.openclipext)</span>
                </div>

                <div>
                  <span className="text-xs text-slate-500 uppercase font-semibold block mb-1">Compatibility</span>
                  <span className="font-semibold text-white">macOS 12.0+</span>
                </div>
              </div>
            </div>
          </div>
        )}
      </main>

      <Footer />
    </div>
  );
}
