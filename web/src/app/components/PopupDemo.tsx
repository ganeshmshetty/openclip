'use client';

import { useEffect, useRef, useState } from 'react';
import {
  Copy,
  Scissors,
  ClipboardPaste,
  CaseUpper,
  Calculator,
  Sparkles,
  ChevronRight,
  X,
} from 'lucide-react';

type Phase = 'idle' | 'processing' | 'result';

const ACTION_CELLS = [
  { icon: Copy, label: 'COPY' },
  { icon: Scissors, label: 'CUT' },
  { icon: ClipboardPaste, label: 'PASTE' },
  { icon: CaseUpper, label: 'TRANSFORM' },
  { icon: Calculator, label: 'CALCULATE' },
];

const SAMPLE_RESULT =
  'Highlight any text on macOS. Run instant actions in milliseconds — no setup, no overhead.';

export default function PopupDemo() {
  const [phase, setPhase] = useState<Phase>('idle');
  const [typed, setTyped] = useState('');
  const [flash, setFlash] = useState<{ text: string; key: number } | null>(null);
  const timers = useRef<number[]>([]);

  useEffect(() => () => timers.current.forEach((t) => window.clearTimeout(t)), []);

  // Typewriter for the AI result card
  useEffect(() => {
    if (phase !== 'result') return;
    setTyped('');
    let i = 0;
    const id = window.setInterval(() => {
      i += 1;
      setTyped(SAMPLE_RESULT.slice(0, i));
      if (i >= SAMPLE_RESULT.length) window.clearInterval(id);
    }, 18);
    return () => window.clearInterval(id);
  }, [phase]);

  const showFlash = (text: string) => {
    setFlash({ text, key: Date.now() });
    const id = window.setTimeout(() => setFlash(null), 950);
    timers.current.push(id);
  };

  const runAI = () => {
    if (phase !== 'idle') return;
    setPhase('processing');
    const id = window.setTimeout(() => setPhase('result'), 1400);
    timers.current.push(id);
  };

  const copyResult = async () => {
    try {
      await navigator.clipboard.writeText(SAMPLE_RESULT);
      showFlash('COPIED ✓');
    } catch {
      showFlash('COPY FAILED');
    }
  };

  return (
    <div className="flex flex-col items-center">
      <div className="relative">
        {flash && (
          <span
            key={flash.key}
            className="oc-flash chip absolute -top-11 left-1/2 -translate-x-1/2 whitespace-nowrap z-10"
          >
            {flash.text}
          </span>
        )}

        {/* Glow ring appears while the AI is "working" (mirrors PopupView's border sweep) */}
        <div className={`rounded-[12px] p-[2px] ${phase === 'processing' ? 'oc-glow-ring' : ''}`}>
          <div className="bg-card border-[1.5px] border-ink rounded-[10px] overflow-hidden">
            <div
              className={`flex items-stretch transition-opacity ${
                phase === 'processing' ? 'opacity-70' : ''
              }`}
            >
              {ACTION_CELLS.map(({ icon: Icon, label }) => (
                <div key={label} className="group flex items-stretch">
                  <button
                    onClick={() => showFlash(label)}
                    className="flex items-center justify-center w-9 h-7 text-ink hover:bg-accent hover:text-white"
                    aria-label={label}
                  >
                    <Icon className="w-3.5 h-3.5" />
                  </button>
                  <span className="hairline group-hover:opacity-0" />
                </div>
              ))}

              {/* AI cell — accent glyph at rest, like the real popup */}
              <div className="group flex items-stretch">
                <button
                  onClick={runAI}
                  className="flex items-center justify-center w-9 h-7 text-accent-deep hover:bg-accent hover:text-white"
                  aria-label="AI assistant"
                >
                  <Sparkles className="w-3.5 h-3.5" />
                </button>
                <span className="hairline group-hover:opacity-0" />
              </div>

              <button
                onClick={() => showFlash('MORE ACTIONS')}
                className="flex items-center justify-center w-[26px] h-7 text-ink/40 hover:bg-accent hover:text-white"
                aria-label="More actions"
              >
                <ChevronRight className="w-3 h-3" />
              </button>
            </div>
          </div>
        </div>

        {/* AI result card — absolutely positioned so it overlays the download buttons without shifting layout */}
        {phase === 'result' && (
          <div className="card-chunky absolute top-full left-1/2 -translate-x-1/2 mt-2 w-[320px] max-w-full p-3 text-left z-20">
            <div className="flex items-center justify-between mb-2">
              <span className="eyebrow">AI Assistant · Fix grammar</span>
              <button
                onClick={() => setPhase('idle')}
                className="w-6 h-6 rounded-full border-[1.5px] border-ink bg-card hover:bg-tint flex items-center justify-center"
                aria-label="Close"
              >
                <X className="w-3 h-3" />
              </button>
            </div>
            <p className="text-[13px] leading-relaxed text-ink/80 min-h-[90px]">
              {typed}
              <span className="inline-block w-[2px] h-[13px] ml-0.5 bg-accent align-middle animate-pulse" />
            </p>
            <div className="flex gap-2 mt-2">
              <button
                onClick={() => {
                  showFlash('REPLACED ✓');
                  setPhase('idle');
                }}
                className="btn-chunky px-3 py-1.5 text-[12px] shadow-chunky-sm"
              >
                Replace
              </button>
              <button
                onClick={copyResult}
                className="btn-chunky-outline px-3 py-1.5 text-[12px] shadow-chunky-sm"
              >
                Copy
              </button>
            </div>
          </div>
        )}
        {phase === 'processing' && (
          <span className="eyebrow absolute top-full left-1/2 -translate-x-1/2 mt-3 z-10 whitespace-nowrap">
            Working…
          </span>
        )}
      </div>
    </div>
  );
}
