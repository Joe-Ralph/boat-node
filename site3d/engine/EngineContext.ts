import * as THREE from 'three';
import gsap from 'gsap';

export interface SceneSystem {
    update?(dt: number, t: number, scrollProgress: number): void;
    dispose?(): void;
}

export interface EngineContext {
    scene: THREE.Scene;
    camera: THREE.PerspectiveCamera;
    renderer: THREE.WebGLRenderer;
    clock: THREE.Clock;
    isMobile: boolean;
    registerSystem(system: SceneSystem): void;
    unregisterSystem(system: SceneSystem): void;
    scrollProgress: { value: number };
}

export interface SceneRegisterArgs<World> {
    tl: gsap.core.Timeline;
    ctx: EngineContext;
    world: World;
}
