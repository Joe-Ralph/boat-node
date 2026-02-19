'use client';

import { MapContainer, TileLayer, Marker, Popup, useMap, Polyline, Tooltip } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import { useEffect, useState, useRef, useMemo } from 'react';
import L from 'leaflet';
import { createClient } from '@/utils/supabase/client';
import { Boat } from '@/lib/types';
import styles from './map-v2.module.css';
import { useSearchParams } from 'next/navigation';
import { Play, Pause, History, Crosshair, Clock } from 'lucide-react';
import TimelineControl from './TimelineControl';

// Fix Leaflet Default Icon
// @ts-ignore
delete L.Icon.Default.prototype._getIconUrl;

L.Icon.Default.mergeOptions({
    iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
    iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

type BoatWithLocation = Boat & {
    location?: {
        lat: number;
        lon: number;
        heading: number;
        speed: number;
        last_updated: string;
        battery_level: number;
    };
};

type HistoricalPoint = {
    boat_id: string;
    lat: number;
    lon: number;
    heading: number;
    speed: number;
    recorded_at: string;
    battery_level?: number;
};

function createBoatIcon(heading: number = 0, color: string = '#0ea5e9') {
    return L.divIcon({
        className: 'custom-boat-icon',
        html: `
      <div style="
        transform: rotate(${heading}deg);
        width: 30px;
        height: 30px;
        display: flex;
        align-items: center;
        justify-content: center;
        transition: transform 0.1s linear; 
      ">
        <svg width="24" height="24" viewBox="0 0 24 24" fill="${color}" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M12 2L2 22l10-3 10 3L12 2z"/>
        </svg>
      </div>
    `,
        iconSize: [30, 30],
        iconAnchor: [15, 15],
    });
}

// Controller component to handle map interactions
function MapController({ selectedBoatId, boats, focusTrigger }: { selectedBoatId: string | null, boats: Record<string, BoatWithLocation>, focusTrigger: number }) {
    const map = useMap();

    useEffect(() => {
        if (selectedBoatId && boats[selectedBoatId]?.location) {
            const boat = boats[selectedBoatId];
            if (boat.location) {
                map.flyTo([boat.location.lat, boat.location.lon], 14, {
                    duration: 1.5
                });
            }
        }
    }, [selectedBoatId, focusTrigger, map]); // Removed 'boats' dependency to avoid re-centering on every update

    return null;
}

// Component to handle map resizing issues
function MapInvalidator() {
    const map = useMap();
    useEffect(() => {
        setTimeout(() => {
            map.invalidateSize();
        }, 200);
    }, [map]);
    return null;
}

// Center Button Component
function CenterControl({ onCenter }: { onCenter: () => void }) {
    return (
        <div className="leaflet-bottom leaflet-right" style={{ marginBottom: '80px' }}>
            <div className="leaflet-control leaflet-bar">
                <a
                    href="#"
                    role="button"
                    onClick={(e) => {
                        e.preventDefault();
                        onCenter();
                    }}
                    className="bg-white hover:bg-gray-100 flex items-center justify-center w-[30px] h-[30px] shadow-sm border-2 border-[rgba(0,0,0,0.2)] rounded cursor-pointer text-slate-700"
                    title="Center on Boat"
                    style={{ backgroundColor: 'white', width: '34px', height: '34px', lineHeight: '30px', borderRadius: '4px' }}
                >
                    <Crosshair size={18} />
                </a>
            </div>
        </div>
    );
}

export default function BoatMap() {
    const [boats, setBoats] = useState<Record<string, BoatWithLocation>>({});
    const supabase = createClient();
    const searchParams = useSearchParams();
    const selectedBoatId = searchParams.get('boatId');
    const defaultPosition: [number, number] = [8.08, 77.53];
    const [focusTrigger, setFocusTrigger] = useState(0);

    // --- Time Travel State ---
    const [isHistoryMode, setIsHistoryMode] = useState(false);
    const [historyLogs, setHistoryLogs] = useState<HistoricalPoint[]>([]);
    const [currentTime, setCurrentTime] = useState<number>(Date.now());
    const [isPlaying, setIsPlaying] = useState(false);
    const [playbackSpeed, setPlaybackSpeed] = useState(10); // 10x speed default
    const [timeRangeHours, setTimeRangeHours] = useState(24);

    // Derived state for history bounds
    const maxTime = useRef(Date.now());
    const minTime = useRef(Date.now() - 24 * 60 * 60 * 1000);

    // Filter logs for interpolation
    // We group logs by boat_id for faster lookup
    const logsByBoat = useMemo(() => {
        const grouped: Record<string, HistoricalPoint[]> = {};
        historyLogs.forEach(log => {
            if (!grouped[log.boat_id]) grouped[log.boat_id] = [];
            grouped[log.boat_id].push(log);
        });
        // Sort by time
        Object.keys(grouped).forEach(key => {
            grouped[key].sort((a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime());
        });
        return grouped;
    }, [historyLogs]);

    // Interpolated Positions
    const [interpolatedBoats, setInterpolatedBoats] = useState<Record<string, BoatWithLocation>>({});

    // Fetch Live Data (Initial & Realtime)
    useEffect(() => {
        const fetchBoats = async () => {
            const { data: boatData } = await supabase.from('boats').select('*');
            const { data: locationData } = await supabase.from('boat_live_locations').select('*');

            const boatMap: Record<string, BoatWithLocation> = {};
            boatData?.forEach((b) => boatMap[b.id] = { ...b });
            locationData?.forEach((loc) => {
                if (boatMap[loc.boat_id]) boatMap[loc.boat_id].location = loc;
            });
            setBoats(boatMap);
        };

        fetchBoats();

        const channel = supabase
            .channel('live-locations')
            .on('postgres_changes', { event: '*', schema: 'public', table: 'boat_live_locations' },
                (payload) => {
                    if (!isHistoryMode) {
                        setBoats((prev) => {
                            const boat = prev[payload.new.boat_id];
                            if (!boat) return prev;
                            return { ...prev, [payload.new.boat_id]: { ...boat, location: payload.new } };
                        });
                    }
                }
            )
            .subscribe();

        return () => { supabase.removeChannel(channel); };
    }, [isHistoryMode]);

    // Fetch History Data
    useEffect(() => {
        if (!isHistoryMode) return;

        const fetchHistory = async () => {
            // Reset time bounds based on range
            const end = new Date();
            const start = new Date(end.getTime() - timeRangeHours * 60 * 60 * 1000);

            maxTime.current = end.getTime();
            minTime.current = start.getTime();
            setCurrentTime(end.getTime()); // Start at "now" (end of history)

            const { data, error } = await supabase
                .from('boat_logs')
                .select('*')
                .gte('recorded_at', start.toISOString())
                .lte('recorded_at', end.toISOString())
                .order('recorded_at', { ascending: true });

            if (error) {
                console.error("Error fetching history:", error);
            } else {
                setHistoryLogs(data || []);
            }
        };

        fetchHistory();
    }, [isHistoryMode, timeRangeHours]);


    // Animation Loop
    useEffect(() => {
        let animationFrameId: number;
        let lastTick = performance.now();

        const loop = (timestamp: number) => {
            const dt = timestamp - lastTick;
            lastTick = timestamp;

            if (isPlaying && isHistoryMode) {
                setCurrentTime(prev => {
                    const nextTime = prev + (dt * 1000 * playbackSpeed / 1000); // dt (ms) * speed
                    if (nextTime >= maxTime.current) {
                        setIsPlaying(false);
                        return maxTime.current;
                    }
                    return nextTime;
                });
            }

            // Interpolate Positions for currentTime
            if (isHistoryMode) {
                const newInterpolated: Record<string, BoatWithLocation> = {};

                Object.keys(logsByBoat).forEach(boatId => {
                    const logs = logsByBoat[boatId];
                    if (logs.length < 2) return;

                    // Find segment [p1, p2] where p1.time <= currentTime <= p2.time
                    let p1 = logs[0];
                    let p2 = logs[logs.length - 1];
                    let found = false;

                    // Binary search or simple iteration (optimization possible)
                    for (let i = 0; i < logs.length - 1; i++) {
                        const t1 = new Date(logs[i].recorded_at).getTime();
                        const t2 = new Date(logs[i + 1].recorded_at).getTime();
                        if (currentTime >= t1 && currentTime <= t2) {
                            p1 = logs[i];
                            p2 = logs[i + 1];
                            found = true;
                            break;
                        }
                    }

                    // If before start or after end, clamp or hide? Clamping for now.
                    // Actually, if !found, checking if we are past the last log or before first
                    if (!found) {
                        return; // Don't render if out of known bounds
                    }

                    const t1 = new Date(p1.recorded_at).getTime();
                    const t2 = new Date(p2.recorded_at).getTime();
                    const factor = (currentTime - t1) / (t2 - t1);

                    // Lerp
                    const lat = p1.lat + (p2.lat - p1.lat) * factor;
                    const lon = p1.lon + (p2.lon - p1.lon) * factor;

                    // Heading requires careful lerp (359 -> 1)
                    let h1 = p1.heading;
                    let h2 = p2.heading;
                    if (Math.abs(h2 - h1) > 180) {
                        if (h2 > h1) h1 += 360;
                        else h2 += 360;
                    }
                    const heading = (h1 + (h2 - h1) * factor) % 360;

                    // Construct Ghost Boat
                    // We need base boat info (name, etc) from `boats` state
                    if (boats[boatId]) {
                        newInterpolated[boatId] = {
                            ...boats[boatId],
                            location: {
                                lat,
                                lon,
                                heading,
                                speed: p1.speed, // simplified
                                battery_level: p1.battery_level || 0,
                                last_updated: new Date(currentTime).toISOString()
                            }
                        };
                    }
                });
                setInterpolatedBoats(newInterpolated);
            }

            animationFrameId = requestAnimationFrame(loop);
        };

        if (isHistoryMode) {
            animationFrameId = requestAnimationFrame(loop);
        }

        return () => cancelAnimationFrame(animationFrameId);
    }, [isPlaying, isHistoryMode, currentTime, logsByBoat, playbackSpeed, boats]);

    // Rendered Boats: Live or Interpolated
    const displayedBoats = isHistoryMode ? interpolatedBoats : boats;

    return (
        <div className={styles.rootWrapper}>
            <MapContainer
                center={defaultPosition}
                zoom={10}
                className={styles.mapLeafletInstance}
            >
                <TileLayer
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />

                <MapController selectedBoatId={selectedBoatId} boats={boats} focusTrigger={focusTrigger} />
                <MapInvalidator />
                <CenterControl onCenter={() => setFocusTrigger(prev => prev + 1)} />

                {/* Toggle Mode Button */}
                <div className="leaflet-top leaflet-right" style={{ marginTop: '10px', marginRight: '10px', pointerEvents: 'auto' }}>
                    <button
                        onClick={() => {
                            setIsHistoryMode(!isHistoryMode);
                            setIsPlaying(false);
                            if (!isHistoryMode) {
                                // Entering history mode
                                setCurrentTime(Date.now());
                            }
                        }}
                        className={`flex items-center gap-2 px-4 py-2 rounded-lg font-bold shadow-lg transition-all ${isHistoryMode
                                ? 'bg-orange-500 text-white hover:bg-orange-600'
                                : 'bg-white text-slate-700 hover:bg-gray-100'
                            }`}
                    >
                        {isHistoryMode ? <Clock size={16} /> : <History size={16} />}
                        {isHistoryMode ? 'Exit Time Travel' : 'Time Travel'}
                    </button>
                </div>

                {/* Timeline Control */}
                {isHistoryMode && (
                    <TimelineControl
                        minTime={minTime.current}
                        maxTime={maxTime.current}
                        currentTime={currentTime}
                        onChange={setCurrentTime}
                        onPlayPause={setIsPlaying}
                        isPlaying={isPlaying}
                        playbackSpeed={playbackSpeed}
                        onSpeedChange={setPlaybackSpeed}
                        onRangeChange={setTimeRangeHours}
                    />
                )}

                {/* Boats Layer */}
                {Object.values(displayedBoats).map((boat) => (
                    boat.location && (
                        <Marker
                            key={boat.id}
                            position={[boat.location.lat, boat.location.lon]}
                            icon={createBoatIcon(boat.location.heading, isHistoryMode ? '#f97316' : '#0ea5e9')} // Orange for history, Blue for live
                        >
                            <Tooltip direction="top" offset={[0, -20]} opacity={1} permanent className="custom-boat-tooltip">
                                <span className="font-bold text-xs">{boat.name}</span>
                            </Tooltip>
                            <Popup className="glass-popup">
                                <div className="p-2">
                                    <h3 className="font-bold">{boat.name}</h3>
                                    <p className="text-xs">
                                        Speed: {boat.location.speed?.toFixed(1)} kts
                                        {isHistoryMode && <span className="block text-orange-400 font-mono text-[10px] mt-1">{new Date(boat.location.last_updated).toLocaleTimeString()}</span>}
                                    </p>
                                </div>
                            </Popup>
                        </Marker>
                    )
                ))}
            </MapContainer>
        </div>
    );
}
