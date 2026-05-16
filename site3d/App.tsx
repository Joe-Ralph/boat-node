/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

import Engine from './engine/Engine';
import { buildWorld, World } from './engine/World';
import { EngineContext, SceneSystem } from './engine/EngineContext';
import { ACT_SPECS, registerAllActs } from './scenes/SceneRegistry';
import { InvocationOverlay, registerInvocation } from './scenes/InvocationScene';
import { ActOverlay, registerAct } from './scenes/ActScene';
import StoryCopy from './ui/StoryCopy';
import ScrollProgress from './ui/ScrollProgress';
import { PALETTE } from './engine/palette';

gsap.registerPlugin(ScrollTrigger);

const INTRO_DUR = 1.2;
const ACT_OUTRO_DUR = 16;

const App: React.FC = () => {
    const scrollContainerRef = useRef<HTMLDivElement>(null);
    const invocationRef = useRef<HTMLDivElement>(null);
    const departureRef = useRef<HTMLDivElement>(null);
    const beyondSignalRef = useRef<HTMLDivElement>(null);
    const stormRef = useRef<HTMLDivElement>(null);
    const sosRef = useRef<HTMLDivElement>(null);
    const awakeningRef = useRef<HTMLDivElement>(null);
    const homeRef = useRef<HTMLDivElement>(null);
    const actRef = useRef<HTMLDivElement>(null);

    const totalActDur = ACT_SPECS.reduce((s, a) => s + a.duration, 0) + INTRO_DUR + ACT_OUTRO_DUR;
    const scrollHeightVh = Math.max(700, Math.round(totalActDur * 6));

    useEffect(() => {
        return () => {
            ScrollTrigger.getAll().forEach((t) => t.kill());
        };
    }, []);

    const onEngineReady = (ctx: EngineContext): (() => void) => {
        const world = buildWorld(ctx.scene);
        ctx.scene.background = world.bgColor;
        (ctx.scene.fog as THREE.FogExp2).color = world.bgColor;

        const tl = gsap.timeline({
            scrollTrigger: {
                trigger: scrollContainerRef.current,
                start: 'top top',
                end: 'bottom bottom',
                scrub: 1.5,
                onUpdate: (self) => {
                    ctx.scrollProgress.value = self.progress;
                },
            },
        });

        gsap.set(
            [
                departureRef.current,
                beyondSignalRef.current,
                stormRef.current,
                sosRef.current,
                awakeningRef.current,
                homeRef.current,
                actRef.current,
            ],
            { autoAlpha: 0 },
        );

        registerInvocation({
            tl,
            sectionRef: invocationRef,
            canvasEl: ctx.renderer.domElement,
            label: 'intro',
            start: 0,
        });

        const { storyEnd } = registerAllActs({
            tl,
            world,
            camera: ctx.camera,
            copies: {
                departure: { container: departureRef },
                beyondSignal: { container: beyondSignalRef },
                storm: { container: stormRef },
                sos: { container: sosRef },
                awakening: { container: awakeningRef },
                home: { container: homeRef },
            },
            isMobile: ctx.isMobile,
            introEnd: INTRO_DUR,
        });

        registerAct({
            tl,
            sectionRef: actRef,
            label: 'cta',
            start: storyEnd,
            duration: ACT_OUTRO_DUR,
        });

        const systems: SceneSystem[] = [];

        systems.push({
            update: (dt) => {
                const om = world.ocean.material;
                om.uniforms.uTime.value += dt * world.sceneParams.timeScale;
                om.uniforms.uWaveHeight.value = world.sceneParams.waveHeight;
                om.uniforms.uSurfaceColor.value.setRGB(
                    world.sceneParams.surfaceR,
                    world.sceneParams.surfaceG,
                    world.sceneParams.surfaceB,
                );
                ctx.scene.background = world.bgColor;
                (ctx.scene.fog as THREE.FogExp2).color.copy(world.bgColor);

                const waveY = Math.sin(om.uniforms.uTime.value) * world.sceneParams.waveHeight * 0.5;
                world.boat.group.position.y = 0.5 + waveY;
                world.boat.group.rotation.x = Math.sin(om.uniforms.uTime.value * 0.5) * world.sceneParams.waveHeight * 0.2;
                world.boat.group.rotation.z = Math.cos(om.uniforms.uTime.value * 0.3) * world.sceneParams.waveHeight * 0.1;

                world.ambientGroup.children.forEach((b, i) => {
                    const phase = i;
                    const wH = world.sceneParams.waveHeight;
                    b.position.y = 0.5 + Math.sin(om.uniforms.uTime.value + phase) * wH * 0.5;
                    b.rotation.x = Math.sin(om.uniforms.uTime.value * 0.5 + phase) * wH * 0.2;
                    b.rotation.z = Math.cos(om.uniforms.uTime.value * 0.3 + phase) * wH * 0.1;
                });

                world.mesh.nodes.forEach((node, i) => {
                    const phase = i * 2;
                    const wH = world.sceneParams.waveHeight;
                    node.mesh.position.y = 0.5 + Math.sin(om.uniforms.uTime.value + phase) * wH * 0.5;
                    node.mesh.rotation.x = Math.sin(om.uniforms.uTime.value * 0.5 + phase) * wH * 0.2;
                    node.mesh.rotation.z = Math.cos(om.uniforms.uTime.value * 0.3 + phase) * wH * 0.1;
                });
            },
        });

        systems.push({
            update: (dt) => {
                const t = world.ocean.material.uniforms.uTime.value;
                if (world.terrain.material.opacity > 0.01 && world.towerSignalState.opacity > 0.01) {
                    world.pulseRings.forEach((ring) => {
                        const r = (t * world.pulseParams.speed + (ring.userData.phase as number)) % world.pulseParams.maxRadius;
                        ring.scale.setScalar(r);
                        const norm = r / world.pulseParams.maxRadius;
                        const op = (1 - norm) * (1 - norm);
                        const fadeIn = Math.min(r, 2) / 2;
                        (ring.material as THREE.Material & { opacity: number }).opacity =
                            op * fadeIn * 0.8 * world.terrain.material.opacity * world.towerSignalState.opacity;
                        ring.visible = true;
                    });
                } else {
                    world.pulseRings.forEach((r) => (r.visible = false));
                }
            },
        });

        systems.push({
            update: (dt) => {
                const sphere = world.boat.pulseSphere;
                const mat = sphere.material as THREE.Material & { opacity: number };
                if (mat.opacity > 0.01) {
                    sphere.visible = true;
                    const t = world.ocean.material.uniforms.uTime.value;
                    const sosSpeed = 1.5;
                    const s = 1 + (t * sosSpeed) % 15;
                    sphere.scale.setScalar(s);
                    const op = 1 - s / 15;
                    mat.opacity = mat.opacity * op;
                } else {
                    sphere.visible = false;
                }
            },
        });

        systems.push({
            update: (dt) => {
                if (!world.meshAnim.active) return;
                world.meshAnim.loopTimer += dt;

                const chain = [
                    world.boat.group.position,
                    world.mesh.nodes[0].mesh.position,
                    world.mesh.nodes[1].mesh.position,
                    world.mesh.nodes[2].mesh.position,
                    world.mesh.nodes[3].mesh.position,
                    world.mesh.nodes[4].mesh.position,
                    new THREE.Vector3(-20, 8, 0),
                ];

                const PULSE_SPEED = 30.0;
                const getRing = (step: number): THREE.Mesh | null => {
                    if (step === 0) return world.boat.signalRing;
                    if (step > 0 && step <= 5) return world.mesh.nodes[step - 1].signalRing;
                    return null;
                };

                const positionsArr = world.mesh.arcLines.geometry.attributes.position.array as Float32Array;
                let idx = 0;

                const drawLine = (p1: THREE.Vector3, p2: THREE.Vector3, progress: number) => {
                    const mid = new THREE.Vector3().lerpVectors(p1, p2, 0.5);
                    mid.y += p1.distanceTo(p2) * 0.4;
                    const curve = new THREE.QuadraticBezierCurve3(p1, mid, p2);
                    const points = curve.getPoints(world.mesh.segmentsPerLine - 1);
                    const limit = Math.floor(points.length * progress);
                    for (let k = 0; k < limit; k++) {
                        if (k >= points.length - 1) break;
                        positionsArr[idx++] = points[k].x;
                        positionsArr[idx++] = points[k].y;
                        positionsArr[idx++] = points[k].z;
                        positionsArr[idx++] = points[k + 1].x;
                        positionsArr[idx++] = points[k + 1].y;
                        positionsArr[idx++] = points[k + 1].z;
                    }
                };

                if (world.meshAnim.step >= chain.length - 1) {
                    if (world.meshAnim.loopTimer > 2.0) {
                        world.meshAnim.step = 0;
                        world.meshAnim.loopTimer = 0;
                        world.meshAnim.pulseRadius = 0;
                        positionsArr.fill(0);
                    }
                } else if (world.meshAnim.step === -1) {
                    if (world.meshAnim.loopTimer > 1.0) {
                        world.meshAnim.step = 0;
                        world.meshAnim.loopTimer = 0;
                        world.meshAnim.pulseRadius = 0;
                    }
                } else {
                    for (let k = 0; k < world.meshAnim.step; k++) {
                        drawLine(chain[k], chain[k + 1], 1.0);
                    }
                    const i = world.meshAnim.step;
                    const p1 = chain[i];
                    const p2 = chain[i + 1];
                    const distToNext = p1.distanceTo(p2);
                    world.meshAnim.pulseRadius += dt * PULSE_SPEED;
                    const ring = getRing(i);
                    if (ring) {
                        ring.visible = true;
                        ring.scale.setScalar(world.meshAnim.pulseRadius);
                        const op = Math.max(0, 1 - world.meshAnim.pulseRadius / 30);
                        (ring.material as THREE.Material & { opacity: number }).opacity = op;
                        ((ring.material as THREE.MeshBasicMaterial).color as THREE.Color).setHex(0x00ffff);
                    }
                    const progress = Math.min(1, world.meshAnim.pulseRadius / distToNext);
                    drawLine(p1, p2, progress);
                    if (world.meshAnim.pulseRadius >= distToNext) {
                        drawLine(p1, p2, 1.0);
                        world.meshAnim.step++;
                        world.meshAnim.pulseRadius = 0;
                        if (ring) ring.visible = false;
                    }
                }
                for (let k = idx; k < positionsArr.length; k++) positionsArr[k] = 0;
                world.mesh.arcLines.geometry.attributes.position.needsUpdate = true;
            },
        });

        systems.push({
            update: (dt, t) => {
                world.rain.update(dt, world.rainDensity.value);
                world.harborLights.update(t);
            },
        });

        systems.forEach((s) => ctx.registerSystem(s));

        return () => {
            tl.scrollTrigger?.kill();
            tl.kill();
            systems.forEach((s) => ctx.unregisterSystem(s));
        };
    };

    return (
        <>
            <Engine onReady={onEngineReady} />

            <div
                ref={scrollContainerRef}
                className="relative w-full"
                style={{ height: `${scrollHeightVh}vh` }}
            />

            <ScrollProgress targetRef={scrollContainerRef} />

            <div className="fixed top-0 left-0 w-full h-full pointer-events-none z-10 flex flex-col">
                <InvocationOverlay sectionRef={invocationRef} />

                <StoryCopy
                    ref={departureRef}
                    title="Departure"
                    titleColor={PALETTE.amber}
                    lines={[
                        'Before dawn, someone leaves for work.',
                        'A family waits behind the harbor lamps.',
                    ]}
                />
                <StoryCopy
                    ref={beyondSignalRef}
                    title="Beyond Signal"
                    titleColor={PALETTE.magenta}
                    lines={[
                        'The shore goes quiet.',
                        'No bars. No signal. No one knows where he is.',
                    ]}
                />
                <StoryCopy
                    ref={stormRef}
                    title="The Storm"
                    titleColor="#88aacc"
                    lines={[
                        'Then the sea forgets him.',
                    ]}
                />
                <StoryCopy
                    ref={sosRef}
                    title="S O S"
                    titleColor={PALETTE.red}
                    lineClass="font-mono uppercase tracking-widest"
                    lines={[
                        'And no one is coming.',
                    ]}
                />
                <StoryCopy
                    ref={awakeningRef}
                    title="Neduvaai Wakes"
                    titleColor={PALETTE.cyan}
                    lines={[
                        'Boat to boat.',
                        'Node to node.',
                        'Shore to family.',
                    ]}
                />
                <StoryCopy
                    ref={homeRef}
                    title="Home"
                    titleColor={PALETTE.amber}
                    lines={[
                        'A mesh that doesn’t forget anyone.',
                    ]}
                />

                <ActOverlay sectionRef={actRef} />
            </div>
        </>
    );
};

export default App;
