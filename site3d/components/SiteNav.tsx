import React, { useEffect, useState } from 'react';

const linkBase =
    "px-3 py-1.5 font-['JetBrains_Mono'] text-[11px] tracking-[0.25em] uppercase border transition-colors duration-150";

const SiteNav: React.FC = () => {
    const [route, setRoute] = useState<string>(typeof window === 'undefined' ? '' : window.location.hash);

    useEffect(() => {
        const onHash = () => setRoute(window.location.hash);
        window.addEventListener('hashchange', onHash);
        return () => window.removeEventListener('hashchange', onHash);
    }, []);

    const isDocs = route.startsWith('#/docs');

    return (
        <nav
            className="fixed top-4 right-4 z-[100] flex items-center gap-2 pointer-events-auto"
            style={{ mixBlendMode: 'normal' }}
        >
            <a
                href="#/"
                className={`${linkBase} ${
                    !isDocs
                        ? 'text-[#020205] bg-[#00ffff] border-[#00ffff]'
                        : 'text-[#a0a8b8] bg-black/40 border-[#1f2434] hover:border-[#00ffff] hover:text-[#00ffff]'
                }`}
            >
                Story
            </a>
            <a
                href="#/docs"
                className={`${linkBase} ${
                    isDocs
                        ? 'text-[#020205] bg-[#D54DFF] border-[#D54DFF]'
                        : 'text-[#a0a8b8] bg-black/40 border-[#1f2434] hover:border-[#D54DFF] hover:text-[#D54DFF]'
                }`}
            >
                Docs
            </a>
        </nav>
    );
};

export default SiteNav;
