'use client';

import { useState, useRef } from 'react';
import { Play, Pause, ChevronUp, ChevronDown, SkipForward, Settings } from 'lucide-react';
import styles from './timeline.module.css';

interface TimelineControlProps {
    minTime: number; // Timestamp
    maxTime: number; // Timestamp
    currentTime: number; // Timestamp
    onChange: (time: number) => void;
    onPlayPause: (isPlaying: boolean) => void;
    isPlaying: boolean;
    playbackSpeed: number;
    onSpeedChange: (speed: number) => void;
    onRangeChange: (hours: number) => void; // Load last X hours
}

export default function TimelineControl({
    minTime,
    maxTime,
    currentTime,
    onChange,
    onPlayPause,
    isPlaying,
    playbackSpeed,
    onSpeedChange,
    onRangeChange
}: TimelineControlProps) {
    const timeRef = useRef<HTMLDivElement>(null);

    // Helper to adjust time parts
    const adjustTime = (amount: number, unit: 'minutes' | 'hours' | 'days' | 'months') => {
        const date = new Date(currentTime);
        switch (unit) {
            case 'minutes':
                date.setMinutes(date.getMinutes() + amount);
                break;
            case 'hours':
                date.setHours(date.getHours() + amount);
                break;
            case 'days':
                date.setDate(date.getDate() + amount);
                break;
            case 'months':
                date.setMonth(date.getMonth() + amount);
                break;
        }
        let newTime = date.getTime();
        if (newTime > maxTime) newTime = maxTime;
        if (newTime < minTime) newTime = minTime;
        onChange(newTime);
    };

    // Prevent propagation to map
    const handleContainerClick = (e: React.MouseEvent) => {
        e.stopPropagation();
    };

    const date = new Date(currentTime);
    const day = date.getDate();
    const month = date.toLocaleDateString('en-US', { month: 'short' });
    const hours = date.getHours().toString().padStart(2, '0');
    const minutes = date.getMinutes().toString().padStart(2, '0');

    return (
        <div
            className={`leaflet-bottom leaflet-left ${styles.container}`}
            onClick={handleContainerClick}
            onDoubleClick={handleContainerClick}
        >
            <div className={styles.widget}>
                {/* Play/Pause Button */}
                <button
                    onClick={() => onPlayPause(!isPlaying)}
                    className={styles.playBtn}
                >
                    {isPlaying ? (
                        <Pause size={28} fill="white" />
                    ) : (
                        <Play size={28} fill="white" className="ml-1" />
                    )}
                </button>

                {/* Date/Time Spinners */}
                <div className={styles.timeDisplay}>

                    {/* Date User Group: Day Month */}
                    <div className={styles.dateGroup}>
                        {/* Day */}
                        <div className={styles.spinner}>
                            <button onClick={() => adjustTime(1, 'days')} className={styles.spinnerBtn}>
                                <ChevronUp size={14} />
                            </button>
                            <span className={styles.spinnerText}>{day}</span>
                            <button onClick={() => adjustTime(-1, 'days')} className={styles.spinnerBtn}>
                                <ChevronDown size={14} />
                            </button>
                        </div>

                        {/* Month */}
                        <div className={styles.spinner}>
                            <button onClick={() => adjustTime(1, 'months')} className={styles.spinnerBtn}>
                                <ChevronUp size={14} />
                            </button>
                            <span className={styles.spinnerText}>{month}</span>
                            <button onClick={() => adjustTime(-1, 'months')} className={styles.spinnerBtn}>
                                <ChevronDown size={14} />
                            </button>
                        </div>
                    </div>

                    {/* Time Use Group: Hour : Minute */}
                    <div className={styles.timeGroup}>
                        {/* Hour */}
                        <div className={styles.spinner}>
                            <button onClick={() => adjustTime(1, 'hours')} className={styles.spinnerBtn}>
                                <ChevronUp size={14} />
                            </button>
                            <span className={styles.spinnerText}>{hours}</span>
                            <button onClick={() => adjustTime(-1, 'hours')} className={styles.spinnerBtn}>
                                <ChevronDown size={14} />
                            </button>
                        </div>

                        <span className="pb-1">:</span>

                        {/* Minute */}
                        <div className={styles.spinner}>
                            <button onClick={() => adjustTime(10, 'minutes')} className={styles.spinnerBtn}>
                                <ChevronUp size={14} />
                            </button>
                            <span className={styles.spinnerText}>{minutes}</span>
                            <button onClick={() => adjustTime(-10, 'minutes')} className={styles.spinnerBtn}>
                                <ChevronDown size={14} />
                            </button>
                        </div>
                    </div>

                </div>

                {/* Speed / Settings Button Group */}
                <div className={styles.rightControls}>
                    {/* Speed Toggle */}
                    <button
                        onClick={() => onSpeedChange(playbackSpeed === 1 ? 10 : playbackSpeed === 10 ? 60 : playbackSpeed === 60 ? 120 : 1)}
                        className={styles.controlBtn}
                        title={`Speed: ${playbackSpeed}x`}
                    >
                        <SkipForward size={20} fill="rgba(255,255,255,0.8)" />
                        <span className={styles.speedBadge}>{playbackSpeed}x</span>
                    </button>

                    {/* Range Selector (Settings) */}
                    <div className={styles.settingsContainer}>
                        <button className={styles.settingsBtn}>
                            <Settings size={18} />
                        </button>

                        {/* Dropdown Menu */}
                        <div className={styles.dropdown}>
                            <div className={styles.dropdownHeader}>History Range</div>
                            {[1, 6, 12, 24, 168].map(hours => (
                                <button
                                    key={hours}
                                    onClick={() => onRangeChange(hours)}
                                    className={styles.dropdownItem}
                                >
                                    <span>Last {hours >= 24 ? `${hours / 24} Days` : `${hours} Hours`}</span>
                                </button>
                            ))}
                        </div>
                    </div>
                </div>
            </div>

            {/* Scrubber Slider */}
            <div className={styles.scrubberContainer}>
                <input
                    type="range"
                    min={minTime}
                    max={maxTime}
                    value={currentTime}
                    onChange={(e) => onChange(Number(e.target.value))}
                    className={styles.scrubber}
                    title="Scrub Timeline"
                />
            </div>
        </div>
    );
}
