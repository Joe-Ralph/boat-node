import React, { useEffect, useMemo, useState } from 'react';

const C = {
    bg: '#020205',
    panel: '#0a0c14',
    panelHi: '#101422',
    grid: 'rgba(120,180,255,0.06)',
    gridHi: 'rgba(120,180,255,0.14)',
    border: '#1f2434',
    text: '#fafafa',
    sub: '#a0a8b8',
    mute: '#5a6478',
    cyan: '#00ffff',
    blue: '#4488ff',
    magenta: '#D54DFF',
    green: '#00ff88',
    amber: '#ffaa33',
    red: '#ff3355',
};

const DOCS_CSS = `
.docs-root {
  background: ${C.bg};
  background-image:
    linear-gradient(${C.grid} 1px, transparent 1px),
    linear-gradient(90deg, ${C.grid} 1px, transparent 1px);
  background-size: 48px 48px;
  background-position: -1px -1px;
  color: ${C.text};
  font-family: 'Inter', sans-serif;
  min-height: 100vh;
}
.docs-display { font-family: 'Rajdhani', sans-serif; font-weight: 600; letter-spacing: 0.01em; }
.docs-mono { font-family: 'JetBrains Mono', monospace; }
.docs-kicker {
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px; letter-spacing: 0.4em; text-transform: uppercase; color: ${C.mute};
}
.docs-rule { height: 1px; background: linear-gradient(90deg, ${C.gridHi}, transparent); }
.docs-panel {
  background: ${C.panel};
  border: 1px solid ${C.border};
  position: relative;
}
.docs-panel::before, .docs-panel::after {
  content: ''; position: absolute; width: 10px; height: 10px;
  border-color: ${C.cyan}; border-style: solid;
}
.docs-panel::before { top: -1px; left: -1px; border-width: 1px 0 0 1px; }
.docs-panel::after { bottom: -1px; right: -1px; border-width: 0 1px 1px 0; }
.docs-tag {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 3px 8px; font-family: 'JetBrains Mono', monospace;
  font-size: 10px; letter-spacing: 0.2em; text-transform: uppercase;
  border: 1px solid currentColor;
}
.docs-toc a {
  display: block; padding: 6px 10px; border-left: 1px solid ${C.border};
  font-family: 'JetBrains Mono', monospace; font-size: 11px;
  color: ${C.sub}; text-decoration: none; transition: all 120ms;
}
.docs-toc a:hover { color: ${C.cyan}; border-left-color: ${C.cyan}; background: ${C.panel}; }
.docs-toc a.active { color: ${C.cyan}; border-left-color: ${C.cyan}; background: ${C.panel}; }
.docs-toc .group-label {
  font-family: 'JetBrains Mono', monospace; font-size: 9px; letter-spacing: 0.3em;
  text-transform: uppercase; color: ${C.mute}; padding: 14px 10px 6px;
}

.led {
  width: 28px; height: 28px; border-radius: 50%;
  position: relative; flex-shrink: 0;
  box-shadow: 0 0 0 1px rgba(255,255,255,0.04);
}
.led::after {
  content: ''; position: absolute; inset: -10px; border-radius: 50%;
  background: radial-gradient(circle, currentColor 0%, transparent 60%);
  opacity: 0.35; pointer-events: none;
}
@keyframes ledSolid { from,to { opacity: 1; } }
@keyframes ledOff   { from,to { opacity: 0.08; } }
@keyframes ledSlow  { 0%,100% { opacity: 0.15; } 50% { opacity: 1; } }
@keyframes ledFast  { 0%,100% { opacity: 0.1; } 50% { opacity: 1; } }
@keyframes ledTrip  {
  0%,100% { opacity: 0.08; }
  6%,14%,22% { opacity: 1; }
  10%,18%,26% { opacity: 0.08; }
}
@keyframes ledDoub  {
  0%,100% { opacity: 0.08; }
  10%,30% { opacity: 1; }
  20%,40% { opacity: 0.08; }
}
@keyframes ledBeat  {
  0%,100% { opacity: 0.2; }
  10%,30% { opacity: 1; }
  20% { opacity: 0.3; }
}
@keyframes ledBreath {
  0%,100% { opacity: 0.25; transform: scale(0.92); }
  50% { opacity: 1; transform: scale(1); }
}
@keyframes ledSingle {
  0% { opacity: 0.08; } 8% { opacity: 1; } 20% { opacity: 0.08; } 100% { opacity: 0.08; }
}
.led-solid  { animation: ledSolid  2s infinite; }
.led-off    { animation: ledOff    2s infinite; }
.led-slow   { animation: ledSlow   1.6s ease-in-out infinite; }
.led-fast   { animation: ledFast   0.35s ease-in-out infinite; }
.led-triple { animation: ledTrip   2.2s linear infinite; }
.led-double { animation: ledDoub   1.6s linear infinite; }
.led-beat   { animation: ledBeat   1.2s linear infinite; }
.led-breath { animation: ledBreath 2.4s ease-in-out infinite; }
.led-single { animation: ledSingle 3s linear infinite; }

.flow-arrow { stroke-dasharray: 6 4; animation: dash 1.4s linear infinite; }
@keyframes dash { to { stroke-dashoffset: -20; } }

.byte-cell {
  font-family: 'JetBrains Mono', monospace; font-size: 10px;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  min-width: 38px; height: 38px; border-right: 1px solid rgba(0,0,0,0.4);
  position: relative;
}
.byte-cell:last-child { border-right: none; }
.byte-cell .b-hex { font-size: 11px; font-weight: 600; }
.byte-cell .b-idx { font-size: 8px; opacity: 0.55; }
.byte-row { display: flex; border: 1px solid ${C.border}; border-radius: 2px; overflow: hidden; }
.field-label {
  font-family: 'JetBrains Mono', monospace; font-size: 9px; letter-spacing: 0.15em;
  text-transform: uppercase; padding: 6px 4px 4px; text-align: center;
}

.fsm-node {
  fill: ${C.panel}; stroke: ${C.cyan}; stroke-width: 1.2;
}
.fsm-node-label {
  font-family: 'JetBrains Mono', monospace; font-size: 11px; fill: ${C.text};
}
.fsm-edge { stroke: ${C.sub}; stroke-width: 1; fill: none; marker-end: url(#arrow); }
.fsm-edge-label { font-family: 'JetBrains Mono', monospace; font-size: 9px; fill: ${C.sub}; }

.step-num {
  width: 24px; height: 24px; border: 1px solid ${C.cyan}; color: ${C.cyan};
  display: inline-flex; align-items: center; justify-content: center;
  font-family: 'JetBrains Mono', monospace; font-size: 11px; flex-shrink: 0;
}

.docs-link { color: ${C.cyan}; text-decoration: none; border-bottom: 1px dotted ${C.cyan}; }
.docs-link:hover { color: ${C.magenta}; border-bottom-color: ${C.magenta}; }
`;

// ===========================================================================
// Primitives
// ===========================================================================

const Kicker: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <div className="docs-kicker">{children}</div>
);

const Section: React.FC<{
    id: string;
    kicker: string;
    title: string;
    lead?: string;
    children: React.ReactNode;
}> = ({ id, kicker, title, lead, children }) => (
    <section id={id} className="py-20 scroll-mt-24">
        <Kicker>{kicker}</Kicker>
        <h2 className="docs-display text-4xl md:text-5xl mt-2 mb-4 text-white">{title}</h2>
        {lead && <p className="text-[#a0a8b8] text-base md:text-lg max-w-3xl mb-10 leading-relaxed">{lead}</p>}
        <div className="docs-rule mb-10" />
        {children}
    </section>
);

const Callout: React.FC<{
    tone?: 'cyan' | 'magenta' | 'amber' | 'green' | 'red';
    label: string;
    children: React.ReactNode;
}> = ({ tone = 'cyan', label, children }) => {
    const color = tone === 'magenta' ? C.magenta
        : tone === 'amber' ? C.amber
        : tone === 'green' ? C.green
        : tone === 'red' ? C.red
        : C.cyan;
    return (
        <aside
            className="my-6 p-4 border-l-2"
            style={{ borderColor: color, background: 'rgba(255,255,255,0.015)' }}
        >
            <div className="docs-mono text-[10px] tracking-[0.3em] uppercase mb-1.5" style={{ color }}>
                {label}
            </div>
            <div className="text-[#cfd4dd] text-sm leading-relaxed">{children}</div>
        </aside>
    );
};

const KV: React.FC<{ k: string; v: React.ReactNode; mono?: boolean }> = ({ k, v, mono }) => (
    <div className="flex items-baseline justify-between gap-4 py-2 border-b border-[#1f2434]">
        <span className="text-[#5a6478] text-xs uppercase tracking-[0.18em]">{k}</span>
        <span className={`text-right ${mono ? 'docs-mono text-xs' : 'text-sm'} text-white`}>{v}</span>
    </div>
);

const Code: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <pre className="docs-panel p-4 my-4 overflow-x-auto text-[12px] leading-relaxed docs-mono text-[#cfd4dd]">
        <code>{children}</code>
    </pre>
);

// ===========================================================================
// Byte Grid (packet visualizer)
// ===========================================================================

type ByteField = {
    name: string;
    size: number;
    color: string;
    note?: string;
};

const ByteGrid: React.FC<{ fields: ByteField[]; title: string; total: number; hmac?: boolean }> = ({
    fields, title, total, hmac
}) => {
    let idx = 0;
    return (
        <div className="my-6">
            <div className="flex items-baseline justify-between mb-2">
                <h4 className="docs-mono text-sm text-white">{title}</h4>
                <span className="docs-mono text-[10px] text-[#5a6478]">
                    {total} BYTES {hmac && '· HMAC-SIGNED'}
                </span>
            </div>
            <div className="docs-panel p-3">
                <div className="overflow-x-auto pb-1">
                    <div className="byte-row" style={{ minWidth: `${total * 38}px` }}>
                        {fields.map((f, i) => {
                            const cells = [];
                            for (let b = 0; b < f.size; b++) {
                                cells.push(
                                    <div
                                        key={`${i}-${b}`}
                                        className="byte-cell"
                                        style={{ background: f.color, color: '#020205' }}
                                        title={f.name}
                                    >
                                        <span className="b-hex">·</span>
                                        <span className="b-idx">{idx++}</span>
                                    </div>
                                );
                            }
                            return cells;
                        })}
                    </div>
                    <div className="flex" style={{ minWidth: `${total * 38}px` }}>
                        {fields.map((f, i) => (
                            <div
                                key={i}
                                className="field-label"
                                style={{
                                    width: `${f.size * 38}px`,
                                    color: f.color,
                                    borderRight: i < fields.length - 1 ? `1px dashed ${C.border}` : 'none',
                                }}
                            >
                                <div className="font-semibold">{f.name}</div>
                                <div className="text-[8px] text-[#5a6478] mt-0.5">{f.size} B{f.note ? ` · ${f.note}` : ''}</div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>
        </div>
    );
};

// ===========================================================================
// Architecture diagram (full SVG)
// ===========================================================================

const ArchDiagram: React.FC = () => (
    <div className="docs-panel p-6 my-4 overflow-x-auto">
        <svg viewBox="0 0 940 540" className="w-full h-auto" style={{ minWidth: '720px' }}>
            <defs>
                <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                    <path d="M0,0 L10,5 L0,10 z" fill={C.sub} />
                </marker>
                <marker id="arrow-cyan" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                    <path d="M0,0 L10,5 L0,10 z" fill={C.cyan} />
                </marker>
                <marker id="arrow-magenta" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
                    <path d="M0,0 L10,5 L0,10 z" fill={C.magenta} />
                </marker>
                <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                    <path d="M 40 0 L 0 0 0 40" fill="none" stroke={C.grid} strokeWidth="0.5" />
                </pattern>
            </defs>
            <rect width="940" height="540" fill={C.panel} />
            <rect width="940" height="540" fill="url(#grid)" />

            {/* Mesh cloud (left) */}
            <text x="40" y="36" className="docs-mono" fill={C.mute} fontSize="10" letterSpacing="2">
                MESH RADIO 865.2 MHz · SF9 · BW125
            </text>

            {/* Originator boat */}
            <g transform="translate(80,200)">
                <rect x="0" y="0" width="120" height="80" fill={C.bg} stroke={C.magenta} />
                <text x="60" y="22" textAnchor="middle" fill={C.magenta} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">ORIGINATOR</text>
                <text x="60" y="44" textAnchor="middle" fill={C.text} fontSize="12" fontFamily="Rajdhani" fontWeight="600">BOAT B-021</text>
                <text x="60" y="62" textAnchor="middle" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">src=0x07F4</text>
                <circle cx="60" cy="0" r="3" fill={C.magenta}>
                    <animate attributeName="r" values="3;9;3" dur="1.4s" repeatCount="indefinite" />
                    <animate attributeName="opacity" values="1;0;1" dur="1.4s" repeatCount="indefinite" />
                </circle>
            </g>

            {/* Neighbor boats */}
            <g transform="translate(260,80)">
                <rect x="0" y="0" width="120" height="60" fill={C.bg} stroke={C.border} />
                <text x="60" y="20" textAnchor="middle" fill={C.sub} fontSize="10" fontFamily="JetBrains Mono">NEIGHBOR</text>
                <text x="60" y="40" textAnchor="middle" fill={C.text} fontSize="11" fontFamily="Rajdhani">BOAT B-013</text>
                <text x="60" y="52" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">forward · hops=1</text>
            </g>
            <g transform="translate(260,320)">
                <rect x="0" y="0" width="120" height="60" fill={C.bg} stroke={C.border} />
                <text x="60" y="20" textAnchor="middle" fill={C.sub} fontSize="10" fontFamily="JetBrains Mono">NEIGHBOR</text>
                <text x="60" y="40" textAnchor="middle" fill={C.text} fontSize="11" fontFamily="Rajdhani">BOAT B-118</text>
                <text x="60" y="52" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">suppressed · K=2</text>
            </g>

            {/* Gateway-class boat */}
            <g transform="translate(450,200)">
                <rect x="0" y="0" width="140" height="80" fill={C.bg} stroke={C.cyan} strokeWidth="1.5" />
                <text x="70" y="22" textAnchor="middle" fill={C.cyan} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">GATEWAY-CLASS</text>
                <text x="70" y="44" textAnchor="middle" fill={C.text} fontSize="12" fontFamily="Rajdhani" fontWeight="600">BOAT B-007</text>
                <text x="70" y="62" textAnchor="middle" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">mesh ⇄ LoRaWAN</text>
            </g>

            {/* LoRaWAN tower */}
            <g transform="translate(680,180)">
                <polygon points="20,80 0,100 40,100" fill="none" stroke={C.cyan} />
                <line x1="20" y1="0" x2="20" y2="100" stroke={C.cyan} />
                <line x1="20" y1="20" x2="6" y2="40" stroke={C.cyan} />
                <line x1="20" y1="20" x2="34" y2="40" stroke={C.cyan} />
                <circle cx="20" cy="10" r="3" fill={C.cyan}>
                    <animate attributeName="opacity" values="1;0.2;1" dur="2s" repeatCount="indefinite" />
                </circle>
                <text x="20" y="120" textAnchor="middle" fill={C.cyan} fontSize="9" fontFamily="JetBrains Mono">CHIRPSTACK GW</text>
            </g>

            {/* Backend */}
            <g transform="translate(770,80)">
                <rect x="0" y="0" width="140" height="50" fill={C.bg} stroke={C.green} />
                <text x="70" y="20" textAnchor="middle" fill={C.green} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">EDGE FN</text>
                <text x="70" y="38" textAnchor="middle" fill={C.text} fontSize="11" fontFamily="Rajdhani">mesh-decoder</text>
            </g>
            <g transform="translate(770,150)">
                <rect x="0" y="0" width="140" height="50" fill={C.bg} stroke={C.green} />
                <text x="70" y="20" textAnchor="middle" fill={C.green} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">SUPABASE</text>
                <text x="70" y="38" textAnchor="middle" fill={C.text} fontSize="11" fontFamily="Rajdhani">tables + realtime</text>
            </g>

            {/* Phones */}
            <g transform="translate(770,360)">
                <rect x="0" y="0" width="60" height="100" rx="6" fill={C.bg} stroke={C.amber} />
                <rect x="6" y="10" width="48" height="68" fill={C.panelHi} />
                <text x="30" y="42" textAnchor="middle" fill={C.amber} fontSize="9" fontFamily="JetBrains Mono">OWNER</text>
                <text x="30" y="58" textAnchor="middle" fill={C.text} fontSize="9" fontFamily="JetBrains Mono">CallKit</text>
                <circle cx="30" cy="88" r="3" fill={C.amber} />
            </g>
            <g transform="translate(850,360)">
                <rect x="0" y="0" width="60" height="100" rx="6" fill={C.bg} stroke={C.amber} />
                <rect x="6" y="10" width="48" height="68" fill={C.panelHi} />
                <text x="30" y="42" textAnchor="middle" fill={C.amber} fontSize="9" fontFamily="JetBrains Mono">CREW</text>
                <text x="30" y="58" textAnchor="middle" fill={C.text} fontSize="9" fontFamily="JetBrains Mono">BLE</text>
                <circle cx="30" cy="88" r="3" fill={C.amber} />
            </g>

            {/* Admin dashboard */}
            <g transform="translate(450,420)">
                <rect x="0" y="0" width="160" height="70" fill={C.bg} stroke={C.sub} />
                <text x="80" y="22" textAnchor="middle" fill={C.sub} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">ADMIN</text>
                <text x="80" y="42" textAnchor="middle" fill={C.text} fontSize="11" fontFamily="Rajdhani">Land Dispatch UI</text>
                <text x="80" y="58" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">map · timeline · roster</text>
            </g>

            {/* Mesh flood arrows */}
            <path d="M 200 230 L 260 110" className="flow-arrow" stroke={C.magenta} strokeWidth="1.5" fill="none" markerEnd="url(#arrow-magenta)" />
            <path d="M 200 250 L 260 350" className="flow-arrow" stroke={C.magenta} strokeWidth="1.5" fill="none" markerEnd="url(#arrow-magenta)" />
            <path d="M 200 240 L 450 235" className="flow-arrow" stroke={C.magenta} strokeWidth="1.5" fill="none" markerEnd="url(#arrow-magenta)" />
            <path d="M 380 110 L 450 220" stroke={C.sub} strokeWidth="1" fill="none" strokeDasharray="2 3" />
            <path d="M 380 350 L 450 260" stroke={C.sub} strokeWidth="1" fill="none" strokeDasharray="2 3" />

            {/* LoRaWAN uplink */}
            <path d="M 590 240 L 690 220" className="flow-arrow" stroke={C.cyan} strokeWidth="1.5" fill="none" markerEnd="url(#arrow-cyan)" />
            <text x="630" y="215" fill={C.cyan} fontSize="9" fontFamily="JetBrains Mono">LoRaWAN uplink</text>

            {/* GW → backend webhook */}
            <path d="M 720 180 L 770 110" stroke={C.green} strokeWidth="1.2" fill="none" markerEnd="url(#arrow)" />
            <text x="710" y="155" fill={C.green} fontSize="9" fontFamily="JetBrains Mono">HTTP</text>

            {/* Edge fn → DB */}
            <path d="M 840 130 L 840 150" stroke={C.green} strokeWidth="1.2" fill="none" markerEnd="url(#arrow)" />

            {/* Realtime → phones */}
            <path d="M 840 200 L 800 360" stroke={C.amber} strokeWidth="1.2" fill="none" strokeDasharray="3 3" markerEnd="url(#arrow)" />
            <path d="M 880 200 L 880 360" stroke={C.amber} strokeWidth="1.2" fill="none" strokeDasharray="3 3" markerEnd="url(#arrow)" />
            <text x="780" y="290" fill={C.amber} fontSize="9" fontFamily="JetBrains Mono">realtime</text>

            {/* DB → admin */}
            <path d="M 770 200 L 530 420" stroke={C.sub} strokeWidth="1" fill="none" strokeDasharray="3 3" markerEnd="url(#arrow)" />

            {/* ACK return path */}
            <path d="M 690 260 L 590 260" stroke={C.green} strokeWidth="1.2" fill="none" strokeDasharray="2 3" markerEnd="url(#arrow)" />
            <path d="M 450 250 L 200 270" stroke={C.green} strokeWidth="1.2" fill="none" strokeDasharray="2 3" markerEnd="url(#arrow)" />
            <text x="320" y="285" fill={C.green} fontSize="9" fontFamily="JetBrains Mono">ACK (HMAC-signed, flood)</text>

            {/* Legend */}
            <g transform="translate(40,485)">
                <text x="0" y="0" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono" letterSpacing="2">LEGEND</text>
                <line x1="0" y1="14" x2="20" y2="14" stroke={C.magenta} strokeWidth="1.5" strokeDasharray="6 4" />
                <text x="26" y="18" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">SOS mesh flood</text>
                <line x1="140" y1="14" x2="160" y2="14" stroke={C.cyan} strokeWidth="1.5" strokeDasharray="6 4" />
                <text x="166" y="18" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">LoRaWAN</text>
                <line x1="260" y1="14" x2="280" y2="14" stroke={C.green} strokeWidth="1.2" strokeDasharray="2 3" />
                <text x="286" y="18" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">ACK return</text>
                <line x1="380" y1="14" x2="400" y2="14" stroke={C.amber} strokeWidth="1.2" strokeDasharray="3 3" />
                <text x="406" y="18" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">realtime push</text>
            </g>
        </svg>
    </div>
);

// ===========================================================================
// Signal flow (swim-lane sequence diagram)
// ===========================================================================

type FlowStep = { from: string; to: string; label: string; color?: string; note?: string };

// One-row helpers for the new sequence diagram.
const ArrowSegment: React.FC<{ tone: string; rightward: boolean }> = ({ tone, rightward }) => (
    <svg viewBox="0 0 100 12" preserveAspectRatio="none"
        className="w-full" style={{ height: 12, display: 'block' }}>
        {rightward ? (
            <>
                <circle cx="2" cy="6" r="2.5" fill={tone} />
                <line x1="4" y1="6" x2="92" y2="6" stroke={tone} strokeWidth="1.6" />
                <polygon points="92,2 100,6 92,10" fill={tone} />
            </>
        ) : (
            <>
                <polygon points="8,2 0,6 8,10" fill={tone} />
                <line x1="8" y1="6" x2="96" y2="6" stroke={tone} strokeWidth="1.6" />
                <circle cx="98" cy="6" r="2.5" fill={tone} />
            </>
        )}
    </svg>
);

const SelfLoop: React.FC<{ tone: string; label: string }> = ({ tone, label }) => (
    <div className="flex items-center gap-2.5 py-2 px-2 max-w-full">
        <svg viewBox="0 0 28 28" width="26" height="26" style={{ flexShrink: 0 }}>
            <circle cx="14" cy="14" r="3" fill={tone} />
            <path d="M 14 7 A 7 7 0 1 1 7 14" stroke={tone} strokeWidth="1.6" fill="none" />
            <polygon points="4,11 8,15 11,11" fill={tone} />
        </svg>
        <div className="docs-mono text-[11px] px-2.5 py-1 leading-tight"
            style={{ background: C.bg, border: `1px solid ${tone}55`, color: C.text }}>
            {label}
        </div>
    </div>
);

const SwimLane: React.FC<{
    lanes: string[];
    steps: FlowStep[];
    title: string;
    height?: number;     // legacy; ignored
}> = ({ lanes, steps, title }) => {
    const cols = `56px repeat(${lanes.length}, minmax(140px, 1fr)) 240px`;
    const minPx = 56 + 240 + lanes.length * 150;

    return (
        <div className="docs-panel my-6 overflow-x-auto">
            <div className="px-5 py-3 border-b border-[#1f2434] flex items-center justify-between">
                <span className="docs-mono text-xs text-white tracking-[0.2em]">{title}</span>
                <span className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478]">
                    {steps.length} steps · {lanes.length} actors
                </span>
            </div>

            {/* Lane header */}
            <div className="grid bg-[#0a0c14]" style={{ gridTemplateColumns: cols, minWidth: minPx }}>
                <div className="border-b border-[#1f2434]" />
                {lanes.map((l) => (
                    <div key={l} className="border-b border-[#1f2434] py-3 text-center">
                        <div className="inline-block px-3 py-1 docs-mono text-[10px] tracking-[0.3em] uppercase"
                            style={{ background: C.panelHi, color: C.cyan, border: `1px solid ${C.border}` }}>
                            {l}
                        </div>
                    </div>
                ))}
                <div className="border-b border-l border-[#1f2434] py-3 px-4 text-right docs-mono text-[9px] tracking-[0.3em] uppercase text-[#5a6478]">
                    notes
                </div>
            </div>

            {/* Steps */}
            <div className="relative" style={{ minWidth: minPx }}>
                {/* Lifelines drawn as full-height vertical dashed rules */}
                <div className="absolute inset-0 grid pointer-events-none" style={{ gridTemplateColumns: cols }}>
                    <div />
                    {lanes.map((_, i) => (
                        <div key={i} className="flex justify-center">
                            <div className="w-px h-full"
                                style={{ background: `repeating-linear-gradient(to bottom, ${C.border} 0 4px, transparent 4px 8px)` }} />
                        </div>
                    ))}
                    <div />
                </div>

                {steps.map((s, i) => {
                    const fromIdx = lanes.indexOf(s.from);
                    const toIdx = lanes.indexOf(s.to);
                    const tone = s.color || C.cyan;
                    const isSelf = fromIdx === toIdx;
                    const leftIdx = Math.min(fromIdx, toIdx);
                    const rightIdx = Math.max(fromIdx, toIdx);
                    const rightward = toIdx > fromIdx;
                    const stripe = i % 2 === 1 ? 'rgba(255,255,255,0.015)' : 'transparent';

                    return (
                        <div key={i} className="relative grid items-stretch border-t border-[#1f2434]"
                            style={{ gridTemplateColumns: cols, minHeight: 72, background: stripe }}>
                            {/* Step number gutter */}
                            <div className="flex items-center justify-center">
                                <div className="docs-mono flex items-center justify-center"
                                    style={{
                                        width: 30, height: 30, border: `1px solid ${tone}`, color: tone,
                                        fontSize: 12, background: C.bg,
                                    }}>
                                    {i + 1}
                                </div>
                            </div>

                            {isSelf ? (
                                lanes.map((_, li) => (
                                    <div key={li} className="flex items-center justify-center px-1">
                                        {li === fromIdx ? <SelfLoop tone={tone} label={s.label} /> : null}
                                    </div>
                                ))
                            ) : (
                                <>
                                    {Array.from({ length: leftIdx }, (_, k) => <div key={`l${k}`} />)}
                                    <div className="relative flex flex-col items-center justify-center px-3 py-3"
                                        style={{ gridColumn: `span ${rightIdx - leftIdx + 1}` }}>
                                        <div className="docs-mono text-[11px] mb-2 px-3 py-1 leading-tight text-center max-w-full"
                                            style={{
                                                background: C.bg, color: C.text,
                                                border: `1px solid ${tone}66`,
                                                boxShadow: `0 0 0 3px ${C.bg}`,   // halo over the lifeline
                                            }}>
                                            {s.label}
                                        </div>
                                        <div className="w-full">
                                            <ArrowSegment tone={tone} rightward={rightward} />
                                        </div>
                                    </div>
                                    {Array.from({ length: lanes.length - 1 - rightIdx }, (_, k) => <div key={`r${k}`} />)}
                                </>
                            )}

                            <div className="border-l border-[#1f2434] px-4 py-2 flex items-center">
                                <span className="docs-mono text-[10px] leading-snug" style={{ color: C.sub }}>
                                    {s.note || ''}
                                </span>
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
};

// ===========================================================================
// LED reference
// ===========================================================================

type LedDef = {
    color: string;
    pattern: 'solid' | 'off' | 'slow' | 'fast' | 'triple' | 'double' | 'beat' | 'breath' | 'single';
    name: string;
    condition: string;
    meaning: string;
    user: string;
};

const LED_PATTERNS: LedDef[] = [
    { color: C.cyan, pattern: 'breath', name: 'Cyan breathing', condition: 'Mesh idle listen, GPS fix, no SOS', meaning: 'Healthy idle. Radio is in CAD listen, GPS locked, battery OK.', user: 'Normal. Nothing to do.' },
    { color: C.cyan, pattern: 'single', name: 'Cyan single flick', condition: 'Mesh TX in progress', meaning: 'Boat is broadcasting its routine POS frame or forwarding a mesh packet.', user: 'Normal. Visible every ~120 s during a journey.' },
    { color: C.blue, pattern: 'solid', name: 'Blue solid', condition: 'Owner phone BLE connected', meaning: 'Authenticated owner session active. Config writes allowed.', user: 'Expected when owner phone is near.' },
    { color: C.blue, pattern: 'slow', name: 'Blue slow pulse', condition: 'Crew phone BLE connected', meaning: 'Authenticated crew session active. SOS + journey allowed, no config.', user: 'Expected when a crew member is paired and onboard.' },
    { color: C.amber, pattern: 'slow', name: 'Amber slow pulse', condition: 'GPS searching / no fix', meaning: 'NEO-6M has not acquired a 3D fix. Outgoing frames send lat=0, lon=0.', user: 'Wait 30–90 s under open sky. If persistent, check antenna.' },
    { color: C.amber, pattern: 'double', name: 'Amber double-blink', condition: 'LoRaWAN TX in progress', meaning: 'LMIC owns the radio. Mesh listen paused for ~6 s while RX1/RX2 windows close.', user: 'Brief and routine.' },
    { color: C.magenta, pattern: 'breath', name: 'Magenta breathing', condition: 'BLE pairing mode', meaning: 'Device is unpaired or just factory-reset. SoftAP/BLE waiting for owner phone.', user: 'Open the BoatNode app and run pair flow.' },
    { color: C.red, pattern: 'fast', name: 'Red fast pulse', condition: 'SOS ACTIVE', meaning: 'Local SOS state machine is firing. Mesh broadcast running with retry backoff.', user: 'Emergency in progress. Cancel only if false alarm (button long-press or app).' },
    { color: C.green, pattern: 'slow', name: 'Green slow pulse', condition: 'SOS ACKED · received', meaning: 'Backend received the SOS over a gateway and HMAC-signed an ACK back through mesh.', user: 'Land has been notified. Stand by.' },
    { color: C.green, pattern: 'solid', name: 'Green solid', condition: 'SOS resolved or false-alarm', meaning: 'Backend marked the incident closed. State machine holds for 5 min then returns to IDLE.', user: 'Help is wrapping up or signal was cleared.' },
    { color: C.red, pattern: 'solid', name: 'Red solid', condition: 'Battery <10 % mid-SOS', meaning: 'One final SOS attempt budgeted. POS broadcasts halted. Mesh listen still on.', user: 'Critical. Charge or swap cells if possible.' },
    { color: C.red, pattern: 'triple', name: 'Red triple-blink', condition: 'RFM95 init fail', meaning: 'Radio chip did not respond on boot. Firmware retries 3× then reboots.', user: 'Check antenna seating and SPI wiring. Persistent fail = service.' },
    { color: C.amber, pattern: 'triple', name: 'Amber triple-blink', condition: 'NVS / storage fail', meaning: 'Preferences write failed. Pairing or sequence number may not survive reboot.', user: 'Power-cycle. If it repeats, flash may need replacement.' },
    { color: C.red, pattern: 'double', name: 'Red double-blink', condition: 'Critical battery <5 %', meaning: 'Hard shutdown imminent. NVS last_shutdown_reason=LOW_BATT will be written.', user: 'Charge immediately.' },
    { color: '#ffffff', pattern: 'beat', name: 'White heartbeat', condition: 'Boot self-test passing', meaning: 'Cold-boot sequence: NVS read OK, GPS UART responsive, RFM95 ID matches.', user: 'Visible for ~2 s after power-on.' },
    { color: '#ffffff', pattern: 'off', name: 'Off / dark', condition: 'SOS canceled · or unit unpowered', meaning: 'Either SOS was acknowledged and aged out, or there is no power.', user: 'If a journey is supposedly active and LED is dark, suspect a brown-out.' },
];

const LedCard: React.FC<LedDef> = ({ color, pattern, name, condition, meaning, user }) => (
    <div className="docs-panel p-5">
        <div className="flex items-center gap-4 mb-4">
            <div className={`led led-${pattern}`} style={{ background: color, color }} />
            <div>
                <div className="docs-display text-lg text-white">{name}</div>
                <div className="docs-mono text-[10px] text-[#5a6478] tracking-[0.2em] uppercase mt-0.5">{condition}</div>
            </div>
        </div>
        <p className="text-[#cfd4dd] text-sm leading-relaxed mb-3">{meaning}</p>
        <div className="border-t border-[#1f2434] pt-3">
            <span className="docs-mono text-[9px] tracking-[0.3em] uppercase text-[#5a6478]">User action · </span>
            <span className="text-[#a0a8b8] text-xs">{user}</span>
        </div>
    </div>
);

// ===========================================================================
// FSM diagram
// ===========================================================================

type FsmNode = { id: string; x: number; y: number; w?: number; h?: number; color?: string };
type FsmEdge = { from: string; to: string; label: string; curve?: number };

const FSM: React.FC<{ title: string; nodes: FsmNode[]; edges: FsmEdge[]; width?: number; height?: number }> = ({
    title, nodes, edges, width = 700, height = 320
}) => {
    const nodeMap = useMemo(() => Object.fromEntries(nodes.map(n => [n.id, n])), [nodes]);
    return (
        <div className="docs-panel p-6 my-4 overflow-x-auto">
            <div className="docs-mono text-xs text-white mb-4">{title}</div>
            <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-auto" style={{ minWidth: '640px' }}>
                <defs>
                    <marker id="fsm-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
                        <path d="M0,0 L10,5 L0,10 z" fill={C.sub} />
                    </marker>
                </defs>
                {edges.map((e, i) => {
                    const a = nodeMap[e.from], b = nodeMap[e.to];
                    if (!a || !b) return null;
                    const aw = a.w || 110, ah = a.h || 40, bw = b.w || 110, bh = b.h || 40;
                    const ax = a.x + aw / 2, ay = a.y + ah / 2;
                    const bx = b.x + bw / 2, by = b.y + bh / 2;
                    const curve = e.curve || 0;
                    const mx = (ax + bx) / 2 + curve;
                    const my = (ay + by) / 2 - Math.abs(curve) * 0.5;
                    const isSelf = e.from === e.to;
                    if (isSelf) {
                        return (
                            <g key={i}>
                                <path d={`M ${a.x + aw - 6} ${a.y + 8} q 30 -16 0 28`}
                                    stroke={C.sub} strokeWidth="1" fill="none" markerEnd="url(#fsm-arrow)" />
                                <text x={a.x + aw + 14} y={a.y + 20} fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">{e.label}</text>
                            </g>
                        );
                    }
                    return (
                        <g key={i}>
                            <path d={`M ${ax} ${ay} Q ${mx} ${my} ${bx} ${by}`}
                                className="fsm-edge" markerEnd="url(#fsm-arrow)" />
                            <text x={mx} y={my - 4} textAnchor="middle" className="fsm-edge-label">{e.label}</text>
                        </g>
                    );
                })}
                {nodes.map((n, i) => {
                    const w = n.w || 110, h = n.h || 40;
                    const color = n.color || C.cyan;
                    return (
                        <g key={i}>
                            <rect x={n.x} y={n.y} width={w} height={h} rx={h / 2}
                                fill={C.panel} stroke={color} strokeWidth="1.2" />
                            <text x={n.x + w / 2} y={n.y + h / 2 + 4} textAnchor="middle"
                                fill={C.text} fontSize="11" fontFamily="JetBrains Mono">{n.id}</text>
                        </g>
                    );
                })}
            </svg>
        </div>
    );
};

// ===========================================================================
// TOC
// ===========================================================================

const TOC_ITEMS: { group: string; items: { id: string; label: string }[] }[] = [
    {
        group: '00 — Orient',
        items: [
            { id: 'overview', label: 'System Overview' },
            { id: 'who', label: 'Who Uses This' },
            { id: 'stack', label: 'Stack at a Glance' },
        ],
    },
    {
        group: '01 — Hardware',
        items: [
            { id: 'arch', label: 'Architecture' },
            { id: 'board', label: 'Board Anatomy' },
            { id: 'radio', label: 'Two Radio Roles' },
        ],
    },
    {
        group: '02 — Protocol',
        items: [
            { id: 'packets', label: 'Packet Formats' },
            { id: 'flows', label: 'Signal Walkthroughs' },
            { id: 'fsm', label: 'State Machines' },
        ],
    },
    {
        group: '03 — UX',
        items: [
            { id: 'led', label: 'LED Status Reference' },
            { id: 'ble', label: 'BLE Auth & Crew' },
        ],
    },
    {
        group: '04 — Backend',
        items: [
            { id: 'security', label: 'Identity & Security' },
            { id: 'backend', label: 'Backend Integration' },
        ],
    },
    {
        group: '05 — Reference',
        items: [
            { id: 'tunables', label: 'Tunables & Limits' },
            { id: 'glossary', label: 'Glossary' },
        ],
    },
];

const TableOfContents: React.FC<{ active: string }> = ({ active }) => (
    <nav className="docs-toc sticky top-24 hidden lg:block">
        <div className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478] mb-3">Contents</div>
        {TOC_ITEMS.map((group) => (
            <div key={group.group}>
                <div className="group-label">{group.group}</div>
                {group.items.map((it) => (
                    <a
                        key={it.id}
                        href={`#/docs#${it.id}`}
                        className={active === it.id ? 'active' : ''}
                        onClick={(e) => {
                            e.preventDefault();
                            const el = document.getElementById(it.id);
                            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
                        }}
                    >
                        {it.label}
                    </a>
                ))}
            </div>
        ))}
    </nav>
);

// ===========================================================================
// Top hero
// ===========================================================================

const Hero: React.FC = () => (
    <header className="pt-32 pb-20 border-b border-[#1f2434]">
        <div className="flex items-center gap-2 mb-6">
            <span className="docs-tag" style={{ color: C.cyan }}>v2 · 2026-05-13</span>
            <span className="docs-tag" style={{ color: C.green }}>spec approved</span>
            <span className="docs-tag" style={{ color: C.magenta }}>fisherman safety</span>
        </div>
        <h1 className="docs-display text-[64px] md:text-[96px] leading-[0.95] tracking-tight text-white">
            BoatNode<br />
            <span style={{ color: C.cyan }}>Technical</span> Documentation
        </h1>
        <p className="text-[#cfd4dd] text-lg md:text-xl max-w-3xl mt-6 leading-relaxed">
            How a low-cost ESP32 buoy, a private LoRa mesh, a LoRaWAN gateway, and a Supabase backend
            cooperate to deliver an emergency SOS from a boat out of cellular range to a land
            dispatcher — and acknowledge it back to the fisherman — in under thirty seconds.
        </p>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-px mt-12 bg-[#1f2434]">
            {[
                { k: 'SOS Δt', v: '≤ 30 s', sub: 'gateway delivery' },
                { k: 'Battery', v: '7 days', sub: '2× 18650, typical' },
                { k: 'Range', v: '0.5 – 5 km', sub: 'inter-boat, SF9' },
                { k: 'Density', v: '10 – 100', sub: 'boats / fleet' },
            ].map((s) => (
                <div key={s.k} className="bg-[#020205] p-6">
                    <div className="docs-kicker">{s.k}</div>
                    <div className="docs-display text-3xl mt-2" style={{ color: C.cyan }}>{s.v}</div>
                    <div className="text-[#5a6478] text-xs mt-1">{s.sub}</div>
                </div>
            ))}
        </div>
    </header>
);

// ===========================================================================
// Docs root
// ===========================================================================

const Docs: React.FC = () => {
    const [active, setActive] = useState('overview');

    useEffect(() => {
        const ids = TOC_ITEMS.flatMap(g => g.items.map(i => i.id));
        const observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    if (entry.isIntersecting) setActive(entry.target.id);
                });
            },
            { rootMargin: '-30% 0px -60% 0px' }
        );
        ids.forEach((id) => {
            const el = document.getElementById(id);
            if (el) observer.observe(el);
        });
        return () => observer.disconnect();
    }, []);

    return (
        <div className="docs-root">
            <style>{DOCS_CSS}</style>
            <div className="max-w-[1400px] mx-auto px-6 md:px-10">
                <Hero />

                <div className="grid grid-cols-1 lg:grid-cols-[220px_1fr] gap-12 pb-32">
                    <aside className="pt-20">
                        <TableOfContents active={active} />
                    </aside>
                    <main className="min-w-0">

                        {/* ==== Overview ==== */}
                        <Section
                            id="overview"
                            kicker="00 / Orient"
                            title="System Overview"
                            lead="BoatNode is a hardware + software system that gives small fishing boats a panic button that works beyond the reach of cellular towers. Every boat carries an inexpensive node; nodes talk to each other over private long-range radio and reach the cloud through any single boat that is still in gateway range."
                        >
                            <p className="text-[#cfd4dd] text-base leading-relaxed mb-6 max-w-3xl">
                                The earlier production firmware was LoRaWAN-only — a boat outside ChirpStack
                                gateway range simply could not reach the backend. The v2 design extends each
                                node to act as a <strong style={{ color: C.cyan }}>hybrid LoRaWAN/mesh device</strong>:
                                a single RFM95 radio is time-shared between LMIC (regulated, public) and a private
                                SX1276 P2P mesh (peer-to-peer, fleet-private). Boats out of gateway range flood
                                SOS+position over the mesh; the first boat still in gateway range relays the
                                packet upward to ChirpStack. The backend HMAC-signs an acknowledgement that
                                flows back through the mesh to the originator, closing the
                                <em> "did my SOS reach land?"</em> loop the fisherman cares about.
                            </p>

                            <div className="grid md:grid-cols-3 gap-px bg-[#1f2434]">
                                {[
                                    { t: 'Hardware', l: 'ESP32 + RFM95 + NEO-6M GPS + BLE + WS2812 + 2× 18650', c: C.cyan },
                                    { t: 'Mesh radio', l: '865.2 MHz, SF9, BW125, sync 0x12, ETSI 14 dBm', c: C.magenta },
                                    { t: 'Protocol', l: 'RBSF flood, TTL=4, HMAC-SHA256/4 B, dedup ring 64', c: C.green },
                                ].map(b => (
                                    <div key={b.t} className="bg-[#020205] p-5">
                                        <div className="docs-mono text-[10px] tracking-[0.3em] uppercase" style={{ color: b.c }}>{b.t}</div>
                                        <div className="text-[#cfd4dd] text-sm mt-2 leading-relaxed">{b.l}</div>
                                    </div>
                                ))}
                            </div>

                            <Callout label="Plain-English version" tone="cyan">
                                Imagine ten fishing boats five kilometres apart. The phone in your pocket has no
                                signal. You hit the red button on the buoy. The buoy whispers your GPS over a
                                long radio to your neighbours; each neighbour repeats the whisper to its neighbours
                                until the whisper reaches a boat that is still close to shore. That boat tells
                                the cloud. The cloud whispers <em>"received"</em> back along the same chain.
                                A green light comes on in your hand within thirty seconds.
                            </Callout>
                        </Section>

                        <Section
                            id="who"
                            kicker="00 / Orient"
                            title="Who Uses This"
                            lead="Four distinct human roles touch the system. Each one cares about different surfaces."
                        >
                            <div className="grid md:grid-cols-2 gap-px bg-[#1f2434]">
                                {[
                                    { role: 'Boat owner', color: C.magenta, can: ['Pair the device', 'Rotate keys', 'Read all telemetry', 'Trigger / cancel SOS', 'Edit configuration', 'Factory reset'] },
                                    { role: 'Crew member', color: C.amber, can: ['Authenticate via BLE crew token', 'Read live status + ACKs', 'Trigger / cancel own SOS', 'Toggle journey on / off', '— cannot edit config', '— cannot rotate keys'] },
                                    { role: 'Land admin', color: C.cyan, can: ['Watch the realtime map', 'Mark SOS resolved / false-alarm', 'Coordinate rescue dispatch', 'Review timeline + audit log', 'Manage village boats', 'Trigger ACK downlinks'] },
                                    { role: 'Field engineer', color: C.green, can: ['Diagnose LED patterns', 'Read serial logs', 'Verify HMAC keys in NVS', 'Replay packet captures', 'Run bench self-tests', 'Flash firmware'] },
                                ].map(r => (
                                    <div key={r.role} className="bg-[#020205] p-6">
                                        <div className="docs-mono text-[10px] tracking-[0.3em] uppercase mb-3" style={{ color: r.color }}>{r.role}</div>
                                        <ul className="space-y-1.5">
                                            {r.can.map(c => (
                                                <li key={c} className="text-sm text-[#cfd4dd] flex items-baseline gap-2">
                                                    <span style={{ color: r.color }}>›</span>
                                                    <span>{c}</span>
                                                </li>
                                            ))}
                                        </ul>
                                    </div>
                                ))}
                            </div>
                        </Section>

                        <Section
                            id="stack"
                            kicker="00 / Orient"
                            title="Stack at a Glance"
                        >
                            <div className="docs-panel p-6">
                                <KV k="Firmware" v="PlatformIO · ESP32 (denky32) · Arduino · LMIC + RadioLib" />
                                <KV k="App" v="Flutter (Dart) · BLE · supabase_flutter · flutter_background_service" />
                                <KV k="Admin" v="Next.js 16 · React 19 · Supabase SSR · Leaflet" />
                                <KV k="Backend" v="Supabase Postgres · RLS · Edge Functions · realtime channels" />
                                <KV k="Gateway" v="ChirpStack Gateway Bridge → Network Server → HTTP integration" />
                                <KV k="Site" v="Vite · React · Three.js (this site)" />
                            </div>
                        </Section>

                        {/* ==== Architecture ==== */}
                        <Section
                            id="arch"
                            kicker="01 / Hardware"
                            title="Architecture"
                            lead="Five interacting domains. Read the diagram from left to right: a boat in distress, its mesh neighbours, a gateway-class boat that can still reach a tower, the backend, and finally the humans who see the alarm."
                        >
                            <ArchDiagram />
                            <div className="grid md:grid-cols-2 gap-6 mt-8">
                                <Callout tone="magenta" label="On-water plane">
                                    Every boat runs an identical firmware image. <em>Gateway-class</em> is not a
                                    hardware distinction — any boat that happens to be in LoRaWAN range becomes
                                    a relay for that minute. As fleets drift, the role transfers naturally.
                                </Callout>
                                <Callout tone="cyan" label="Cloud plane">
                                    ChirpStack ingests LoRaWAN uplinks and POSTs them to the Supabase Edge
                                    function <span className="docs-mono">mesh-decoder</span>, which validates
                                    HMAC, deduplicates, and writes <span className="docs-mono">sos_signals</span>.
                                    Realtime channels push the row to subscribers within ~100 ms.
                                </Callout>
                            </div>
                        </Section>

                        {/* ==== Board anatomy ==== */}
                        <Section
                            id="board"
                            kicker="01 / Hardware"
                            title="Board Anatomy"
                            lead="What's on the buoy. No exotic parts — every component is off-the-shelf and field-replaceable."
                        >
                            <div className="docs-panel p-6 my-2">
                                <svg viewBox="0 0 800 360" className="w-full h-auto">
                                    <defs>
                                        <pattern id="board-grid" width="20" height="20" patternUnits="userSpaceOnUse">
                                            <path d="M 20 0 L 0 0 0 20" fill="none" stroke={C.grid} strokeWidth="0.5" />
                                        </pattern>
                                    </defs>
                                    <rect width="800" height="360" fill={C.panel} />
                                    <rect width="800" height="360" fill="url(#board-grid)" />

                                    {/* PCB outline */}
                                    <rect x="200" y="60" width="400" height="240" fill={C.bg} stroke={C.cyan} strokeWidth="1.2" rx="8" />
                                    <text x="400" y="46" textAnchor="middle" fill={C.cyan} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="3">BOATNODE PCB</text>

                                    {/* ESP32 */}
                                    <rect x="250" y="110" width="120" height="80" fill={C.panelHi} stroke={C.cyan} />
                                    <text x="310" y="142" textAnchor="middle" fill={C.cyan} fontSize="11" fontFamily="JetBrains Mono">ESP32</text>
                                    <text x="310" y="158" textAnchor="middle" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">denky32</text>
                                    <text x="310" y="172" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">2 cores · 320 KB</text>

                                    {/* RFM95 */}
                                    <rect x="420" y="110" width="120" height="80" fill={C.panelHi} stroke={C.magenta} />
                                    <text x="480" y="142" textAnchor="middle" fill={C.magenta} fontSize="11" fontFamily="JetBrains Mono">RFM95</text>
                                    <text x="480" y="158" textAnchor="middle" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">SX1276</text>
                                    <text x="480" y="172" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">868 MHz · SPI</text>

                                    {/* GPS */}
                                    <rect x="230" y="220" width="80" height="50" fill={C.panelHi} stroke={C.green} />
                                    <text x="270" y="240" textAnchor="middle" fill={C.green} fontSize="10" fontFamily="JetBrains Mono">NEO-6M</text>
                                    <text x="270" y="256" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">UART</text>

                                    {/* LED WS2812 */}
                                    <circle cx="380" cy="245" r="14" fill={C.amber} />
                                    <circle cx="380" cy="245" r="14" fill="none" stroke={C.panelHi} strokeWidth="2" />
                                    <text x="380" y="280" textAnchor="middle" fill={C.amber} fontSize="9" fontFamily="JetBrains Mono">WS2812</text>

                                    {/* Buttons */}
                                    <circle cx="440" cy="245" r="10" fill={C.red} stroke={C.bg} strokeWidth="2" />
                                    <text x="440" y="276" textAnchor="middle" fill={C.red} fontSize="9" fontFamily="JetBrains Mono">SOS</text>
                                    <circle cx="478" cy="245" r="10" fill={C.sub} stroke={C.bg} strokeWidth="2" />
                                    <text x="478" y="276" textAnchor="middle" fill={C.sub} fontSize="9" fontFamily="JetBrains Mono">RST</text>

                                    {/* Battery */}
                                    <rect x="515" y="220" width="70" height="50" fill={C.panelHi} stroke={C.blue} />
                                    <rect x="585" y="232" width="6" height="26" fill={C.blue} />
                                    <text x="550" y="240" textAnchor="middle" fill={C.blue} fontSize="9" fontFamily="JetBrains Mono">2× 18650</text>
                                    <text x="550" y="254" textAnchor="middle" fill={C.mute} fontSize="8" fontFamily="JetBrains Mono">~7 Ah</text>

                                    {/* Antenna stub */}
                                    <line x1="540" y1="110" x2="560" y2="70" stroke={C.magenta} strokeWidth="1.5" />
                                    <line x1="555" y1="76" x2="565" y2="66" stroke={C.magenta} strokeWidth="1.5" />
                                    <text x="580" y="68" fill={C.magenta} fontSize="9" fontFamily="JetBrains Mono">868 MHz λ/4</text>

                                    {/* Callout lines & labels */}
                                    <line x1="310" y1="110" x2="80" y2="90" stroke={C.cyan} strokeDasharray="2 3" />
                                    <text x="14" y="86" fill={C.cyan} fontSize="9" fontFamily="JetBrains Mono">① MCU + BLE</text>
                                    <text x="14" y="98" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">app code, BLE GATT</text>

                                    <line x1="480" y1="110" x2="730" y2="90" stroke={C.magenta} strokeDasharray="2 3" />
                                    <text x="640" y="86" fill={C.magenta} fontSize="9" fontFamily="JetBrains Mono">② RFM95 time-shared</text>
                                    <text x="640" y="98" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">LMIC + RadioLib mesh</text>

                                    <line x1="270" y1="270" x2="80" y2="320" stroke={C.green} strokeDasharray="2 3" />
                                    <text x="14" y="320" fill={C.green} fontSize="9" fontFamily="JetBrains Mono">③ GPS</text>
                                    <text x="14" y="332" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">lat/lon + UTC time</text>

                                    <line x1="380" y1="260" x2="380" y2="330" stroke={C.amber} strokeDasharray="2 3" />
                                    <text x="380" y="346" textAnchor="middle" fill={C.amber} fontSize="9" fontFamily="JetBrains Mono">④ WS2812 status LED · the entire UI of the device</text>

                                    <line x1="550" y1="270" x2="730" y2="320" stroke={C.blue} strokeDasharray="2 3" />
                                    <text x="640" y="320" fill={C.blue} fontSize="9" fontFamily="JetBrains Mono">⑤ Cells</text>
                                    <text x="640" y="332" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">7-day budget</text>
                                </svg>
                            </div>

                            <div className="grid md:grid-cols-2 gap-4 mt-6">
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">Process model on ESP32</div>
                                    <KV k="radioTask" v="core 0 · high prio" mono />
                                    <KV k="appTask" v="core 1 · normal" mono />
                                    <KV k="shared state" v="BoatState + MeshState" mono />
                                    <KV k="mutex order" v="data → mesh" mono />
                                    <KV k="ISR" v="setMeshRxFlag (DIO0)" mono />
                                </div>
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">RAM budget</div>
                                    <KV k="Dedup cache" v="320 B" mono />
                                    <KV k="Forward queue" v="400 B" mono />
                                    <KV k="Nearby cache" v="1 080 B" mono />
                                    <KV k="LoRaWAN queue" v="400 B" mono />
                                    <KV k="SosState + mutex" v="≈ 264 B" mono />
                                    <KV k="Total mesh state" v="≈ 2.5 KB / 320 KB" mono />
                                </div>
                            </div>
                        </Section>

                        {/* ==== Two radio roles ==== */}
                        <Section
                            id="radio"
                            kicker="01 / Hardware"
                            title="Two Radio Roles, One Chip"
                            lead="The biggest constraint of v2: there is only one RFM95 on the board. It must wear two hats."
                        >
                            <p className="text-[#cfd4dd] max-w-3xl leading-relaxed mb-6">
                                The radio scheduler treats the RFM95 as a single-owner resource. Ownership is
                                held by either the LMIC stack (LoRaWAN, public network, regulated downlink
                                windows) or the RadioLib mesh stack (private peer-to-peer, free-form). Switching
                                takes about 5 ms — a retune plus a reconfigure of spreading factor, bandwidth,
                                and the LoRa sync word, which is what separates the two networks at the PHY layer.
                            </p>
                            <div className="grid md:grid-cols-2 gap-px bg-[#1f2434]">
                                <div className="bg-[#020205] p-6">
                                    <div className="docs-mono text-[10px] tracking-[0.3em] uppercase mb-3" style={{ color: C.cyan }}>LoRaWAN</div>
                                    <div className="docs-display text-2xl text-white mb-3">Regulated uplink</div>
                                    <KV k="Stack" v="LMIC (Class A)" mono />
                                    <KV k="Freq" v="865 MHz EU868" mono />
                                    <KV k="Sync word" v="0x34 (public)" mono />
                                    <KV k="Purpose" v="POS + SOS uplink, ACK downlink" mono />
                                    <KV k="Duty cycle" v="ETSI 1 %" mono />
                                    <KV k="Cost" v="2 RX windows blocking ~6 s after TX" mono />
                                </div>
                                <div className="bg-[#020205] p-6">
                                    <div className="docs-mono text-[10px] tracking-[0.3em] uppercase mb-3" style={{ color: C.magenta }}>Private mesh</div>
                                    <div className="docs-display text-2xl text-white mb-3">P2P flooding</div>
                                    <KV k="Stack" v="RadioLib" mono />
                                    <KV k="Freq" v="865.2 MHz" mono />
                                    <KV k="Sync word" v="0x12 (private)" mono />
                                    <KV k="Purpose" v="Inter-boat POS + SOS + ACK + CANCEL" mono />
                                    <KV k="Duty cycle" v="≈ 0.17 % idle (CAD listen)" mono />
                                    <KV k="Cost" v="No gateway, no airtime fee" mono />
                                </div>
                            </div>
                            <Callout tone="amber" label="Preemption rule">
                                SOS always wins. If the scheduler is about to hand off to LMIC for a routine POS
                                uplink and an SOS event arrives, the LMIC plan is dropped, the mesh broadcast
                                fires first, and then the schedule is re-evaluated. SOS <em>cannot</em> preempt
                                mid-LMIC-RX-window — it must wait ~6 s for <span className="docs-mono">EV_TXCOMPLETE</span>.
                            </Callout>
                        </Section>

                        {/* ==== Packets ==== */}
                        <Section
                            id="packets"
                            kicker="02 / Protocol"
                            title="Packet Formats"
                            lead="Every mesh frame starts with a 15-byte header and ends with a CRC. Multi-byte fields are little-endian and structs are packed — wire format is a byte-exact copy of the C struct."
                        >
                            <Callout tone="cyan" label="Header anatomy · 15 bytes, every packet">
                                <span className="docs-mono text-xs">magic (1)</span> ·
                                <span className="docs-mono text-xs"> ver (1)</span> ·
                                <span className="docs-mono text-xs"> type (1)</span> ·
                                <span className="docs-mono text-xs"> src (2)</span> ·
                                <span className="docs-mono text-xs"> dest (2)</span> ·
                                <span className="docs-mono text-xs"> seq (2)</span> ·
                                <span className="docs-mono text-xs"> hops (1)</span> ·
                                <span className="docs-mono text-xs"> ttl (1)</span> ·
                                <span className="docs-mono text-xs"> ts (4)</span>
                            </Callout>

                            <ByteGrid
                                title="MeshHeader"
                                total={15}
                                fields={[
                                    { name: 'magic', size: 1, color: '#6b7280' },
                                    { name: 'ver', size: 1, color: '#6b7280' },
                                    { name: 'type', size: 1, color: C.cyan, note: '01/02/03/04' },
                                    { name: 'src', size: 2, color: C.blue },
                                    { name: 'dest', size: 2, color: C.blue, note: '0xFFFF = bcast' },
                                    { name: 'seq', size: 2, color: C.amber },
                                    { name: 'hops', size: 1, color: C.sub },
                                    { name: 'ttl', size: 1, color: C.sub },
                                    { name: 'ts', size: 4, color: C.green, note: 'unix s, GPS' },
                                ]}
                            />

                            <ByteGrid
                                title="POS · 46 bytes · no HMAC · type=0x01"
                                total={46}
                                fields={[
                                    { name: 'MeshHeader', size: 15, color: '#6b7280' },
                                    { name: 'lat1e7', size: 4, color: C.cyan },
                                    { name: 'lon1e7', size: 4, color: C.cyan },
                                    { name: 'spd', size: 2, color: C.amber },
                                    { name: 'hdg', size: 2, color: C.amber },
                                    { name: 'batt', size: 1, color: C.green },
                                    { name: 'flags', size: 1, color: C.green, note: 'journey' },
                                    { name: 'user', size: 2, color: C.magenta },
                                    { name: 'len', size: 1, color: C.sub },
                                    { name: 'name', size: 12, color: C.blue, note: 'utf-8' },
                                    { name: 'crc', size: 2, color: '#444' },
                                ]}
                            />

                            <ByteGrid
                                title="SOS · 36 bytes · HMAC-signed · type=0x02"
                                total={36}
                                hmac
                                fields={[
                                    { name: 'MeshHeader', size: 15, color: '#6b7280' },
                                    { name: 'lat1e7', size: 4, color: C.cyan },
                                    { name: 'lon1e7', size: 4, color: C.cyan },
                                    { name: 'spd', size: 2, color: C.amber },
                                    { name: 'hdg', size: 2, color: C.amber },
                                    { name: 'batt', size: 1, color: C.green },
                                    { name: 'reason', size: 1, color: C.red, note: 'manual/MoB/…' },
                                    { name: 'user_id', size: 2, color: C.magenta },
                                    { name: 'hmac', size: 4, color: C.magenta, note: 'SHA256[:4]' },
                                    { name: 'crc', size: 2, color: '#444' },
                                ]}
                            />

                            <ByteGrid
                                title="ACK · 25 bytes · HMAC-signed · type=0x03"
                                total={25}
                                hmac
                                fields={[
                                    { name: 'MeshHeader', size: 15, color: '#6b7280' },
                                    { name: 'ack_src', size: 2, color: C.blue },
                                    { name: 'ack_seq', size: 2, color: C.amber },
                                    { name: 'status', size: 1, color: C.green, note: '0..3' },
                                    { name: 'rsv', size: 1, color: C.sub },
                                    { name: 'hmac', size: 4, color: C.magenta },
                                    { name: 'crc', size: 2, color: '#444' },
                                ]}
                            />

                            <ByteGrid
                                title="CANCEL · 25 bytes · HMAC-signed · type=0x04"
                                total={25}
                                hmac
                                fields={[
                                    { name: 'MeshHeader', size: 15, color: '#6b7280' },
                                    { name: 'cancel_seq', size: 2, color: C.amber },
                                    { name: 'user_id', size: 2, color: C.magenta },
                                    { name: 'hmac', size: 4, color: C.magenta },
                                    { name: 'reserved', size: 4, color: C.sub },
                                    { name: 'crc', size: 2, color: '#444' },
                                ]}
                            />

                            <Callout tone="amber" label="Validation pipeline · every received frame">
                                <ol className="space-y-1.5 mt-1">
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">1.</span> length ≥ <span className="docs-mono">sizeof(MeshHeader)</span></li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">2.</span> magic == 0xBA && ver == 0x02</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">3.</span> type ∈ {'{POS, SOS, ACK, CANCEL}'}</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">4.</span> CRC16-CCITT matches</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">5.</span> (src, seq, type) not already in dedup ring</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">6.</span> ts within ±300 s of GPS time</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">7.</span> if type ∈ {'{SOS, ACK, CANCEL}'} → HMAC verify, drop on fail</li>
                                    <li><span className="docs-mono text-xs text-[#a0a8b8]">8.</span> insert dedup entry; hand to forwarding FSM + local logic</li>
                                </ol>
                            </Callout>

                            <div className="docs-panel p-5 mt-6">
                                <div className="docs-mono text-xs text-white mb-3">Airtime · SF9 BW125 CR4/5</div>
                                <div className="grid grid-cols-4 gap-px bg-[#1f2434]">
                                    {[
                                        ['POS', '46 B', '~205 ms'],
                                        ['SOS', '36 B', '~180 ms'],
                                        ['ACK', '25 B', '~145 ms'],
                                        ['CANCEL', '25 B', '~145 ms'],
                                    ].map(([n, b, t]) => (
                                        <div key={n} className="bg-[#020205] p-4 text-center">
                                            <div className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478]">{n}</div>
                                            <div className="docs-display text-2xl text-white mt-1">{t}</div>
                                            <div className="docs-mono text-[10px] text-[#5a6478] mt-1">{b}</div>
                                        </div>
                                    ))}
                                </div>
                                <p className="text-[#a0a8b8] text-xs mt-3">
                                    Idle boat duty cycle: 205 ms / 120 000 ms ≈ 0.17 % — well under the ETSI 1 % cap.
                                </p>
                            </div>
                        </Section>

                        {/* ==== Signal walkthroughs ==== */}
                        <Section
                            id="flows"
                            kicker="02 / Protocol"
                            title="Signal Walkthroughs"
                            lead="Five canonical journeys a packet can take. Read each one as a sequence diagram: vertical lanes are actors, numbered circles are ordered steps."
                        >
                            <h3 className="docs-display text-2xl text-white mt-8 mb-2">A · POS routine broadcast</h3>
                            <p className="text-[#a0a8b8] max-w-3xl mb-2">
                                Every <span className="docs-mono text-[#cfd4dd]">POS_INTERVAL_S = 120 s</span>
                                ±20 s of jitter the boat tells its neighbours where it is. Cheap, no HMAC,
                                heavy on dedup. This is what powers the live map.
                            </p>
                            <SwimLane
                                title="A · POS routine broadcast"
                                lanes={['BOAT', 'MESH', 'GATEWAY', 'BACKEND']}
                                steps={[
                                    { from: 'BOAT', to: 'BOAT', label: 'POS timer fires (120s ±20)' },
                                    { from: 'BOAT', to: 'MESH', label: 'TX POS frame · 46 B · 205 ms' },
                                    { from: 'MESH', to: 'MESH', label: 'neighbours dedup + maybe forward (K=2)' },
                                    { from: 'MESH', to: 'GATEWAY', label: 'gateway-class boat overhears' },
                                    { from: 'GATEWAY', to: 'BACKEND', label: 'LoRaWAN uplink · own POS' },
                                    { from: 'BACKEND', to: 'BACKEND', label: 'INSERT boat_logs · realtime' },
                                ]}
                            />

                            <h3 className="docs-display text-2xl text-white mt-12 mb-2">B · SOS end-to-end</h3>
                            <p className="text-[#a0a8b8] max-w-3xl mb-2">
                                The critical path. From button press to <span className="docs-mono text-[#cfd4dd]">ACK_FEED</span>
                                notification on the fisherman's phone, target latency is ≤ 30 s.
                            </p>
                            <SwimLane
                                title="B · SOS end-to-end"
                                lanes={['BOAT', 'MESH', 'GATEWAY', 'BACKEND', 'OWNER']}
                                height={520}
                                steps={[
                                    { from: 'BOAT', to: 'BOAT', label: 'button press → SosState=ACTIVE, LED red-fast', color: C.red },
                                    { from: 'BOAT', to: 'BOAT', label: 'build SosPkt, sign HMAC[:4]' },
                                    { from: 'BOAT', to: 'MESH', label: 'TX SOS · 36 B · t=0', color: C.red },
                                    { from: 'MESH', to: 'MESH', label: 'RBSF flood, TTL=4, jitter 50–200 ms' },
                                    { from: 'MESH', to: 'GATEWAY', label: 'gateway-class boat receives' },
                                    { from: 'GATEWAY', to: 'BACKEND', label: 'LoRaWAN uplink (mesh-decoder)', color: C.cyan },
                                    { from: 'BACKEND', to: 'BACKEND', label: 'HMAC verify · INSERT sos_signals', color: C.green },
                                    { from: 'BACKEND', to: 'OWNER', label: 'realtime → owner CallKit', color: C.amber },
                                    { from: 'BACKEND', to: 'GATEWAY', label: 'AckPkt downlink to GW', color: C.green },
                                    { from: 'GATEWAY', to: 'MESH', label: 'GW retransmits ACK to mesh', color: C.green },
                                    { from: 'MESH', to: 'BOAT', label: 'flood ACK, hdr.dest=originator', color: C.green },
                                    { from: 'BOAT', to: 'BOAT', label: 'HMAC ok → SosState=ACKED, LED green', color: C.green },
                                ]}
                            />

                            <h3 className="docs-display text-2xl text-white mt-12 mb-2">C · Joiner SOS over BLE</h3>
                            <p className="text-[#a0a8b8] max-w-3xl mb-2">
                                A crew member without a paired LoRa device but standing on the boat fires SOS
                                through the boat's BLE radio. The boat device builds and signs the packet —
                                the joiner's phone never holds an HMAC secret.
                            </p>
                            <SwimLane
                                title="C · Joiner SOS via BLE"
                                lanes={['JOINER', 'BOAT', 'MESH', 'BACKEND']}
                                height={420}
                                steps={[
                                    { from: 'JOINER', to: 'BOAT', label: 'BLE write SOS_TRIGGER {user, reason}', color: C.amber },
                                    { from: 'BOAT', to: 'BOAT', label: 'ACL check: tier == CREW' },
                                    { from: 'BOAT', to: 'BOAT', label: 'trigger_user_id ← profiles.user_short_id' },
                                    { from: 'BOAT', to: 'MESH', label: 'TX SosPkt · trigger_user_id=joiner', color: C.red },
                                    { from: 'MESH', to: 'BACKEND', label: 'flood → gateway → LoRaWAN', color: C.cyan },
                                    { from: 'BACKEND', to: 'BACKEND', label: 'sos_signals.origin=mesh · resolve UUID', color: C.green },
                                    { from: 'BACKEND', to: 'BOAT', label: 'ACK downlink → mesh flood', color: C.green },
                                    { from: 'BOAT', to: 'JOINER', label: 'BLE notify ACK_FEED', color: C.amber },
                                ]}
                            />

                            <h3 className="docs-display text-2xl text-white mt-12 mb-2">D · Joiner fallback (no BLE in range)</h3>
                            <SwimLane
                                title="D · Joiner fallback path"
                                lanes={['JOINER', 'BACKEND', 'OWNER']}
                                steps={[
                                    { from: 'JOINER', to: 'JOINER', label: 'tap SOS' },
                                    { from: 'JOINER', to: 'JOINER', label: 'BLE scan 5 s · no match' },
                                    { from: 'JOINER', to: 'BACKEND', label: 'Supabase RPC broadcast_sos(lat, lon)', color: C.amber },
                                    { from: 'BACKEND', to: 'BACKEND', label: 'sos_signals.origin=phone_direct' },
                                    { from: 'BACKEND', to: 'OWNER', label: 'realtime → owner app sees row' },
                                    { from: 'OWNER', to: 'OWNER', label: 'owner BLE → device → mesh', color: C.red },
                                ]}
                            />

                            <h3 className="docs-display text-2xl text-white mt-12 mb-2">E · CANCEL / false-alarm</h3>
                            <SwimLane
                                title="E · CANCEL flow"
                                lanes={['USER', 'BOAT', 'MESH', 'BACKEND']}
                                steps={[
                                    { from: 'USER', to: 'BOAT', label: 'app button or long-press SOS · CREW = own-only' },
                                    { from: 'BOAT', to: 'BOAT', label: 'SosState=CANCELED, LED off', color: C.red },
                                    { from: 'BOAT', to: 'MESH', label: 'TX CANCEL once', color: C.amber },
                                    { from: 'MESH', to: 'BACKEND', label: 'gateway uplinks', color: C.cyan },
                                    { from: 'BACKEND', to: 'BACKEND', label: "UPDATE sos_signals SET status='canceled'" },
                                ]}
                            />
                        </Section>

                        {/* ==== State machines ==== */}
                        <Section
                            id="fsm"
                            kicker="02 / Protocol"
                            title="State Machines"
                            lead="Four explicit FSMs run inside the firmware. Each one owns a narrow concern. Names match the spec verbatim."
                        >
                            <FSM
                                title="FSM-1 · Radio Scheduler"
                                width={760}
                                height={300}
                                nodes={[
                                    { id: 'BOOT', x: 40, y: 130 },
                                    { id: 'MESH_LISTEN', x: 200, y: 130 },
                                    { id: 'MESH_TX', x: 380, y: 40 },
                                    { id: 'MESH_PROCESS', x: 380, y: 220 },
                                    { id: 'LMIC_HANDOFF', x: 560, y: 40 },
                                    { id: 'LMIC_ACTIVE', x: 560, y: 220 },
                                ]}
                                edges={[
                                    { from: 'BOOT', to: 'MESH_LISTEN', label: 'init OK' },
                                    { from: 'MESH_LISTEN', to: 'MESH_TX', label: 'POS / fwd / SOS' },
                                    { from: 'MESH_LISTEN', to: 'MESH_PROCESS', label: 'RX flag', curve: -20 },
                                    { from: 'MESH_PROCESS', to: 'MESH_LISTEN', label: 'done', curve: 30 },
                                    { from: 'MESH_TX', to: 'MESH_LISTEN', label: 'done', curve: -30 },
                                    { from: 'MESH_LISTEN', to: 'LMIC_HANDOFF', label: 'uplink' },
                                    { from: 'LMIC_HANDOFF', to: 'LMIC_ACTIVE', label: 'tx' },
                                    { from: 'LMIC_ACTIVE', to: 'MESH_LISTEN', label: 'EV_TXCOMPLETE' },
                                ]}
                            />

                            <FSM
                                title="FSM-2 · Per-packet Forwarding (RBSF)"
                                width={720}
                                height={260}
                                nodes={[
                                    { id: 'PENDING', x: 60, y: 100, color: C.cyan },
                                    { id: 'SUPPRESSED', x: 280, y: 30, color: C.amber },
                                    { id: 'DONE (tx)', x: 280, y: 170, color: C.green, w: 120 },
                                    { id: 'DROP_TTL', x: 520, y: 100, color: C.red },
                                    { id: 'DROP_DUP', x: 520, y: 190, color: C.red },
                                ]}
                                edges={[
                                    { from: 'PENDING', to: 'SUPPRESSED', label: 'heard ≥ K=2' },
                                    { from: 'PENDING', to: 'DONE (tx)', label: 'jitter expired' },
                                    { from: 'PENDING', to: 'DROP_TTL', label: 'hops+1 > ttl' },
                                    { from: 'PENDING', to: 'DROP_DUP', label: 'dedup hit' },
                                ]}
                            />

                            <FSM
                                title="FSM-3 · SOS Originator"
                                width={720}
                                height={260}
                                nodes={[
                                    { id: 'IDLE', x: 60, y: 100 },
                                    { id: 'ACTIVE', x: 280, y: 100, color: C.red },
                                    { id: 'ACKED', x: 500, y: 30, color: C.green },
                                    { id: 'CANCELED', x: 500, y: 170, color: C.amber },
                                ]}
                                edges={[
                                    { from: 'IDLE', to: 'ACTIVE', label: 'button / BLE trigger' },
                                    { from: 'ACTIVE', to: 'ACTIVE', label: 'retry · 0/30/60/120/300…' },
                                    { from: 'ACTIVE', to: 'ACKED', label: 'ACK rx (HMAC ok)' },
                                    { from: 'ACTIVE', to: 'CANCELED', label: 'cancel / batt < 10%' },
                                    { from: 'ACKED', to: 'IDLE', label: 'after 5 min hold' },
                                ]}
                            />

                            <FSM
                                title="FSM-4 · LoRaWAN Uplink Queue (gateway role)"
                                width={720}
                                height={220}
                                nodes={[
                                    { id: 'EMPTY', x: 60, y: 90 },
                                    { id: 'QUEUED', x: 280, y: 90, color: C.amber },
                                    { id: 'IN_FLIGHT', x: 520, y: 90, color: C.cyan, w: 130 },
                                ]}
                                edges={[
                                    { from: 'EMPTY', to: 'QUEUED', label: 'enqueue · SOS preempts' },
                                    { from: 'QUEUED', to: 'IN_FLIGHT', label: 'radio free' },
                                    { from: 'IN_FLIGHT', to: 'EMPTY', label: 'EV_TXCOMPLETE' },
                                    { from: 'IN_FLIGHT', to: 'QUEUED', label: 'more waiting' },
                                ]}
                            />
                        </Section>

                        {/* ==== LED ==== */}
                        <Section
                            id="led"
                            kicker="03 / UX"
                            title="LED Status Reference"
                            lead="The buoy has exactly one user interface: a single WS2812 pixel and a long-press button. Every operating state of the system is encoded as a colour + blink pattern. Learn this card and you can diagnose a node from a hundred metres of open water."
                        >
                            <div className="grid md:grid-cols-2 xl:grid-cols-3 gap-4">
                                {LED_PATTERNS.map((l) => <LedCard key={l.name} {...l} />)}
                            </div>

                            <Callout tone="cyan" label="Reading priority">
                                Red beats green beats blue beats amber beats cyan. If two conditions overlap
                                (e.g. SOS active and battery low), the higher-priority pattern wins. Cyan
                                breathing is the default "everything's fine, leave me alone" pattern.
                            </Callout>
                        </Section>

                        {/* ==== BLE / crew ==== */}
                        <Section
                            id="ble"
                            kicker="03 / UX"
                            title="BLE Auth & Crew Multi-Tenant"
                            lead="A single boat device serves up to four BLE clients: one owner + three crew. Each connection is independently authenticated with a per-tier HMAC challenge; per-command ACLs prevent crew from touching config."
                        >
                            <div className="docs-panel p-6 my-2">
                                <div className="docs-mono text-xs text-white mb-4">BLE auth handshake · per connection</div>
                                <svg viewBox="0 0 800 320" className="w-full h-auto">
                                    <defs>
                                        <marker id="ble-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto">
                                            <path d="M0,0 L10,5 L0,10 z" fill={C.cyan} />
                                        </marker>
                                    </defs>
                                    <rect x="40" y="0" width="200" height="30" fill={C.panelHi} />
                                    <text x="140" y="20" textAnchor="middle" fill={C.amber} fontSize="11" fontFamily="JetBrains Mono" letterSpacing="2">PHONE</text>
                                    <rect x="560" y="0" width="200" height="30" fill={C.panelHi} />
                                    <text x="660" y="20" textAnchor="middle" fill={C.cyan} fontSize="11" fontFamily="JetBrains Mono" letterSpacing="2">BOAT DEVICE</text>
                                    <line x1="140" y1="30" x2="140" y2="310" stroke={C.border} strokeDasharray="2 3" />
                                    <line x1="660" y1="30" x2="660" y2="310" stroke={C.border} strokeDasharray="2 3" />

                                    {[
                                        { y: 60, t: '1', fl: '→', l: 'BLE connect', s: 'conn.tier = STRANGER', color: C.sub },
                                        { y: 100, t: '2', fl: '←', l: 'read AUTH_CHALLENGE', s: 'C = 16 random bytes', color: C.cyan },
                                        { y: 140, t: '3', fl: '→', l: 'write AUTH_RESPONSE', s: 'HMAC(token, C)[:8] + tier_hint', color: C.magenta },
                                        { y: 180, t: '4', fl: '', l: 'consteq verify', s: 'tier ← OWNER / CREW or STRANGER', color: C.green, right: true },
                                        { y: 220, t: '5', fl: '←', l: 'read AUTH_STATUS', s: '{tier, ok}', color: C.cyan },
                                        { y: 260, t: '6', fl: '→', l: 'subscribe DATA + ACK_FEED', s: 'operate', color: C.green },
                                    ].map((s, i) => (
                                        <g key={i}>
                                            <circle cx={s.right ? 660 : 140} cy={s.y} r="11" fill={C.panel} stroke={s.color} />
                                            <text x={s.right ? 660 : 140} y={s.y + 4} textAnchor="middle" fill={s.color} fontSize="10" fontFamily="JetBrains Mono">{s.t}</text>
                                            {!s.right && (
                                                <line
                                                    x1={s.fl === '→' ? 152 : 648}
                                                    y1={s.y}
                                                    x2={s.fl === '→' ? 648 : 152}
                                                    y2={s.y}
                                                    stroke={s.color} strokeWidth="1.2" markerEnd="url(#ble-arrow)"
                                                />
                                            )}
                                            <text x="400" y={s.y - 4} textAnchor="middle" fill={C.text} fontSize="11" fontFamily="JetBrains Mono">{s.l}</text>
                                            <text x="400" y={s.y + 12} textAnchor="middle" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">{s.s}</text>
                                        </g>
                                    ))}
                                </svg>
                            </div>

                            <h3 className="docs-display text-2xl text-white mt-10 mb-4">Per-command ACL</h3>
                            <div className="docs-panel overflow-hidden">
                                <table className="w-full text-sm">
                                    <thead>
                                        <tr className="bg-[#101422]">
                                            {['Command', 'Owner', 'Crew', 'Stranger'].map(h => (
                                                <th key={h} className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478] py-3 px-4 text-left">{h}</th>
                                            ))}
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {[
                                            ['SET config', '✓', '✗', '✗'],
                                            ['START_JOURNEY / END_JOURNEY', '✓', '✓', '✗'],
                                            ['SOS_TRIGGER', '✓', '✓', '✗'],
                                            ['CANCEL_SOS', '✓', 'own only', '✗'],
                                            ['ROTATE_KEY', '✓', '✗', '✗'],
                                            ['FACTORY_RESET', '✓', '✗', '✗'],
                                            ['Subscribe DATA', '✓', '✓', '✗'],
                                            ['Subscribe ACK_FEED', '✓', '✓', '✗'],
                                        ].map((row, i) => (
                                            <tr key={i} className="border-t border-[#1f2434]">
                                                <td className="docs-mono text-xs text-[#cfd4dd] py-2.5 px-4">{row[0]}</td>
                                                {row.slice(1).map((cell, j) => (
                                                    <td key={j} className="py-2.5 px-4 docs-mono text-xs"
                                                        style={{
                                                            color: cell === '✓' ? C.green : cell === '✗' ? C.red : C.amber
                                                        }}>{cell}</td>
                                                ))}
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>

                            <Callout tone="green" label="Crew membership flow">
                                Owner shows QR → joiner scans → backend writes <span className="docs-mono">boat_members</span>
                                → app calls <span className="docs-mono">get_crew_token(boat_id)</span> → token cached
                                in <span className="docs-mono">flutter_secure_storage</span>. On next BLE proximity,
                                AUTH handshake with that token elevates the connection to CREW.
                            </Callout>
                        </Section>

                        {/* ==== Security ==== */}
                        <Section
                            id="security"
                            kicker="04 / Backend"
                            title="Identity & Security"
                            lead="Three identity layers cover three different concerns: who the device is on the LoRaWAN network, who it is on the mesh, and who the human at the other end of the BLE link is."
                        >
                            <div className="docs-panel p-6 my-4">
                                <svg viewBox="0 0 800 280" className="w-full h-auto">
                                    {[
                                        { y: 30, color: C.cyan, label: 'LoRaWAN identity', body: 'DevEUI (8 B) + AppEUI (8 B) + AppKey (16 B)', why: 'authentication with ChirpStack network server' },
                                        { y: 100, color: C.magenta, label: 'Mesh identity', body: 'mesh_src_id (u16) + hmac_secret (16 B)', why: 'fits in 2 bytes per frame · per-boat isolated' },
                                        { y: 170, color: C.amber, label: 'BLE identity', body: 'owner = hmac_secret · crew = crew_token (8 B)', why: 'per-connection challenge, per-command ACL' },
                                        { y: 240, color: C.green, label: 'Backend identity', body: 'profiles.id (UUID) + profiles.user_short_id (u16)', why: 'short_id rides in mesh packets · UUID for RLS' },
                                    ].map((r, i) => (
                                        <g key={i}>
                                            <rect x="40" y={r.y} width="720" height="50" fill={C.bg} stroke={r.color} />
                                            <text x="60" y={r.y + 22} fill={r.color} fontSize="11" fontFamily="JetBrains Mono" letterSpacing="2">{`0${i + 1} · ${r.label}`}</text>
                                            <text x="60" y={r.y + 40} fill={C.text} fontSize="12" fontFamily="JetBrains Mono">{r.body}</text>
                                            <text x="760" y={r.y + 32} textAnchor="end" fill={C.mute} fontSize="10" fontFamily="JetBrains Mono">{r.why}</text>
                                        </g>
                                    ))}
                                </svg>
                            </div>

                            <h3 className="docs-display text-2xl text-white mt-10 mb-3">HMAC anatomy</h3>
                            <Code>{`hmac_input = MeshHeader (15 B) || payload up to (but excluding) hmac and crc
hmac_full  = HMAC_SHA256(hmac_secret, hmac_input)
hmac_4     = hmac_full[0..3]   // 4 bytes on the wire`}</Code>
                            <p className="text-[#a0a8b8] text-sm leading-relaxed max-w-3xl">
                                Library is <span className="docs-mono">mbedtls_md_hmac</span> (built into Arduino-ESP32),
                                about 1 ms per packet. Brute-forcing a 4-byte truncated HMAC at the protocol's airtime
                                ceiling would require ≈ 24 years of continuous transmission — well outside the threat model.
                            </p>

                            <h3 className="docs-display text-2xl text-white mt-10 mb-3">Threat model</h3>
                            <div className="docs-panel overflow-hidden">
                                <table className="w-full text-sm">
                                    <thead>
                                        <tr className="bg-[#101422]">
                                            <th className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478] py-3 px-4 text-left">Attack</th>
                                            <th className="docs-mono text-[10px] tracking-[0.3em] uppercase text-[#5a6478] py-3 px-4 text-left">Mitigation</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        {[
                                            ['Spoofed SOS from rogue LoRa', 'HMAC verify fails at backend → drop'],
                                            ['Replay of captured SOS', 'ts outside ±300 s OR seq ≤ last_seq → reject'],
                                            ['Spoofed POS (no HMAC)', 'Backend rate-limits + position-jump filter + src must be registered'],
                                            ['Forged ACK', 'ACK is HMAC-signed with originator\'s key — attacker has no key'],
                                            ['Selective DoS (forwarder drops SOS)', 'RBSF flood = multiple paths'],
                                            ['Mass spoof flood (radio DoS)', 'CAD listen near-free + backend rate-limits per src'],
                                            ['Phone compromise post-pair', 'Secret never leaves device after pair'],
                                            ['Device theft', 'Owner reports → backend disables boat or rotates secret (v2 downlink)'],
                                            ['Stolen joiner phone', 'Only crew_token; cannot forge mesh HMAC; owner revokes via boat_members'],
                                            ['Crew tries owner commands', 'BLE per-command ACL drops at device'],
                                        ].map((row, i) => (
                                            <tr key={i} className="border-t border-[#1f2434]">
                                                <td className="docs-mono text-xs text-[#cfd4dd] py-2.5 px-4">{row[0]}</td>
                                                <td className="text-xs text-[#a0a8b8] py-2.5 px-4">{row[1]}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                            <Callout tone="amber" label="Out of scope (v1)">
                                Crew token rotation on crew removal · ESP32 flash encryption + secure boot ·
                                Active jamming defence (detection only — fleet-wide silence triggers a SAR alert).
                            </Callout>
                        </Section>

                        {/* ==== Backend integration ==== */}
                        <Section
                            id="backend"
                            kicker="04 / Backend"
                            title="Backend Integration"
                            lead="Once a frame reaches a LoRaWAN gateway, it leaves the radio world and enters the cloud. Two stops: ChirpStack, then a Supabase Edge function."
                        >
                            <div className="docs-panel p-6 my-4">
                                <div className="docs-mono text-xs text-white mb-4">Cloud path · uplink and ACK downlink</div>
                                <svg viewBox="0 0 820 220" className="w-full h-auto">
                                    {[
                                        { x: 20, label: 'Gateway-class boat', sub: 'LoRaWAN uplink frame', color: C.magenta },
                                        { x: 180, label: 'ChirpStack NS', sub: 'Network Server', color: C.cyan },
                                        { x: 340, label: 'ChirpStack AS codec', sub: 'JS · header parse', color: C.cyan },
                                        { x: 500, label: 'Edge fn · mesh-decoder', sub: 'HMAC + dedup + dispatch', color: C.green },
                                        { x: 660, label: 'Supabase tables', sub: 'sos_signals + boat_logs', color: C.green },
                                    ].map((s, i) => (
                                        <g key={i}>
                                            <rect x={s.x} y={70} width="140" height="60" fill={C.bg} stroke={s.color} />
                                            <text x={s.x + 70} y={94} textAnchor="middle" fill={s.color} fontSize="10" fontFamily="JetBrains Mono" letterSpacing="2">{`0${i + 1}`}</text>
                                            <text x={s.x + 70} y={110} textAnchor="middle" fill={C.text} fontSize="10" fontFamily="JetBrains Mono">{s.label}</text>
                                            <text x={s.x + 70} y={122} textAnchor="middle" fill={C.mute} fontSize="9" fontFamily="JetBrains Mono">{s.sub}</text>
                                            {i < 4 && (
                                                <line x1={s.x + 140} y1="100" x2={s.x + 180} y2="100" stroke={C.sub} strokeWidth="1" markerEnd="url(#fsm-arrow)" />
                                            )}
                                        </g>
                                    ))}
                                    <text x="410" y="170" textAnchor="middle" fill={C.green} fontSize="10" fontFamily="JetBrains Mono">ACK downlink path · same hops in reverse · pgcrypto.hmac builds AckPkt</text>
                                    <line x1="730" y1="155" x2="90" y2="155" stroke={C.green} strokeWidth="1.2" strokeDasharray="3 3" markerEnd="url(#fsm-arrow)" />
                                </svg>
                            </div>

                            <h3 className="docs-display text-2xl text-white mt-8 mb-3">Edge function flow</h3>
                            <Code>{`1. Parse frame, validate magic/ver/type, CRC.
2. Lookup boat by mesh_src_id; load hmac_secret.
3. If type in {SOS, ACK, CANCEL}: verify HMAC (consteq).
4. Verify ts freshness (±300 s); verify seq progression.
5. Dispatch by type:
     POS    → INSERT boat_logs
     SOS    → INSERT sos_signals ON CONFLICT (boat_id, mesh_seq) DO NOTHING
              → trigger downlink ACK via ChirpStack REST
     CANCEL → UPDATE sos_signals SET status='canceled'
6. Return 200 OK.`}</Code>

                            <h3 className="docs-display text-2xl text-white mt-10 mb-3">Schema migration v10 · key columns</h3>
                            <div className="grid md:grid-cols-2 gap-4">
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">boats</div>
                                    <KV k="mesh_src_id" v="INTEGER UNIQUE 1..65534" mono />
                                    <KV k="hmac_secret" v="BYTEA · server only" mono />
                                    <KV k="crew_token" v="BYTEA · via RPC" mono />
                                    <KV k="dev_eui" v="BYTEA" mono />
                                    <KV k="last_sos_seq" v="INTEGER" mono />
                                    <KV k="relay_mode" v="BOOLEAN default false" mono />
                                </div>
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">sos_signals</div>
                                    <KV k="origin" v="'mesh' | 'phone_direct'" mono />
                                    <KV k="trigger_user_id" v="UUID → profiles.id" mono />
                                    <KV k="mesh_seq" v="INTEGER · u16" mono />
                                    <KV k="mesh_hops" v="SMALLINT" mono />
                                    <KV k="gateway_boat_id" v="INTEGER → boats" mono />
                                    <KV k="ack_status" v="SMALLINT default 0" mono />
                                </div>
                            </div>
                            <Callout tone="cyan" label="Realtime channels">
                                <span className="docs-mono">sos_signals insert</span> → owner CallKit, joiner ACK display, admin map ·
                                <span className="docs-mono"> boat_logs insert</span> → live boat tracking ·
                                <span className="docs-mono"> boat_journey_events insert</span> → audit + admin
                            </Callout>
                        </Section>

                        {/* ==== Tunables ==== */}
                        <Section
                            id="tunables"
                            kicker="05 / Reference"
                            title="Tunables & Limits"
                            lead="Every magic number in one place. Change with care."
                        >
                            <div className="grid md:grid-cols-2 gap-4">
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">Radio</div>
                                    <KV k="MESH_FREQ_MHZ" v="865.2" mono />
                                    <KV k="MESH_SF" v="9" mono />
                                    <KV k="MESH_BW_KHZ" v="125" mono />
                                    <KV k="MESH_CR" v="4/5" mono />
                                    <KV k="MESH_SYNC_WORD" v="0x12 · private" mono />
                                    <KV k="MESH_TX_DBM" v="14 · ETSI cap" mono />
                                </div>
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">Protocol</div>
                                    <KV k="MESH_TTL" v="4 hops" mono />
                                    <KV k="K_SUPPRESS" v="2" mono />
                                    <KV k="JITTER_POS" v="200..800 ms" mono />
                                    <KV k="JITTER_SOS" v="50..200 ms" mono />
                                    <KV k="JITTER_ACK" v="50..200 ms" mono />
                                    <KV k="DEDUP_CACHE_SIZE" v="64 entries" mono />
                                </div>
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">Timing</div>
                                    <KV k="POS_INTERVAL_S" v="120 ±20" mono />
                                    <KV k="SOS_RETRY_S" v="0/30/60/120/300…" mono />
                                    <KV k="REPLAY_WINDOW_S" v="300" mono />
                                    <KV k="ACK hold" v="5 min after ACKED" mono />
                                </div>
                                <div className="docs-panel p-5">
                                    <div className="docs-mono text-xs text-white mb-3">Limits</div>
                                    <KV k="BLE_MAX_CONN" v="4 · 1 owner + 3 crew" mono />
                                    <KV k="MAX_INFLIGHT_FWD" v="8" mono />
                                    <KV k="LOW_BATT_THRESHOLD_PC" v="10" mono />
                                    <KV k="CRITICAL_BATT_PC" v="5" mono />
                                </div>
                            </div>
                        </Section>

                        {/* ==== Glossary ==== */}
                        <Section
                            id="glossary"
                            kicker="05 / Reference"
                            title="Glossary"
                        >
                            <div className="docs-panel overflow-hidden">
                                <table className="w-full text-sm">
                                    <tbody>
                                        {[
                                            ['ACK', 'Mesh acknowledgement packet sent by the backend (via a gateway-class boat) confirming that an SOS reached land.'],
                                            ['CAD', 'Channel Activity Detection. RFM95 low-power preamble sniff used in mesh idle to avoid full RX duty.'],
                                            ['ChirpStack', 'Open-source LoRaWAN Network Server. Receives uplinks from gateways and dispatches downlinks.'],
                                            ['Dedup ring', '64-entry ring buffer of (src, seq, type) tuples. Drops repeat sightings of the same frame.'],
                                            ['DevEUI', '8-byte unique LoRaWAN device identifier.'],
                                            ['FSM', 'Finite state machine. Four explicit ones live in the firmware.'],
                                            ['Gateway-class boat', 'Any boat momentarily in LoRaWAN range that relays mesh frames to ChirpStack.'],
                                            ['HMAC', 'Keyed message authentication code. The mesh uses SHA-256 truncated to 4 bytes for size.'],
                                            ['LMIC', 'LoRaWAN-in-C. The Arduino LoRaWAN stack used for the public uplink path.'],
                                            ['mesh_src_id', '16-bit fleet-local identifier the backend assigns at pair time. Rides in every frame.'],
                                            ['NVS', 'Non-Volatile Storage. ESP32 key-value flash. Holds pairing state and secrets.'],
                                            ['POS', 'Routine position broadcast every ~120 s. Cheap, unauthenticated, dedup-heavy.'],
                                            ['RBSF', 'Receiver-Based Suppression Flood. If you overhear a frame K times, do not forward.'],
                                            ['Realtime', 'Supabase logical-replication channel that pushes table changes to subscribed clients.'],
                                            ['RLS', 'Row-Level Security. Postgres-level access policy. Crew vs. owner vs. admin enforced here.'],
                                            ['SF', 'Spreading Factor. SF9 is the mesh default — a balance of range and airtime.'],
                                            ['Sync word', 'LoRa PHY-layer network discriminator. 0x34 = public LoRaWAN, 0x12 = our private mesh.'],
                                            ['user_short_id', 'New 16-bit per-user identifier that fits in mesh packet fields. Backend resolves to UUID on receive.'],
                                        ].map(([k, v]) => (
                                            <tr key={k} className="border-t border-[#1f2434] first:border-t-0">
                                                <td className="docs-mono text-xs py-3 px-4 align-top w-44" style={{ color: C.cyan }}>{k}</td>
                                                <td className="text-sm text-[#cfd4dd] py-3 px-4 leading-relaxed">{v}</td>
                                            </tr>
                                        ))}
                                    </tbody>
                                </table>
                            </div>
                        </Section>

                        {/* ==== Footer ==== */}
                        <footer className="pt-16 pb-8 border-t border-[#1f2434]">
                            <div className="flex flex-col md:flex-row md:items-end md:justify-between gap-6">
                                <div>
                                    <div className="docs-kicker mb-2">Source spec</div>
                                    <div className="docs-mono text-xs text-[#cfd4dd]">
                                        docs/superpowers/specs/2026-05-13-boatnode-hybrid-mesh-design.md
                                    </div>
                                </div>
                                <div className="text-right">
                                    <div className="docs-kicker mb-2">Project</div>
                                    <div className="docs-mono text-xs text-[#cfd4dd]">
                                        Neduvaai · BoatNode v2 · fisherman safety system
                                    </div>
                                </div>
                            </div>
                            <div className="docs-rule mt-8 mb-4" />
                            <div className="flex items-center justify-between">
                                <div className="text-[#5a6478] text-xs">
                                    Doc generated from approved design spec. Implementation in progress.
                                </div>
                                <a href="#/" className="docs-mono text-xs text-[#a0a8b8] hover:text-[#00ffff]">
                                    ← back to story
                                </a>
                            </div>
                        </footer>
                    </main>
                </div>
            </div>
        </div>
    );
};

export default Docs;
