'use client';

import dynamic from 'next/dynamic';

import styles from './map-v2.module.css';

const BoatMap = dynamic(() => import('./BoatMap'), {
    ssr: false,
    loading: () => (
        <div className="w-full h-full flex items-center justify-center bg-secondary/20 rounded-xl animate-pulse min-h-[500px]">
            <p className="text-gray-400">Loading Map...</p>
        </div>
    ),
});

export default BoatMap;
