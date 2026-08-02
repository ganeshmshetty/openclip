'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Download, Menu, X } from 'lucide-react';

const NAV_LINKS = [
  { href: '/', label: 'Home' },
  { href: '/extensions', label: 'Extensions' },
  { href: '/developers', label: 'Developers' },
  { href: 'https://github.com/ganeshmshetty/openclip', label: 'GitHub', external: true },
];

function LogoCell() {
  return (
    <Link href="/" className="flex items-center gap-2 pl-3 pr-3.5 py-2 shrink-0" aria-label="OpenClip home">
      <img
        src="/icons/openclip-icon.png"
        alt="OpenClip"
        className="w-[26px] h-[26px] rounded-[8px]"
        width={26}
        height={26}
      />
      <span className="font-semibold text-[15px] tracking-[-0.01em] text-ink">OpenClip</span>
    </Link>
  );
}

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <header className="sticky top-4 z-50 px-4">
      <div className="mx-auto w-fit max-w-full">
        {/* Popup-style segmented pill */}
        <nav className="flex items-stretch bg-card border-[1.5px] border-ink rounded-[12px] shadow-chunky">
          <LogoCell />

          {/* Desktop link cells — hover floods accent, divider hides (mirrors the real popup) */}
          <div className="hidden md:flex items-stretch">
            {NAV_LINKS.map(({ href, label, external }) => (
              <div key={href} className="group flex items-stretch">
                <span className="hairline group-hover:opacity-0" />
                <Link
                  href={href}
                  target={external ? '_blank' : undefined}
                  rel={external ? 'noopener noreferrer' : undefined}
                  className="flex items-center px-3.5 text-[13.5px] font-medium text-ink hover:bg-accent hover:text-white"
                >
                  {label}
                </Link>
              </div>
            ))}
          </div>

          {/* CTA cell */}
          <div className="hidden sm:flex items-stretch">
            <span className="hairline" />
            <div className="flex items-center px-2.5 py-1.5">
              <a
                href="https://github.com/ganeshmshetty/openclip/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="btn-chunky px-3 py-1.5 text-[13px] shadow-chunky-sm"
              >
                <Download className="w-3.5 h-3.5" />
                Download
              </a>
            </div>
          </div>

          {/* Hamburger cell (mobile) */}
          <div className="flex md:hidden items-stretch">
            <span className="hairline" />
            <button
              className="flex items-center px-3 text-ink hover:bg-accent hover:text-white"
              onClick={() => setMobileOpen(!mobileOpen)}
              aria-label="Toggle menu"
            >
              {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
            </button>
          </div>
        </nav>

        {/* Mobile dropdown */}
        {mobileOpen && (
          <div className="md:hidden card-chunky mt-2 p-2 flex flex-col">
            {NAV_LINKS.map(({ href, label, external }) => (
              <Link
                key={href}
                href={href}
                target={external ? '_blank' : undefined}
                rel={external ? 'noopener noreferrer' : undefined}
                className="px-3 py-2 rounded-[8px] text-[14px] font-medium text-ink hover:bg-accent hover:text-white"
                onClick={() => setMobileOpen(false)}
              >
                {label}
              </Link>
            ))}
            <a
              href="https://github.com/ganeshmshetty/openclip/releases/latest"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-chunky mt-2 px-4 py-2.5 text-[13.5px]"
            >
              <Download className="w-4 h-4" />
              Download for Mac
            </a>
          </div>
        )}
      </div>
    </header>
  );
}
