'use client';

import Link from 'next/link';
import { Sparkles, Download, Layers, Code, GitBranch } from 'lucide-react';

export default function Navbar() {
  return (
    <header className="sticky top-0 z-50 bg-slate-900/90 backdrop-blur-md border-b border-blue-900/40">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5 font-bold text-lg text-white tracking-tight group">
          <div className="w-8 h-8 rounded-xl bg-blue-600 text-white flex items-center justify-center font-extrabold text-sm shadow-md shadow-blue-500/30 group-hover:rotate-6 transition-transform">
            ⚡
          </div>
          <span className="bg-gradient-to-r from-blue-400 to-sky-300 bg-clip-text text-transparent">
            OpenClip
          </span>
        </Link>

        <nav className="hidden md:flex items-center gap-7 text-sm font-semibold text-slate-300">
          <Link href="/" className="hover:text-blue-400 transition-colors">
            Home
          </Link>
          <Link href="/extensions" className="flex items-center gap-1.5 hover:text-blue-400 transition-colors">
            <Layers className="w-4 h-4 text-blue-400" />
            Extensions
          </Link>
          <Link href="/developers" className="flex items-center gap-1.5 hover:text-blue-400 transition-colors">
            <Code className="w-4 h-4 text-sky-400" />
            Developers
          </Link>
          <a
            href="https://github.com/openclip-app/openclip"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 hover:text-blue-400 transition-colors"
          >
            <GitBranch className="w-4 h-4 text-slate-400" />
            GitHub
          </a>
        </nav>

        <div className="flex items-center gap-3">
          <a
            href="https://github.com/openclip-app/openclip/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs tracking-wide shadow-lg shadow-blue-600/30 transition-all hover:scale-105 active:scale-95"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Download for Mac</span>
          </a>
        </div>
      </div>
    </header>
  );
}
