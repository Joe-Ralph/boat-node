import * as THREE from 'three';

export const PALETTE = {
    magenta: '#D54DFF',
    cyan: '#00ffff',
    blueAccent: '#4488ff',
    cyanLight: '#00ccff',
    blueDeep: '#005599',
    ultramarine: '#031a2c',
    red: '#ff0000',
    amber: '#FFB347',
    offWhite: '#f5f0e8',
    white: '#ffffff',
    bgPage: '#020205',
    bgScene: '#111116',
    bgStorm: '#050810',
} as const;

export const PALETTE_THREE = {
    magenta: new THREE.Color(PALETTE.magenta),
    cyan: new THREE.Color(PALETTE.cyan),
    blueAccent: new THREE.Color(PALETTE.blueAccent),
    cyanLight: new THREE.Color(PALETTE.cyanLight),
    blueDeep: new THREE.Color(PALETTE.blueDeep),
    ultramarine: new THREE.Color(PALETTE.ultramarine),
    red: new THREE.Color(PALETTE.red),
    amber: new THREE.Color(PALETTE.amber),
    white: new THREE.Color(PALETTE.white),
};
