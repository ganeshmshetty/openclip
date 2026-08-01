import Link from 'next/link';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import { Download, Layers, Zap, Terminal, Shield, ArrowRight } from 'lucide-react';

export default function Home() {
  return (
    <div className="min-h-screen bg-neutral-950 text-neutral-100 flex flex-col font-sans">
      <Navbar />

      <main className="flex-1">
        {/* Hero Section */}
        <section className="pt-20 pb-16 border-b border-neutral-800/80">
          <div className="max-w-4xl mx-auto px-4 text-center">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-md bg-neutral-900 border border-neutral-800 text-neutral-400 text-xs font-medium mb-6">
              <span>Open Source macOS Extension Engine</span>
            </div>

            <h1 className="text-4xl sm:text-6xl font-bold text-neutral-100 tracking-tight leading-tight">
              Action Your Text <br />
              <span className="text-neutral-400 font-normal">Directly From Any App.</span>
            </h1>

            <p className="mt-6 text-base sm:text-lg text-neutral-400 max-w-xl mx-auto font-normal leading-relaxed">
              Highlight text anywhere on macOS. Run JavaScript, AppleScript, Shell scripts, or URL actions with zero overhead.
            </p>

            <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-3">
              <a
                href="https://github.com/openclip-app/openclip/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-6 py-3 rounded-md bg-neutral-100 text-neutral-950 hover:bg-neutral-200 font-medium text-sm transition-colors"
              >
                <Download className="w-4 h-4" />
                <span>Download OpenClip for Mac</span>
              </a>

              <Link
                href="/extensions"
                className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-6 py-3 rounded-md bg-neutral-900 hover:bg-neutral-850 border border-neutral-800 text-neutral-200 font-medium text-sm transition-colors"
              >
                <Layers className="w-4 h-4 text-neutral-400" />
                <span>Browse Extensions</span>
              </Link>
            </div>
          </div>
        </section>

        {/* Feature Grid */}
        <section className="py-16 max-w-5xl mx-auto px-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="p-6 rounded-lg bg-neutral-900/50 border border-neutral-800">
              <Zap className="w-5 h-5 text-neutral-300 mb-3" />
              <h3 className="text-base font-semibold text-neutral-100">4 Native Runtimes</h3>
              <p className="mt-2 text-xs text-neutral-400 leading-relaxed">
                Run JavaScript (JavaScriptCore), AppleScript, Shell/Python, or simple URL templates natively.
              </p>
            </div>

            <div className="p-6 rounded-lg bg-neutral-900/50 border border-neutral-800">
              <Terminal className="w-5 h-5 text-neutral-300 mb-3" />
              <h3 className="text-base font-semibold text-neutral-100">Single-File Snippets</h3>
              <p className="mt-2 text-xs text-neutral-400 leading-relaxed">
                Create an extension by making a plain file with a <code>#openclip</code> header. No complex build setup required.
              </p>
            </div>

            <div className="p-6 rounded-lg bg-neutral-900/50 border border-neutral-800">
              <Shield className="w-5 h-5 text-neutral-300 mb-3" />
              <h3 className="text-base font-semibold text-neutral-100">Native Swift Core</h3>
              <p className="mt-2 text-xs text-neutral-400 leading-relaxed">
                Built natively in Swift 5 for macOS with lightweight memory footprint and immediate popup HUD triggers.
              </p>
            </div>
          </div>
        </section>

        {/* Call to Action */}
        <section className="py-12 border-t border-neutral-800/80 bg-neutral-900/30 text-center">
          <div className="max-w-2xl mx-auto px-4">
            <h2 className="text-xl font-bold text-neutral-100">Explore Community Extensions</h2>
            <p className="mt-2 text-xs text-neutral-400">
              Browse extensions and install them into OpenClip with one click.
            </p>
            <div className="mt-6">
              <Link
                href="/extensions"
                className="inline-flex items-center gap-2 px-5 py-2.5 rounded-md bg-neutral-800 hover:bg-neutral-700 text-neutral-100 text-xs font-medium transition-colors"
              >
                <span>Go to Extensions Store</span>
                <ArrowRight className="w-3.5 h-3.5" />
              </Link>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
