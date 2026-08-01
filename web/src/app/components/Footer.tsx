import Link from 'next/link';

export default function Footer() {
  return (
    <footer className="border-t border-neutral-800/80 bg-neutral-950 text-neutral-400 text-xs py-10">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 flex flex-col sm:flex-row items-center justify-between gap-4">
        <div>
          <p className="font-medium text-neutral-300">OpenClip — macOS Action & Clipboard Engine</p>
          <p className="text-neutral-500 mt-0.5">Open source, lightweight, native Swift architecture.</p>
        </div>
        <div className="flex items-center gap-6">
          <Link href="/extensions" className="hover:text-neutral-200 transition-colors">
            Extensions
          </Link>
          <Link href="/developers" className="hover:text-neutral-200 transition-colors">
            Developers
          </Link>
          <a
            href="https://github.com/openclip-app/openclip"
            target="_blank"
            rel="noopener noreferrer"
            className="hover:text-neutral-200 transition-colors"
          >
            GitHub
          </a>
        </div>
      </div>
    </footer>
  );
}
