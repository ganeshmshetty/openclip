import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { Code, Terminal, FileCode, CheckCircle2, Sparkles } from 'lucide-react';

export default function DevelopersPage() {
  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 flex flex-col font-sans">
      <Navbar />

      <main className="flex-1 max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-12 w-full">
        <div className="text-center max-w-3xl mx-auto mb-16">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 text-xs font-semibold uppercase tracking-wider mb-4">
            <Code className="w-3.5 h-3.5" />
            <span>Developer Guide</span>
          </div>
          <h1 className="text-3xl sm:text-5xl font-extrabold text-white tracking-tight">
            Build OpenClip Extensions
          </h1>
          <p className="mt-4 text-slate-400 text-base sm:text-lg">
            Create custom extensions in seconds using plain text files, JavaScript, AppleScript, or Shell scripts.
          </p>
        </div>

        {/* Section 1: Single File Snippet */}
        <section className="mb-16 p-8 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-xl">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-purple-500/10 border border-purple-500/20 flex items-center justify-center text-purple-400">
              <FileCode className="w-5 h-5" />
            </div>
            <h2 className="text-2xl font-bold text-white">Method 1: Single-File Snippet (Easiest)</h2>
          </div>
          <p className="text-slate-400 text-sm mb-6 leading-relaxed">
            Create a plain text file ending in <code>.txt</code> or <code>.js</code> containing a <code>#openclip</code> header at the top:
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <span className="text-xs font-semibold text-purple-400 uppercase tracking-wider block mb-2">Web Search URL Example</span>
              <pre className="p-4 rounded-xl bg-slate-950 border border-slate-800/80 text-slate-200 text-xs font-mono overflow-x-auto leading-relaxed">
{`#openclip
title: Search YouTube
icon: play.circle
url: https://www.youtube.com/results?search_query={text}`}
              </pre>
            </div>

            <div>
              <span className="text-xs font-semibold text-indigo-400 uppercase tracking-wider block mb-2">JavaScript Example</span>
              <pre className="p-4 rounded-xl bg-slate-950 border border-slate-800/80 text-slate-200 text-xs font-mono overflow-x-auto leading-relaxed">
{`#openclip
title: Uppercase Text
icon: textformat.size
js:
return text.toUpperCase();`}
              </pre>
            </div>
          </div>
        </section>

        {/* Section 2: Full Extension Package */}
        <section className="mb-16 p-8 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-xl">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-indigo-500/10 border border-indigo-500/20 flex items-center justify-center text-indigo-400">
              <Terminal className="w-5 h-5" />
            </div>
            <h2 className="text-2xl font-bold text-white">Method 2: Multi-File Package (`.openclipext`)</h2>
          </div>
          <p className="text-slate-400 text-sm mb-6 leading-relaxed">
            Create a folder named <code>MyExtension.openclipext</code> containing an <code>openclip.json</code> manifest file:
          </p>

          <pre className="p-4 rounded-xl bg-slate-950 border border-slate-800/80 text-slate-200 text-xs font-mono overflow-x-auto leading-relaxed">
{`{
  "id": "com.yourname.myextension",
  "name": "My Cool Extension",
  "actions": [
    {
      "title": "Search YouTube",
      "icon": "symbol:play.circle",
      "url": "https://www.youtube.com/results?search_query={text}"
    }
  ]
}`}
          </pre>
        </section>

        {/* Section 3: Submitting to Marketplace */}
        <section className="p-8 rounded-2xl bg-slate-900/60 border border-slate-800/80 backdrop-blur-xl text-center">
          <Sparkles className="w-8 h-8 text-purple-400 mx-auto mb-3" />
          <h2 className="text-2xl font-bold text-white">Submit Your Extension</h2>
          <p className="text-slate-400 text-sm mt-2 max-w-xl mx-auto">
            Want your extension featured in the OpenClip Store? Submit a Pull Request to our GitHub repository or upload your package file.
          </p>
          <div className="mt-6">
            <a
              href="https://github.com/openclip-app/openclip"
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-purple-600 hover:bg-purple-500 text-white font-medium text-sm transition-colors shadow-lg shadow-purple-500/25"
            >
              <span>Submit via GitHub</span>
            </a>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
