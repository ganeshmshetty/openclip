'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Download, Menu, X } from 'lucide-react';

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-white/5 bg-[#050A14]/80 backdrop-blur-xl">
      <div className="max-w-6xl mx-auto px-5 sm:px-8 h-[60px] flex items-center justify-between">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2.5 group" aria-label="OpenClip home">
          <div className="w-7 h-7 rounded-[8px] bg-blue-600 flex items-center justify-center text-white font-bold text-[13px] shadow-lg shadow-blue-600/25 group-hover:scale-105 transition-transform">
            O
          </div>
          <span className="font-semibold text-[15px] tracking-[-0.01em] text-white/90">OpenClip</span>
        </Link>

        {/* Desktop Nav */}
        <nav className="hidden md:flex items-center gap-1">
          {[
            { href: '/', label: 'Home' },
            { href: '/extensions', label: 'Extensions' },
            { href: '/developers', label: 'Developers' },
          ].map(({ href, label }) => (
            <Link
              key={href}
              href={href}
              className="px-3.5 py-1.5 rounded-lg text-[13.5px] font-medium text-white/50 hover:text-white/90 hover:bg-white/5 transition-all"
            >
              {label}
            </Link>
          ))}
          <a
            href="https://github.com/ganeshmshetty/openclip"
            target="_blank"
            rel="noopener noreferrer"
            className="px-3.5 py-1.5 rounded-lg text-[13.5px] font-medium text-white/50 hover:text-white/90 hover:bg-white/5 transition-all"
          >
            GitHub
          </a>
        </nav>

        {/* CTA */}
        <div className="flex items-center gap-3">
          <a
            href="https://github.com/ganeshmshetty/openclip/releases/latest"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-[13px] font-semibold transition-colors shadow-lg shadow-blue-600/20"
          >
            <Download className="w-3.5 h-3.5" />
            Download
          </a>
          <button
            className="md:hidden p-1.5 text-white/50 hover:text-white"
            onClick={() => setMobileOpen(!mobileOpen)}
            aria-label="Toggle menu"
          >
            {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* Mobile Menu */}
      {mobileOpen && (
        <div className="md:hidden border-t border-white/5 bg-[#050A14] px-5 py-4 flex flex-col gap-1">
          {[
            { href: '/', label: 'Home' },
            { href: '/extensions', label: 'Extensions' },
            { href: '/developers', label: 'Developers' },
            { href: 'https://github.com/ganeshmshetty/openclip', label: 'GitHub', external: true },
          ].map(({ href, label, external }) => (
            <Link
              key={href}
              href={href}
              target={external ? '_blank' : undefined}
              rel={external ? 'noopener noreferrer' : undefined}
              className="px-3 py-2 rounded-lg text-[14px] text-white/60 hover:text-white hover:bg-white/5 transition-all"
              onClick={() => setMobileOpen(false)}
            >
              {label}
            </Link>
          ))}
          <a
            href="https://github.com/ganeshmshetty/openclip/releases/latest"
            className="mt-2 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-blue-600 text-white text-[13.5px] font-semibold"
          >
            <Download className="w-4 h-4" />
            Download for Mac
          </a>
        </div>
      )}
    </header>
  );
}
