'use client';

import { useState } from 'react';
import { FileImage } from 'lucide-react';

interface GifFrameProps {
  src: string;
  alt: string;
  name: string;
}

export default function GifFrame({ src, alt, name }: GifFrameProps) {
  const [error, setError] = useState(false);

  return (
    <div className="card-chunky overflow-hidden">
      {error ? (
        <div className="aspect-[4/3] bg-tint flex flex-col items-center justify-center gap-2 p-6 text-center">
          <span className="w-10 h-10 rounded-[10px] bg-card border-[1.5px] border-ink flex items-center justify-center text-accent-deep">
            <FileImage className="w-5 h-5" />
          </span>
          <p className="eyebrow text-ink">GIF coming soon</p>
          <p className="font-mono text-[11px] text-ink/50">
            drop <span className="text-accent-deep">{name}</span> into /public/gifs/
          </p>
        </div>
      ) : (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt={alt}
          loading="lazy"
          onError={() => setError(true)}
          className="block w-full h-auto"
        />
      )}
    </div>
  );
}
