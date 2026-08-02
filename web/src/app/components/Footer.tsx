import Link from 'next/link';
import { Paperclip } from 'lucide-react';

const links = [
  { href: '/extensions', label: 'Extensions' },
  { href: '/developers', label: 'Developers' },
  { href: 'https://github.com/ganeshmshetty/openclip', label: 'GitHub', external: true },
];

export default function Footer() {
  return (
    <footer className="mt-auto border-t-[1.5px] border-ink">
      <div className="max-w-6xl mx-auto px-5 sm:px-8 py-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div className="flex items-center gap-2.5">
          <span className="w-[22px] h-[22px] rounded-[6px] bg-accent border-[1.5px] border-ink flex items-center justify-center text-white">
            <Paperclip className="w-3 h-3" />
          </span>
          <div>
            <p className="text-[13px] font-semibold text-ink">OpenClip</p>
            <p className="text-[12px] text-ink/50">Open source macOS clipboard action engine</p>
          </div>
        </div>
        <nav className="flex items-center gap-5">
          {links.map(({ href, label, external }) => (
            <Link
              key={href}
              href={href}
              target={external ? '_blank' : undefined}
              rel={external ? 'noopener noreferrer' : undefined}
              className="text-[12.5px] font-medium text-ink/50 hover:text-accent-deep transition-colors"
            >
              {label}
            </Link>
          ))}
        </nav>
      </div>
      <div className="max-w-6xl mx-auto px-5 sm:px-8 pb-6">
        <p className="font-mono text-[11px] uppercase tracking-widest text-ink/35">
          © 2026 OpenClip · Made for the Mac
        </p>
      </div>
    </footer>
  );
}
