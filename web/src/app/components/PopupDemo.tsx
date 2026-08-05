'use client';

import { useEffect, useRef, useState } from 'react';
import {
  Copy,
  Scissors,
  ClipboardPaste,
  CaseUpper,
  Calculator,
  Sparkles,
  Command,
  Search,
  Globe,
  BookOpen,
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

const PALETTE_ACTIONS = [
  { icon: Copy, label: 'Copy' },
  { icon: Scissors, label: 'Cut' },
  { icon: ClipboardPaste, label: 'Paste' },
  { icon: CaseUpper, label: 'Transform Case' },
  { icon: Calculator, label: 'Calculate' },
  { icon: BookOpen, label: 'Define' },
  { icon: Globe, label: 'Search Web', badge: 'url' },
  { icon: Sparkles, label: 'Fix Grammar', badge: 'AI' },
];

const SAMPLE_RESULT =
  'Highlight any text on macOS. Run instant actions in milliseconds — no setup, no overhead.';

export default function PopupDemo() {
  const [phase, setPhase] = useState<Phase>('idle');
  const [typed, setTyped] = useState('');
  const [flash, setFlash] = useState<{ text: string; key: number } | null>(null);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [selectedIndex, setSelectedIndex] = useState(0);
  const timers = useRef<number[]>([]);
  const inputRef = useRef<HTMLInputElement>(null);

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

  // Focus the search field whenever the palette opens
  useEffect(() => {
    if (paletteOpen) inputRef.current?.focus();
  }, [paletteOpen]);

  const filteredActions = PALETTE_ACTIONS.filter((a) =>
    a.label.toLowerCase().includes(query.trim().toLowerCase())
  );

  const showFlash = (text: string) => {
    setFlash({ text, key: Date.now() });
    const id = window.setTimeout(() => {
      setFlash(null);
      timers.current = timers.current.filter((t) => t !== id);
    }, 950);
    timers.current.push(id);
  };

  const runAI = () => {
    if (phase !== 'idle') return;
    setPhase('processing');
    const id = window.setTimeout(() => {
      setPhase('result');
      timers.current = timers.current.filter((t) => t !== id);
    }, 1400);
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

  const togglePalette = () => {
    setPaletteOpen((open) => !open);
    setQuery('');
    setSelectedIndex(0);
  };

  // Global ⌘K / Ctrl+K opens the palette from anywhere on the page
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        togglePalette();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  const runPaletteAction = (label: string) => {
    showFlash(label);
    setPaletteOpen(false);
    setQuery('');
    setSelectedIndex(0);
  };

  const handlePaletteKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      if (query) {
        setQuery('');
      } else {
        setPaletteOpen(false);
      }
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredActions.length) setSelectedIndex((i) => (i + 1) % filteredActions.length);
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (filteredActions.length) {
        setSelectedIndex((i) => (i - 1 + filteredActions.length) % filteredActions.length);
      }
      return;
    }
    if (e.key === 'Enter' && filteredActions[selectedIndex]) {
      runPaletteAction(filteredActions[selectedIndex].label);
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

        <div className="relative">
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
                    aria-label="AI actions"
                  >
                    <Sparkles className="w-3.5 h-3.5" />
                  </button>
                  <span className="hairline group-hover:opacity-0" />
                </div>

                {/* ⌘ command button — replaces the chevron, toggles the action-search palette */}
                <div className="group flex items-stretch">
                  <button
                    onClick={togglePalette}
                    className={`flex items-center justify-center w-9 h-7 hover:bg-accent hover:text-white ${
                      paletteOpen ? 'bg-accent text-white' : 'text-ink/40'
                    }`}
                    aria-label="Search all actions"
                    title="Search all actions (⌘K)"
                  >
                    <Command className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Action-search palette — overlays the bar (the popup becomes the search field) so it
              never shifts the download buttons below */}
          {paletteOpen && (
            <div className="absolute top-[2px] left-[2px] right-[2px] z-20 bg-card border-[1.5px] border-ink rounded-[10px] shadow-chunky overflow-hidden">
              <div className="flex items-center gap-2 h-9 px-3">
                <Search className="w-3.5 h-3.5 text-ink/40 shrink-0" />
                <input
                  ref={inputRef}
                  value={query}
                  onChange={(e) => {
                    setQuery(e.target.value);
                    setSelectedIndex(0);
                  }}
                  onKeyDown={handlePaletteKeyDown}
                  placeholder="Search all actions"
                  className="flex-1 min-w-0 bg-transparent text-[13px] text-ink placeholder:text-ink/40 outline-none font-[var(--font-inter)]"
                  spellCheck={false}
                />
                <span
                  className="chip !px-1.5 !py-0.5 cursor-pointer"
                  onClick={() => setPaletteOpen(false)}
                >
                  esc
                </span>
              </div>

              <div className="border-t-[1.5px] border-ink max-h-[130px] overflow-y-auto">
                {filteredActions.length === 0 && (
                  <p className="px-3 py-2.5 text-[12px] text-ink/50">No matching actions</p>
                )}
                {filteredActions.map(({ icon: Icon, label, badge }, i) => {
                  const isSelected = i === selectedIndex;
                  return (
                    <button
                      key={label}
                      onClick={() => runPaletteAction(label)}
                      onMouseEnter={() => setSelectedIndex(i)}
                      className={`flex items-center gap-2 w-full h-8 px-3 text-left ${
                        isSelected ? 'bg-accent text-white' : 'hover:bg-tint'
                      }`}
                    >
                      <Icon className={`w-3.5 h-3.5 shrink-0 ${isSelected ? 'text-white' : 'text-ink'}`} />
                      <span className="flex-1 min-w-0 text-[13px] font-medium truncate">{label}</span>
                      {badge && (
                        <span className={`text-[10px] font-mono uppercase tracking-wide ${
                          isSelected ? 'text-white/80' : 'text-ink/40'
                        }`}>
                          {badge}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </div>

        {/* AI result card — absolutely positioned so it overlays the download buttons without shifting layout */}
        {phase === 'result' && (
          <div className="card-chunky absolute top-full left-1/2 -translate-x-1/2 mt-2 w-[320px] max-w-full p-3 text-left z-20">
            <div className="flex items-center justify-between mb-2">
              <span className="eyebrow">AI Actions · Fix grammar</span>
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
