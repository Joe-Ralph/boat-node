import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { EngineContext, SceneSystem } from './EngineContext';
import { PALETTE } from './palette';

export interface EngineHandle {
    ctx: EngineContext;
}

interface Props {
    onReady: (ctx: EngineContext) => void | (() => void);
    className?: string;
    style?: React.CSSProperties;
}

const Engine: React.FC<Props> = ({ onReady, className, style }) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const cleanupRef = useRef<(() => void) | void>(undefined);

    useEffect(() => {
        if (!canvasRef.current) return;
        const isMobile = window.innerWidth <= 768;

        const scene = new THREE.Scene();
        const bgColor = new THREE.Color(PALETTE.bgScene).getHex();
        scene.fog = new THREE.FogExp2(bgColor, 0.005);
        scene.background = new THREE.Color(bgColor);

        const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        if (isMobile) {
            camera.position.set(-15, 5, 30);
            camera.lookAt(-15, 0.5, 0);
        } else {
            camera.position.set(-10, 5, 10);
            camera.lookAt(-10, 0.5, 0);
        }

        const renderer = new THREE.WebGLRenderer({
            canvas: canvasRef.current,
            antialias: true,
            alpha: true,
        });
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

        const clock = new THREE.Clock();
        const systems = new Set<SceneSystem>();
        const scrollProgress = { value: 0 };

        const ctx: EngineContext = {
            scene,
            camera,
            renderer,
            clock,
            isMobile,
            scrollProgress,
            registerSystem: (s) => systems.add(s),
            unregisterSystem: (s) => systems.delete(s),
        };

        let rafId = 0;
        const tick = () => {
            const dt = clock.getDelta();
            const t = clock.elapsedTime;
            systems.forEach((s) => {
                try {
                    s.update?.(dt, t, scrollProgress.value);
                } catch (err) {
                    console.warn('[Engine] system update error', err);
                }
            });
            renderer.render(scene, camera);
            rafId = requestAnimationFrame(tick);
        };

        const handleResize = () => {
            camera.aspect = window.innerWidth / window.innerHeight;
            camera.updateProjectionMatrix();
            renderer.setSize(window.innerWidth, window.innerHeight);
        };
        window.addEventListener('resize', handleResize);

        const cleanup = onReady(ctx);
        tick();

        return () => {
            cancelAnimationFrame(rafId);
            window.removeEventListener('resize', handleResize);
            if (typeof cleanup === 'function') cleanup();
            systems.forEach((s) => s.dispose?.());
            systems.clear();
            renderer.dispose();
        };
    }, []);

    return (
        <canvas
            ref={canvasRef}
            id="canvas-container"
            className={className ?? 'fixed top-0 left-0 w-full h-full z-0'}
            style={style ?? { transform: 'translateY(100vh)' }}
        />
    );
};

export default Engine;
