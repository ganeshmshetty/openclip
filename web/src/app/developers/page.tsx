import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { Code, Terminal, FileCode, ArrowRight } from 'lucide-react';

const inlineCode = 'font-mono text-[12px] bg-tint border border-ink/20 rounded px-1.5 py-0.5';
const codeBlock =
  'p-4 rounded-[10px] bg-card border-[1.5px] border-ink shadow-chunky-sm text-ink text-[12.5px] font-mono overflow-x-auto leading-relaxed';

export default function DevelopersPage() {
  return (
    <div className="min-h-screen text-ink flex flex-col">
      <Navbar />

      <main className="flex-1 max-w-5xl mx-auto px-5 sm:px-8 py-16 w-full">
        <div className="text-center max-w-3xl mx-auto mb-16">
          <span className="chip mb-5">
            <Code className="w-3.5 h-3.5" />
            Developer Guide
          </span>
          <h1 className="text-3xl sm:text-5xl font-extrabold text-ink tracking-[-0.03em]">
            Build OpenClip Extensions
          </h1>
          <p className="mt-4 text-ink/60 text-base sm:text-lg">
            Create custom extensions in seconds using plain text files, JavaScript, AppleScript, or Shell scripts.
          </p>
        </div>

        {/* Section 1: Single File Snippet */}
        <section className="card-chunky mb-12 p-8">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-[10px] bg-tint border-[1.5px] border-ink flex items-center justify-center text-accent-deep">
              <FileCode className="w-5 h-5" />
            </div>
            <h2 className="text-xl sm:text-2xl font-bold text-ink">Method 1: Single-File Snippet (Easiest)</h2>
          </div>
          <p className="text-ink/60 text-sm mb-6 leading-relaxed">
            Create a plain text file ending in <code className={inlineCode}>.txt</code> or{' '}
            <code className={inlineCode}>.js</code> containing a{' '}
            <code className={inlineCode}>#openclip</code> header at the top:
          </p>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <span className="eyebrow text-accent-deep block mb-2">Web Search URL Example</span>
              <pre className={codeBlock}>
{`#openclip
title: Search YouTube
icon: play.circle
url: https://www.youtube.com/results?search_query={text}`}
              </pre>
            </div>

            <div>
              <span className="eyebrow text-accent-deep block mb-2">JavaScript Example</span>
              <pre className={codeBlock}>
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
        <section className="card-chunky mb-12 p-8">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-[10px] bg-tint border-[1.5px] border-ink flex items-center justify-center text-accent-deep">
              <Terminal className="w-5 h-5" />
            </div>
            <h2 className="text-xl sm:text-2xl font-bold text-ink">
              Method 2: Multi-File Package (<code className={inlineCode}>.openclipext</code>)
            </h2>
          </div>
          <p className="text-ink/60 text-sm mb-6 leading-relaxed">
            Create a folder named <code className={inlineCode}>MyExtension.openclipext</code> containing an{' '}
            <code className={inlineCode}>openclip.json</code> manifest file:
          </p>

          <pre className={codeBlock}>
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
        <section className="card-chunky bg-tint p-8 text-center">
          <h2 className="text-xl sm:text-2xl font-bold text-ink">Submit Your Extension</h2>
          <p className="text-ink/60 text-sm mt-2 max-w-xl mx-auto">
            Want your extension featured in the OpenClip Store? Submit a Pull Request to our GitHub repository or upload your package file.
          </p>
          <div className="mt-6">
            <a
              href="https://github.com/ganeshmshetty/openclip"
              target="_blank"
              rel="noopener noreferrer"
              className="btn-chunky px-6 py-3 text-sm"
            >
              Submit via GitHub
              <ArrowRight className="w-4 h-4" />
            </a>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
