import Link from 'next/link';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import PopupDemo from './components/PopupDemo';
import GifFrame from './components/GifFrame';
import { Download, ArrowRight, Zap, Terminal, GitBranch, Shield } from 'lucide-react';

const SHOWCASE = [
  {
    eyebrow: '01 / AI Assistant',
    title: 'AI, right in the popup.',
    body: 'Fix grammar, summarize, translate — results stream into a card. Replace or copy in one click.',
    gif: '/gifs/ai-assistant.gif',
    name: 'ai-assistant.gif',
    alt: 'OpenClip AI assistant rewriting selected text',
  },
  {
    eyebrow: '02 / Calculate',
    title: 'Math without leaving your text.',
    body: 'Select any expression and the answer appears inline, ready to paste.',
    gif: '/gifs/calculate.gif',
    name: 'calculate.gif',
    alt: 'OpenClip calculating a selected math expression',
  },
  {
    eyebrow: '03 / Share',
    title: 'Share straight from the selection.',
    body: 'Send selected text to the macOS share sheet — Messages, Mail, Notes, anywhere.',
    gif: '/gifs/share.gif',
    name: 'share.gif',
    alt: 'OpenClip sending selected text to the macOS share sheet',
  },
  {
    eyebrow: '04 / Word Completion',
    title: 'Finish words as you type.',
    body: 'Accept a completion instantly, without ever leaving the keyboard.',
    gif: '/gifs/word-completion.gif',
    name: 'word-completion.gif',
    alt: 'OpenClip completing a word inline',
  },
];

const FEATURES = [
  {
    icon: Zap,
    title: '4 Native Runtimes',
    body: 'JavaScript (JSC), AppleScript, Shell/Python, and URL templates — all running natively.',
  },
  {
    icon: Terminal,
    title: 'One-File Extensions',
    body: 'Drop a text file with an #openclip header to create a fully functional extension.',
  },
  {
    icon: Shield,
    title: 'Pure Swift Core',
    body: 'Built natively in Swift 5. Lightweight, sandboxed, and always feels instant.',
  },
  {
    icon: GitBranch,
    title: 'Open Source',
    body: 'Every line is on GitHub. Audit, fork, and contribute at any time.',
  },
];

export default function Home() {
  return (
    <div className="min-h-screen text-ink flex flex-col font-[var(--font-inter)]">
      <Navbar />

      <main className="flex-1">
        {/* Hero */}
        <section className="pt-16 pb-20">
          <div className="max-w-3xl mx-auto px-5 sm:px-8 text-center">
            <span className="chip mb-7">Open Source · Native macOS · Swift 5</span>

            <h1 className="text-4xl sm:text-[56px] font-extrabold tracking-[-0.03em] leading-[1.05] text-ink">
              Clipboard actions,<br />
              <span className="text-accent-deep">without the friction.</span>
            </h1>

            <p className="mt-5 text-base sm:text-lg text-ink/60 max-w-xl mx-auto leading-relaxed">
              Highlight any text on macOS. Run JavaScript, AppleScript, Shell scripts, or URL actions in milliseconds — no setup, no overhead.
            </p>

            <div className="mt-12 flex flex-col items-center gap-3">
              <p className="eyebrow">The real popup UI — hover it, click the ✦</p>
              <PopupDemo />
            </div>

            <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
              <a
                href="https://github.com/ganeshmshetty/openclip/releases/latest"
                target="_blank"
                rel="noopener noreferrer"
                className="btn-chunky px-5 py-2.5 text-sm"
              >
                <Download className="w-4 h-4" />
                Download for macOS
              </a>
              <Link href="/extensions" className="btn-chunky-outline px-5 py-2.5 text-sm">
                Browse Extensions
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
        </section>

        {/* See it in action */}
        <section className="py-20 max-w-6xl mx-auto px-5 sm:px-8">
          <p className="eyebrow mb-2">See it in action</p>
          <h2 className="text-2xl sm:text-3xl font-extrabold tracking-[-0.02em] text-ink mb-12">
            Four actions you&apos;ll use every day.
          </h2>

          <div className="space-y-16">
            {SHOWCASE.map(({ eyebrow, title, body, gif, name, alt }, i) => (
              <div key={eyebrow} className="grid md:grid-cols-2 gap-8 md:gap-12 items-center">
                <div className={i % 2 === 1 ? 'md:order-2' : ''}>
                  <GifFrame src={gif} alt={alt} name={name} />
                </div>
                <div className={i % 2 === 1 ? 'md:order-1' : ''}>
                  <p className="eyebrow text-accent-deep mb-3">{eyebrow}</p>
                  <h3 className="text-xl sm:text-2xl font-bold tracking-[-0.01em] text-ink mb-2">
                    {title}
                  </h3>
                  <p className="text-[14.5px] text-ink/60 leading-relaxed max-w-md">{body}</p>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* Features */}
        <section className="py-20 max-w-6xl mx-auto px-5 sm:px-8">
          <p className="eyebrow mb-10">Why OpenClip</p>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {FEATURES.map(({ icon: Icon, title, body }) => (
              <div
                key={title}
                className="card-chunky p-5 hover:-translate-x-0.5 hover:-translate-y-0.5 hover:shadow-chunky-lg transition-all"
              >
                <div className="w-9 h-9 rounded-[8px] border-[1.5px] border-ink bg-tint flex items-center justify-center text-accent-deep mb-4">
                  <Icon className="w-4 h-4" />
                </div>
                <h3 className="text-[14px] font-semibold text-ink mb-1.5">{title}</h3>
                <p className="text-[12.5px] text-ink/55 leading-relaxed">{body}</p>
              </div>
            ))}
          </div>
        </section>

        {/* CTA Strip */}
        <section className="py-16 max-w-6xl mx-auto px-5 sm:px-8">
          <div className="card-chunky bg-tint p-8 flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6">
            <div>
              <h2 className="text-xl font-bold tracking-tight text-ink">
                Ready to install your first extension?
              </h2>
              <p className="text-[13px] text-ink/55 mt-1">
                Browse the directory and install with one click from your browser.
              </p>
            </div>
            <Link href="/extensions" className="btn-chunky shrink-0 px-5 py-2.5 text-sm whitespace-nowrap">
              Go to Extensions
              <ArrowRight className="w-4 h-4" />
            </Link>
          </div>
        </section>
      </main>

      <Footer />
    </div>
  );
}
