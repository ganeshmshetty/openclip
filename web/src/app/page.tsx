import Link from 'next/link';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import { Download, Layers, Zap, Terminal, Shield, ArrowRight, Smile, Sparkles } from 'lucide-react';

export default function Home() {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans selection:bg-blue-500 selection:text-white">
      <Navbar />

      <main className="flex-1">
        {/* Fun Hero Section */}
        <section className="pt-20 pb-16 border-b border-blue-900/30 relative overflow-hidden">
          <div className="max-w-4xl mx-auto px-4 text-center relative z-10">
            <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-blue-500/10 border border-blue-500/30 text-blue-400 text-xs font-bold uppercase tracking-widest mb-6">
              <Sparkles className="w-3.5 h-3.5" />
              <span>Fun & Fast Clipboard Power</span>
            </div>

            <h1 className="text-4xl sm:text-6xl font-extrabold text-white tracking-tight leading-tight">
              Supercharge Your Text <br />
              <span className="bg-gradient-to-r from-blue-400 via-sky-400 to-cyan-300 bg-clip-text text-transparent">
                With One Click. ⚡
              </span>
            </h1>

            <p className="mt-6 text-base sm:text-xl text-slate-300 max-w-2xl mx-auto font-medium leading-relaxed">
              Highlight text anywhere on your Mac and pop up instant actions! Run JavaScript, AppleScript, Shell commands, or search web apps seamlessly.
            </p>

            <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-4">
              <a
                href="https://github.com/openclip-app/openclip/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="w-full sm:w-auto inline-flex items-center justify-center gap-2.5 px-7 py-3.5 rounded-2xl bg-gradient-to-r from-blue-600 to-sky-500 hover:from-blue-500 hover:to-sky-400 text-white font-extrabold text-base shadow-xl shadow-blue-500/25 transition-all hover:scale-105 active:scale-95"
              >
                <Download className="w-5 h-5" />
                <span>Get OpenClip Free</span>
              </a>

              <Link
                href="/extensions"
                className="w-full sm:w-auto inline-flex items-center justify-center gap-2 px-7 py-3.5 rounded-2xl bg-slate-900 hover:bg-slate-800 border border-blue-900/50 text-slate-200 font-bold text-base transition-all hover:scale-105 active:scale-95"
              >
                <Layers className="w-5 h-5 text-blue-400" />
                <span>Explore Store</span>
              </Link>
            </div>
          </div>
        </section>

        {/* Fun Feature Grid */}
        <section className="py-16 max-w-5xl mx-auto px-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="p-6 rounded-2xl bg-slate-900/80 border border-blue-900/40 hover:border-blue-500/50 transition-all hover:-translate-y-1">
              <div className="w-10 h-10 rounded-xl bg-blue-500/10 border border-blue-500/30 flex items-center justify-center text-blue-400 font-bold text-lg mb-4">
                🚀
              </div>
              <h3 className="text-lg font-bold text-white">4 Runtimes, Infinite Possibilities</h3>
              <p className="mt-2 text-xs text-slate-400 leading-relaxed font-medium">
                Write actions in JavaScript, AppleScript, Shell/Python, or simple URL templates.
              </p>
            </div>

            <div className="p-6 rounded-2xl bg-slate-900/80 border border-blue-900/40 hover:border-blue-500/50 transition-all hover:-translate-y-1">
              <div className="w-10 h-10 rounded-xl bg-sky-500/10 border border-sky-500/30 flex items-center justify-center text-sky-400 font-bold text-lg mb-4">
                📝
              </div>
              <h3 className="text-lg font-bold text-white">Super Easy Snippets</h3>
              <p className="mt-2 text-xs text-slate-400 leading-relaxed font-medium">
                Just drop a text file with a <code>#openclip</code> header to create your own instant extension!
              </p>
            </div>

            <div className="p-6 rounded-2xl bg-slate-900/80 border border-blue-900/40 hover:border-blue-500/50 transition-all hover:-translate-y-1">
              <div className="w-10 h-10 rounded-xl bg-cyan-500/10 border border-cyan-500/30 flex items-center justify-center text-cyan-400 font-bold text-lg mb-4">
                ⚡
              </div>
              <h3 className="text-lg font-bold text-white">Pure Swift Speed</h3>
              <p className="mt-2 text-xs text-slate-400 leading-relaxed font-medium">
                Built natively for macOS in Swift 5. Blazing fast, lightweight, and fun to use every day.
              </p>
            </div>
          </div>
        </section>

        {/* Fun Call to Action */}
        <section className="py-12 border-t border-blue-900/30 bg-slate-900/40 text-center">
          <div className="max-w-2xl mx-auto px-4">
            <h2 className="text-2xl font-extrabold text-white">Ready to have fun with your clipboard?</h2>
            <p className="mt-2 text-sm text-slate-400 font-medium">
              Browse community extensions and install them into OpenClip with one click.
            </p>
            <div className="mt-6">
              <Link
                href="/extensions"
                className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold transition-all hover:scale-105 shadow-lg shadow-blue-500/25"
              >
                <span>Browse Extension Store</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
