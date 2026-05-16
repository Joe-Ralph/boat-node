import React from 'react';
import { PALETTE } from '../engine/palette';

const CTA_LINKS = {
    pilot: 'mailto:hello@example.com?subject=Pilot%20request',
    repo: 'https://github.com/USER/REPO',
    newsletter: '#newsletter-todo',
    docs: '#/docs',
};

const buttonBase: React.CSSProperties = {
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: 12,
    textTransform: 'uppercase',
    letterSpacing: '0.18em',
    padding: '14px 26px',
    border: '1px solid transparent',
    background: 'transparent',
    cursor: 'pointer',
    transition: 'all 200ms ease',
    minWidth: 220,
    textAlign: 'center',
    display: 'inline-block',
    textDecoration: 'none',
};

const CTAPanel: React.FC = () => {
    return (
        <div
            className="relative max-w-3xl w-[90%] mx-auto"
            style={{
                background: 'rgba(5,5,8,0.7)',
                backdropFilter: 'blur(18px)',
                border: `1px solid ${PALETTE.magenta}40`,
                borderRadius: 16,
                padding: '48px 32px',
                boxShadow: `0 0 80px ${PALETTE.magenta}26`,
            }}
        >
            <div className="text-center">
                <div
                    style={{
                        fontFamily: '"JetBrains Mono", monospace',
                        fontSize: 11,
                        textTransform: 'uppercase',
                        letterSpacing: '0.32em',
                        color: PALETTE.cyan,
                        marginBottom: 14,
                    }}
                >
                    Act
                </div>
                <h2
                    style={{
                        fontFamily: 'Rajdhani, sans-serif',
                        fontSize: 'clamp(36px, 6vw, 64px)',
                        fontWeight: 700,
                        letterSpacing: '0.04em',
                        color: PALETTE.offWhite,
                        margin: 0,
                        lineHeight: 1.05,
                    }}
                >
                    The sea forgets. <span style={{ color: PALETTE.magenta }}>The mesh doesn't.</span>
                </h2>
                <p
                    style={{
                        fontFamily: 'Rajdhani, sans-serif',
                        fontSize: 18,
                        color: PALETTE.white,
                        opacity: 0.7,
                        marginTop: 18,
                        marginBottom: 36,
                    }}
                >
                    Run a pilot, read the build, or stay in the loop.
                </p>

                <div className="flex flex-col md:flex-row items-center justify-center gap-4 flex-wrap">
                    <a
                        href={CTA_LINKS.pilot}
                        style={{
                            ...buttonBase,
                            color: PALETTE.cyan,
                            borderColor: PALETTE.cyan,
                        }}
                    >
                        Run a pilot →
                    </a>
                    <a
                        href={CTA_LINKS.repo}
                        target="_blank"
                        rel="noreferrer"
                        style={{
                            ...buttonBase,
                            color: PALETTE.magenta,
                            borderColor: PALETTE.magenta,
                        }}
                    >
                        See the code ↗
                    </a>
                    <a
                        href={CTA_LINKS.newsletter}
                        style={{
                            ...buttonBase,
                            color: PALETTE.offWhite,
                            borderColor: `${PALETTE.offWhite}66`,
                        }}
                    >
                        Stay in the loop
                    </a>
                </div>

                <div style={{ marginTop: 28 }}>
                    <a
                        href={CTA_LINKS.docs}
                        style={{
                            fontFamily: '"JetBrains Mono", monospace',
                            fontSize: 11,
                            textTransform: 'uppercase',
                            letterSpacing: '0.22em',
                            color: `${PALETTE.white}99`,
                            textDecoration: 'none',
                            borderBottom: `1px solid ${PALETTE.white}33`,
                            paddingBottom: 2,
                        }}
                    >
                        Read the technical docs →
                    </a>
                </div>
            </div>
        </div>
    );
};

export default CTAPanel;
