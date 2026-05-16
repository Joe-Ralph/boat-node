import React, { forwardRef } from 'react';

export interface StoryCopyProps {
    title: string;
    titleColor?: string;
    lines: string[];
    align?: 'top' | 'center';
    lineClass?: string;
}

const StoryCopy = forwardRef<HTMLDivElement, StoryCopyProps>(({
    title,
    titleColor = '#D54DFF',
    lines,
    align = 'top',
    lineClass = '',
}, ref) => {
    const justify = align === 'center' ? 'justify-center' : 'justify-start';
    const pad = align === 'center' ? '' : 'pt-12 md:pt-20';
    return (
        <div
            ref={ref}
            className={`story-section absolute inset-0 opacity-0 flex flex-col items-center ${justify} ${pad} pointer-events-none`}
        >
            <div className="text-center max-w-2xl px-6">
                <h2
                    className="text-4xl md:text-7xl font-bold tracking-tight mb-6 drop-shadow-lg"
                    style={{ color: titleColor }}
                >
                    {title}
                </h2>
                <p className="text-lg md:text-3xl text-white leading-relaxed font-bold drop-shadow-md">
                    {lines.map((line, i) => (
                        <span
                            key={i}
                            className={`story-line font-medium opacity-0 block ${lineClass}`}
                        >
                            {line}
                        </span>
                    ))}
                </p>
            </div>
        </div>
    );
});
StoryCopy.displayName = 'StoryCopy';

export default StoryCopy;
