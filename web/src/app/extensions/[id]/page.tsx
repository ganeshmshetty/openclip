'use client';

import { use, useState, useEffect } from 'react';
import Link from 'next/link';
import Navbar from '../../components/Navbar';
import Footer from '../../components/Footer';
import { Package, Download, ArrowLeft, Check, User } from 'lucide-react';

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
    <div className="min-h-screen text-ink flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-4xl mx-auto px-5 sm:px-8 py-16 w-full">
        <Link
          href="/extensions"
          className="inline-flex items-center gap-2 font-mono text-[12px] uppercase tracking-widest text-ink/50 hover:text-accent-deep transition-colors mb-8"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>All Extensions</span>
        </Link>

        {isLoading ? (
          <div className="h-64 card-chunky bg-tint animate-pulse" />
        ) : !extension ? (
          <div className="card-chunky text-center py-20">
            <h2 className="text-xl font-bold text-ink">Extension not found</h2>
            <p className="text-sm text-ink/50 mt-2">The requested extension could not be located.</p>
          </div>
        ) : (
          <div className="space-y-8">
            {/* Header Card */}
            <div className="card-chunky p-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
              <div className="flex items-center gap-5">
                <div className="w-16 h-16 rounded-[12px] bg-tint border-[1.5px] border-ink flex items-center justify-center text-accent-deep">
                  <Package className="w-7 h-7" />
                </div>
                <div>
                  <h1 className="text-2xl sm:text-3xl font-extrabold tracking-[-0.02em] text-ink">
                    {extension.name}
                  </h1>
                  <div className="flex items-center gap-3 mt-1.5">
                    <span className="flex items-center gap-1 text-[13px] text-ink/55">
                      <User className="w-3.5 h-3.5 text-ink/40" />
                      {extension.author}
                    </span>
                    <span className="chip">{extension.category}</span>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-3 w-full sm:w-auto">
                <button
                  onClick={handleInstall}
                  className={`flex-1 sm:flex-none px-6 py-3 text-sm ${
                    installed
                      ? 'inline-flex items-center justify-center gap-2 rounded-[10px] border-[1.5px] border-ink bg-tint text-ink font-semibold shadow-chunky-sm'
                      : 'btn-chunky'
                  }`}
                >
                  {installed ? (
                    <>
                      <Check className="w-4 h-4" />
                      <span>Opening OpenClip...</span>
                    </>
                  ) : (
                    <span>Install in OpenClip</span>
                  )}
                </button>

                <a
                  href={extension.downloadURL}
                  download
                  title="Download raw package file"
                  className="btn-chunky-outline p-3"
                >
                  <Download className="w-4 h-4" />
                </a>
              </div>
            </div>

            {/* Description & metadata */}
            <div className="card-chunky p-8">
              <h2 className="eyebrow text-ink mb-3">Description</h2>
              <p className="text-ink/75 leading-relaxed text-[15px]">
                {extension.description}
              </p>

              <div className="mt-6 pt-6 border-t-[1.5px] border-ink/10 grid grid-cols-2 gap-6">
                <div>
                  <span className="eyebrow block mb-1">Downloads</span>
                  <span className="font-semibold text-ink inline-flex items-center gap-1.5">
                    <Download className="w-3.5 h-3.5 text-ink/40" />
                    {extension.downloadCount.toLocaleString()}
                  </span>
                </div>

                <div>
                  <span className="eyebrow block mb-1">Version</span>
                  <span className="font-semibold text-ink">v{extension.version}</span>
                </div>

                <div>
                  <span className="eyebrow block mb-1">Format</span>
                  <span className="font-semibold text-ink">OpenClip Extension (.openclipext)</span>
                </div>

                <div>
                  <span className="eyebrow block mb-1">Compatibility</span>
                  <span className="font-semibold text-ink">macOS 12.0+</span>
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
