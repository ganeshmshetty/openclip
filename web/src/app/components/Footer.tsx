import Link from 'next/link';

const links = [
  { href: '/extensions', label: 'Extensions' },
  { href: '/developers', label: 'Developers' },
  { href: 'https://github.com/openclip-app/openclip', label: 'GitHub', external: true },
];

export default function Footer() {
  return (
    <footer className="mt-auto border-t border-white/5 bg-[#050A14]">
      <div className="max-w-6xl mx-auto px-5 sm:px-8 py-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4">
        <div>
          <p className="text-[13px] font-semibold text-white/70">OpenClip</p>
          <p className="text-[12px] text-white/30 mt-0.5">Open source macOS clipboard action engine</p>
        </div>
        <nav className="flex items-center gap-5">
          {links.map(({ href, label, external }) => (
            <Link
              key={href}
              href={href}
              target={external ? '_blank' : undefined}
              rel={external ? 'noopener noreferrer' : undefined}
              className="text-[12.5px] text-white/35 hover:text-white/70 transition-colors"
            >
              {label}
            </Link>
          ))}
        </nav>
      </div>
    </footer>
  );
}
