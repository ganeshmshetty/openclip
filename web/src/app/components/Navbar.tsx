'use client';

import Link from 'next/link';
import { Layers, Code, GitBranch, Download } from 'lucide-react';

export default function Navbar() {
  return (
    <header className="sticky top-0 z-50 bg-neutral-900/90 backdrop-blur-md border-b border-neutral-800">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5 font-semibold text-lg text-neutral-100 tracking-tight">
          <div className="w-7 h-7 rounded-md bg-neutral-100 text-neutral-950 flex items-center justify-center font-bold text-sm">
            O
          </div>
          <span>OpenClip</span>
        </Link>

        <nav className="hidden md:flex items-center gap-7 text-sm font-medium text-neutral-400">
          <Link href="/" className="hover:text-neutral-100 transition-colors">
            Home
          </Link>
          <Link href="/extensions" className="flex items-center gap-1.5 hover:text-neutral-100 transition-colors">
            <Layers className="w-4 h-4 text-neutral-400" />
            Extensions
          </Link>
          <Link href="/developers" className="flex items-center gap-1.5 hover:text-neutral-100 transition-colors">
            <Code className="w-4 h-4 text-neutral-400" />
            Developers
          </Link>
          <a
            href="https://github.com/openclip-app/openclip"
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-1.5 hover:text-neutral-100 transition-colors"
          >
            <GitBranch className="w-4 h-4 text-neutral-400" />
            GitHub
          </a>
        </nav>

        <div className="flex items-center gap-3">
          <a
            href="https://github.com/openclip-app/openclip/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-md bg-neutral-100 text-neutral-950 hover:bg-neutral-200 font-medium text-xs tracking-wide transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Download App</span>
          </a>
        </div>
      </div>
    </header>
  );
}
