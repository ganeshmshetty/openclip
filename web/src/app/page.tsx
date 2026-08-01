import Link from 'next/link';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import { Download, ArrowRight, Zap, Terminal, GitBranch, Shield } from 'lucide-react';

export default function Home() {
  return (
    <div className="min-h-screen bg-[#050A14] text-white flex flex-col font-[var(--font-inter)]">
      <Navbar />

      <main className="flex-1">
        {/* Hero */}
        <section className="relative pt-24 pb-20 overflow-hidden">
          {/* Subtle blue radial glow behind hero text */}
          <div className="pointer-events-none absolute inset-0 flex items-start justify-center">
            <div className="w-[700px] h-[400px] rounded-full bg-blue-600/10 blur-[120px] mt-10" />
          </div>

          <div className="relative max-w-3xl mx-auto px-5 sm:px-8 text-center">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full border border-blue-500/20 bg-blue-500/8 text-blue-400 text-[12px] font-medium tracking-wide mb-7">
              <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
              Open Source · Native macOS · Swift 5
            </div>

            <h1 className="text-4xl sm:text-[56px] font-bold tracking-[-0.03em] leading-[1.1] text-white">
              Clipboard actions,<br />
              <span className="text-blue-400">without the friction.</span>
            </h1>

            <p className="mt-5 text-base sm:text-lg text-white/50 max-w-xl mx-auto leading-relaxed font-normal">
              Highlight any text on macOS. Run JavaScript, AppleScript, Shell scripts, or URL actions in milliseconds — no setup, no overhead.
            </p>

            <div className="mt-9 flex flex-col sm:flex-row items-center justify-center gap-3">
              <a
                href="https://github.com/ganeshmshetty/openclip/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="group flex items-center gap-2 px-5 py-2.5 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold transition-all shadow-xl shadow-blue-600/20 hover:shadow-blue-500/30"
              >
                <Download className="w-4 h-4" />
                Download for macOS
              </a>
              <Link
                href="/extensions"
                className="flex items-center gap-2 px-5 py-2.5 rounded-xl border border-white/10 bg-white/5 hover:bg-white/8 text-white/80 text-sm font-medium transition-all"
              >
                Browse Extensions
                <ArrowRight className="w-4 h-4 text-white/40" />
              </Link>
            </div>
          </div>
        </section>

        {/* Divider */}
        <div className="max-w-6xl mx-auto px-5 sm:px-8">
          <div className="border-t border-white/5" />
        </div>

        {/* Features */}
        <section className="py-20 max-w-6xl mx-auto px-5 sm:px-8">
          <p className="text-xs font-semibold uppercase tracking-widest text-white/25 mb-10">
            Why OpenClip
          </p>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {[
              {
                icon: <Zap className="w-4 h-4" />,
                title: '4 Native Runtimes',
                body: 'JavaScript (JSC), AppleScript, Shell/Python, and URL templates — all running natively.',
              },
              {
                icon: <Terminal className="w-4 h-4" />,
                title: 'One-File Extensions',
                body: 'Drop a text file with an #openclip header to create a fully functional extension.',
              },
              {
                icon: <Shield className="w-4 h-4" />,
                title: 'Pure Swift Core',
                body: 'Built natively in Swift 5. Lightweight, sandboxed, and always feels instant.',
              },
              {
                icon: <GitBranch className="w-4 h-4" />,
                title: 'Open Source',
                body: 'Every line is on GitHub. Audit, fork, and contribute at any time.',
              },
            ].map(({ icon, title, body }) => (
              <div
                key={title}
                className="p-5 rounded-2xl border border-white/6 bg-white/[0.02] hover:bg-white/[0.04] hover:border-white/10 transition-all"
              >
                <div className="w-8 h-8 rounded-lg border border-white/8 bg-white/5 flex items-center justify-center text-blue-400 mb-4">
                  {icon}
                </div>
                <h3 className="text-[14px] font-semibold text-white/90 mb-1.5">{title}</h3>
                <p className="text-[12.5px] text-white/40 leading-relaxed">{body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* Divider */}
        <div className="max-w-6xl mx-auto px-5 sm:px-8">
          <div className="border-t border-white/5" />
        </div>

        {/* CTA Strip */}
        <section className="py-16 max-w-6xl mx-auto px-5 sm:px-8">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
            <div>
              <h2 className="text-xl font-bold tracking-tight text-white/90">
                Ready to install your first extension?
              </h2>
              <p className="text-[13px] text-white/40 mt-1">
                Browse the directory and install with one click from your browser.
              </p>
            </div>
            <Link
              href="/extensions"
              className="shrink-0 flex items-center gap-2 px-5 py-2.5 rounded-xl bg-white/6 hover:bg-white/10 border border-white/8 text-white/80 text-sm font-medium transition-all whitespace-nowrap"
            >
              Go to Extensions
              <ArrowRight className="w-4 h-4 text-white/40" />
            </Link>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
