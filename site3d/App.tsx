/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */
import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import LandingOverlay from './components/LandingOverlay';
import { createLowPolyBoat } from './engine/utils/createLowPolyBoat';
import { createOcean } from './engine/utils/createOcean';
import { createTerrain } from './engine/utils/createTerrain';
import { createTower } from './engine/utils/createTower';

gsap.registerPlugin(ScrollTrigger);

const App: React.FC = () => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const scrollContainerRef = useRef<HTMLDivElement>(null);

    const section0Ref = useRef<HTMLDivElement>(null);
    const section1Ref = useRef<HTMLDivElement>(null);
    const section2Ref = useRef<HTMLDivElement>(null);
    const section3Ref = useRef<HTMLDivElement>(null);
    const section35Ref = useRef<HTMLDivElement>(null); // NEW: Neduvaai Activates
    const section4Ref = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (!canvasRef.current) return;

        const isMobile = window.innerWidth <= 768;

        // --- SCENE SETUP ---
        const scene = new THREE.Scene();
        // "make a slightly gray so the ocean shader, deep blue will be visible"
        // #111116 or similar dark gray-blue
        const bgColor = 0x111116;
        scene.fog = new THREE.FogExp2(bgColor, 0.005); // Reduced fog density to see full scene on zoom out
        scene.background = new THREE.Color(bgColor);

        const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
        // Start camera relative to boat start
        // Mobile: Zoom out (z=30) and pan left (x=-15) to see Tower (-20) and Boat (-10)
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
            alpha: true
        });
        renderer.setSize(window.innerWidth, window.innerHeight);
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

        // --- CONFIG & COLORS ---
        const colors = {
            neonMagenta: new THREE.Color(0xff00ff),
            neonCyan: new THREE.Color(0xD54DFF), // VIOLET (Renamed concept, kept variable name for compatibility)
            lightBlue: new THREE.Color(0x0077be),
            darkBlue: new THREE.Color(0x005599),
            dangerRed: new THREE.Color(0xff0000),
            white: new THREE.Color(0xffffff),
            safeZoneRing: new THREE.Color(0xD54DFF), // Violet (Brighter)
        };

        // --- OBJECTS ---

        // 1. OCEAN
        const { ocean, material: oceanMaterial } = createOcean(colors.lightBlue);
        scene.add(ocean);

        // 2. SHORE & TOWER
        const shoreGroup = new THREE.Group();

        // Procedural Low-Poly Terrain
        const { mesh: landMesh, material: landMat, getHeight: getTerrainHeight } = createTerrain();
        shoreGroup.add(landMesh);

        // 4. Red Cell Tower (lattice + platform + antenna + dishes)
        const { group: towerGroup, towerMaterial: towerMat, edgeMaterial: shoreEdgeMat } = createTower();
        towerGroup.position.set(-20, 0.1, 0);
        shoreGroup.add(towerGroup);

        // Group materials for easier fading later
        const shoreMaterials: THREE.Material[] = [shoreEdgeMat, towerMat, landMat];

        // 5. Trees & Houses (Low Poly)
        const trunkMat = new THREE.MeshBasicMaterial({ color: 0x8B4513, transparent: true, opacity: 1 });
        const foliageMat = new THREE.MeshBasicMaterial({ color: 0x228B22, transparent: true, opacity: 1 });
        const houseMat = new THREE.MeshBasicMaterial({ color: 0xeeeeee, transparent: true, opacity: 1 });
        const roofMat = new THREE.MeshBasicMaterial({ color: 0x8B0000, transparent: true, opacity: 1 });
        shoreMaterials.push(trunkMat, foliageMat, houseMat, roofMat);

        // Trees (Lining the "Street")
        const treePositions = [
            [-20, -45], [-20, -35], [-20, -25], [-20, -15], [-20, -5], [-20, 5], [-20, 15], [-20, 25], [-20, 35], [-20, 45], // Front row
            [-30, -45], [-30, -35], [-30, -25], [-30, -15], [-30, -5], [-30, 5], [-30, 15], [-30, 25], [-30, 35], [-30, 45]  // Back row
        ];

        treePositions.forEach(pos => {
            const treeGroup = new THREE.Group();
            // Trunk
            const trunkGeo = new THREE.CylinderGeometry(0.2, 0.2, 1, 6);
            const trunk = new THREE.Mesh(trunkGeo, trunkMat);
            trunk.position.y = 0.5; // Base at 0

            // Trunk Edges
            const trunkEdges = new THREE.EdgesGeometry(trunkGeo);
            const trunkLines = new THREE.LineSegments(trunkEdges, shoreEdgeMat);
            trunk.add(trunkLines);

            // Foliage
            const foliageGeo = new THREE.ConeGeometry(0.8, 2, 6);
            const foliage = new THREE.Mesh(foliageGeo, foliageMat);
            foliage.position.y = 1 + 1; // On top of trunk

            // Foliage Edges
            const foliageEdges = new THREE.EdgesGeometry(foliageGeo);
            const foliageLines = new THREE.LineSegments(foliageEdges, shoreEdgeMat);
            foliage.add(foliageLines);

            treeGroup.add(trunk, foliage);

            treeGroup.position.set(pos[0], getTerrainHeight(pos[0], pos[1]), pos[1]); // Placed on terrain
            shoreGroup.add(treeGroup);
        });

        // Houses (Ordered Row behind tower)
        const housePositions = [
            [-25, -50], [-25, -40], [-25, -30], [-25, -20], [-25, -10],
            [-25, 0],
            [-25, 10], [-25, 20], [-25, 30], [-25, 40], [-25, 50]
        ];

        housePositions.forEach((pos, i) => {
            const houseGroup = new THREE.Group();
            // Deterministic size using index
            const w = 2 + (i % 3) * 0.5;
            const d = 2 + ((i + 1) % 3) * 0.5;
            const h = 1.5;
            const houseGeo = new THREE.BoxGeometry(w, h, d);
            const house = new THREE.Mesh(houseGeo, houseMat);
            house.position.y = h / 2;

            // House Edges
            const houseEdges = new THREE.EdgesGeometry(houseGeo);
            const houseLines = new THREE.LineSegments(houseEdges, shoreEdgeMat);
            house.add(houseLines);

            const roofGeo = new THREE.ConeGeometry(Math.max(w, d) * 0.8, 1, 4);
            const roof = new THREE.Mesh(roofGeo, roofMat);
            roof.position.y = h + 0.5;
            roof.rotation.y = Math.PI / 4;

            // Roof Edges
            const roofEdges = new THREE.EdgesGeometry(roofGeo);
            const roofLines = new THREE.LineSegments(roofEdges, shoreEdgeMat);
            roof.add(roofLines);

            houseGroup.add(house, roof);
            houseGroup.position.set(pos[0], getTerrainHeight(pos[0], pos[1]), pos[1]); // Placed on terrain
            shoreGroup.add(houseGroup);
        });

        // Signal Pulse (Origin from Tower Tip)
        // Tower tip is now higher due to antenna mast (6 + 2 = 8)
        const towerTipY = 8.0;

        const pulseParams = {
            speed: 10.0, // Slowed down slightly
            maxRadius: 45, // Reduced from 80 to 45 (Short range)
            count: 3 // Increased count
        };
        const pulseRings: THREE.Mesh[] = [];
        const pulseMat = new THREE.MeshBasicMaterial({
            color: colors.safeZoneRing, // Violet
            transparent: true,
            opacity: 0.8,
            side: THREE.DoubleSide,
            depthWrite: false // Fix Z-fighting
        });

        for (let i = 0; i < pulseParams.count; i++) {
            const ringGeo = new THREE.RingGeometry(0.99, 1.0, 64); // Ultrathin ring (0.99 to 1.0)
            const ring = new THREE.Mesh(ringGeo, pulseMat.clone());
            ring.rotation.x = -Math.PI / 2;
            // Origin: "tip of the tower"
            // Origin: "tip of the tower"
            ring.position.set(-20, towerTipY + (i * 0.01), 0); // Slight offset to prevent Z-fighting

            ring.userData = {
                phase: (i / pulseParams.count) * pulseParams.maxRadius
            };
            shoreGroup.add(ring);
            pulseRings.push(ring);
        }
        scene.add(shoreGroup);

        // 3. MAIN BOAT
        const { group: boatGroup, mat: boatMat, glowMat, glow, pulseSphere: boatPulseSphere, signalRing: mainSignalRing } = createLowPolyBoat(colors.white);
        // Start position: Inside safe zone
        // "start the boat from the shore" -> "start from the point where land meets ocean"
        // Land Low is at -20, width 20 -> Extends -30 to -10.
        // So -10 is the edge.
        boatGroup.position.set(-10, 0.5, 0);
        scene.add(boatGroup);


        // 4. MESH NETWORK (Other boats)
        const meshGroup = new THREE.Group();
        meshGroup.visible = false;

        // Structure to hold boat + its signal ring
        const otherBoatsData: { mesh: THREE.Group, pos: THREE.Vector3, signalRing: THREE.Mesh }[] = [];

        const predefinedPos = [
            [45, 0, -5],
            [30, 0, 8],
            [15, 0, -6],
            [0, 0, 5],
            [-5, 0, -2] // Connects to Land (Moved from -15 to -5 to be in water)
        ];

        predefinedPos.forEach((pos, idx) => {
            const { group: bGroup, signalRing } = createLowPolyBoat(colors.neonCyan);
            bGroup.position.set(pos[0], 0.5, pos[2]);
            bGroup.rotation.y = Math.PI / 2;
            meshGroup.add(bGroup);
            otherBoatsData.push({
                mesh: bGroup,
                pos: new THREE.Vector3(pos[0], 0.5, pos[2]),
                signalRing: signalRing
            });
        }); // Closing bracket for predefinedPos.forEach

        // 5. AMBIENT BOATS (Non-Mesh Background)
        // "introduce more boats, so it doesn't look like we have only boats that are necessary"
        const ambientGroup = new THREE.Group();
        const ambientCount = 15;
        for (let i = 0; i < ambientCount; i++) {
            const { group: bGroup } = createLowPolyBoat(colors.white); // Neutral color
            const x = (Math.random() - 0.5) * 100 + 40; // Spread wide, mostly far out
            let z = (Math.random() - 0.5) * 80;
            // Avoid placing on top of main chain (approx z=0)
            if (Math.abs(z) < 10) z += 20 * (Math.sign(z) || 1);

            bGroup.position.set(x, 0.5, z);
            bGroup.rotation.y = Math.random() * Math.PI * 2;
            // Dimmer?
            bGroup.traverse((c) => {
                if (c instanceof THREE.Mesh && c.material) {
                    // Clone material to dim
                    if (c.material.color) {
                        c.material = c.material.clone();
                        c.material.color.setHex(0x555555); // Grayed out
                    }
                }
            });
            ambientGroup.add(bGroup);
        }
        scene.add(ambientGroup);

        // Connection Lines (Arcs)
        const lineMat = new THREE.LineBasicMaterial({ color: 0x00FFFF, transparent: true, opacity: 0 }); // Start invisible, Electric Cyan for Contrast
        const segmentsPerLine = 30; // Points per arc

        // Define Connections manually or via distance
        // Main Boat connects to Boat 0
        // Boat 0 connects to Boat 1
        // ...
        // Boat 4 connects to Tower (Shore)

        // We will build a list of "Active Arcs" that get animated sequentially.
        // Each Arc: { start: Vec3, end: Vec3, progress: 0-1 }
        // We need dynamic line drawing.
        // Let's use many separate Line loops? Or one big BufferGeometry but we control "drawRange" or opacity via attributes?
        // Easiest: One big geometry, but we only create/update vertices for "active" lines.

        // Capacity: Main->0, 0->1, 1->2, 2->3, 3->4, 4->Tower. Total 6 hops.
        const maxHops = 10;
        const vertexCount = maxHops * (segmentsPerLine - 1) * 2;
        const arcPositions = new Float32Array(vertexCount * 3);
        const arcGeo = new THREE.BufferGeometry();
        arcGeo.setAttribute('position', new THREE.BufferAttribute(arcPositions, 3));

        const arcLines = new THREE.LineSegments(arcGeo, lineMat);
        arcLines.frustumCulled = false;
        meshGroup.add(arcLines);

        // State for animation
        const meshAnimState = {
            active: false,
            // Loop state
            loopTimer: 0,

            // Animation internals
            step: -1, // -1: Waiting, 0: Main->0, 1: 0->1 ...
            pulseRadius: 0
        };

        scene.add(meshGroup);

        // --- ANIMATION TIMELINE ---
        const sceneParams = {
            timeScale: 0.5, // Slow calm waves initially
            waveHeight: 0.2,
            surfaceR: colors.lightBlue.r,
            surfaceG: colors.lightBlue.g,
            surfaceB: colors.lightBlue.b
        };

        const tl = gsap.timeline({
            scrollTrigger: {
                trigger: scrollContainerRef.current,
                start: "top top",
                end: "bottom bottom",
                scrub: 1.5, // slightly more smooth scrub
            }
        });

        // Initialize sections with autoAlpha: 0 to correct visibility handling
        gsap.set([section1Ref.current, section2Ref.current, section3Ref.current, section35Ref.current], { autoAlpha: 0 });

        // === ACT 0: INTRO REVEAL ===
        // "intro section scroll upwards and bring 3d scene from below"
        tl.addLabel("intro", 0);

        // Intro Animation - Act 0 to Act 1
        // "Zoom Through" Effect: Scale up HUGE (100x) and keep opacity longer to fly through logo
        tl.to(section0Ref.current, { scale: 100, duration: 1.0, ease: "power4.in" }, "start");
        tl.to(section0Ref.current, { opacity: 0, duration: 0.5 }, "start+=0.5"); // Fade out only at the very end

        // Ensure Section 0 is disabled after zoom
        tl.set(section0Ref.current, { pointerEvents: "none" }, "start+=1.0");

        // Slide Canvas UP (100vh -> 0)
        // Note: Canvas needs initial style y: 100vh (Handled in JSX)
        tl.to(canvasRef.current, { y: "0vh", ease: "none", duration: 1.0 }, "intro");

        // State for Tower Signal Animation Start
        const towerSignalState = { opacity: 0 };

        // === ACT 1: LEAVING THE SHORE (0% - 25%) ===
        tl.addLabel("start", ">"); // Start Act 1 AFTER intro slide completes

        // Activate Tower Signal when boat starts moving
        tl.to(towerSignalState, { opacity: 1, duration: 1 }, "start");

        // Scene Logic Starts ->
        tl.to(sceneParams, {
            waveHeight: 1.5,
            timeScale: 1.5,
            duration: 5
        }, "start");

        // Animate Lines Staggered
        const q1 = gsap.utils.selector(section1Ref.current);
        tl.to(section1Ref.current, { autoAlpha: 1, duration: 0.1 }, "start+=10"); // Container visible
        tl.to(q1(".story-line"), { opacity: 1, duration: 1, stagger: 1.5 }, "start+=10.1");


        // Move Boat OUT
        // Boat moves from -20 to -5 (Edge of Safe Zone)
        // "strech ... look like it took more time"
        const departureDur = 25; // Increased from 15 to 25 (User requested longer duration)
        // Easing changed to "power1.in" (Accelerate out) to blend with next movement
        tl.to(boatGroup.position, { x: 10, z: 0, duration: departureDur, ease: "power1.in" }, "start+=2"); // Target x=10 (Further out)
        // Mobile: Maintain z=30 distance. Desktop: Zoom to z=12.
        tl.to(camera.position, { x: 10, z: isMobile ? 30 : 12, duration: departureDur, ease: "power1.in" }, "start+=2"); // Follow boat to x=10
        // UI Fades
        // UI Fades Out
        tl.to(q1(".story-line"), { opacity: 0, duration: 1, stagger: 0.5 }, `start+=${departureDur - 4}`);
        tl.to(section1Ref.current, { autoAlpha: 0, duration: 0.5 }, `start+=${departureDur - 2}`);


        // GRADUAL TRANSITION ZONE

        // === ACT 2: THE DEEP (50% - 75%) ===
        // "feeling of scrolling stuck when Leaving the shore... and The silent dark"
        // This is due to long delays between labels where nothing happens.
        // We need overlapping motion.

        const deepMoveDur = 25;

        // Overlap Deep Start with Departure End
        // "pause on scroll... make smooth" -> Remove dead zone offset.
        // Departure ends at: start + 2 (delay) + 15 (dur) = start + 17.
        // We start Deep at start + 15 (2s Overlap) to blend the motion.
        tl.addLabel("deep", `start+=${departureDur}`); // start+15 (Overlap 2s)

        // "no land should be visible when we are in the deep screen"
        // Move boat FAR OUT.
        // Start Linear motion immediately to pick up momentum
        tl.to(boatGroup.position, { x: 60, z: 0, duration: deepMoveDur, ease: "none" }, "deep");
        tl.to(camera.position, { x: 60, z: 8, y: 4, duration: deepMoveDur, ease: "none" }, "deep");

        // HIDE ISLAND/RADAR Visually using Opacity Fade (Reversible)
        // "moving down... fix this issue" -> Fade out instead.
        // Delay fade out until boat is further out
        tl.to(shoreMaterials, { opacity: 0, duration: 2 }, "deep+=10"); // Moved to +10 (was +5)

        // Slow gradual wave increase
        tl.to(sceneParams, {
            waveHeight: 2.5,
            timeScale: 3.0,
            surfaceR: colors.darkBlue.r,
            surfaceG: colors.darkBlue.g,
            surfaceB: colors.darkBlue.b,
            duration: deepMoveDur
        }, "deep");

        // UI
        // Show Deep Text Staggered
        const q2 = gsap.utils.selector(section2Ref.current);
        tl.to(section2Ref.current, { autoAlpha: 1, duration: 0.1 }, "deep");
        tl.to(q2(".story-line"), { opacity: 1, duration: 1, stagger: 1.5 }, "deep+=0.1");

        tl.to(q2(".story-line"), { opacity: 0, duration: 1, stagger: 0.5 }, `deep+=${deepMoveDur - 7}`);
        tl.to(section2Ref.current, { autoAlpha: 0, duration: 0.5 }, `deep+=${deepMoveDur - 5}`);


        // === ACT 3: BLACKOUT (75% - 90%) ===
        tl.addLabel("blackout", `deep+=${deepMoveDur}`);

        const blackoutDur = 25; // Increased from ~7 to 25 to match other sections

        // Boat turns Red
        tl.to(boatMat.color, { r: 1, g: 0, b: 0, duration: 0.5 }, "blackout");

        // SOS Pulse Sphere
        // Reveal it
        // Use opacity control for reversibility.
        // "red sos sphere, still pulses even when we scroll back" -> Handled by opacity logic in tick
        tl.to(boatPulseSphere.material, { opacity: 0.5, duration: 0.5 }, "blackout"); // Set base opacity to trigger tick logic
        // Also ensure visible is handled? No, just rely on opacity.
        // But we need to toggle 'visible' to avoid tick processing if unwanted?
        // Actually, let's use a scale tween to pop it in.
        tl.to(boatPulseSphere.scale, { x: 1, y: 1, z: 1, duration: 0 }, "blackout"); // Reset scale

        const q3 = gsap.utils.selector(section3Ref.current);
        tl.to(section3Ref.current, { autoAlpha: 1, duration: 0.1 }, "blackout+=1");
        tl.to(q3(".story-line"), { opacity: 1, duration: 1, stagger: 1.5 }, "blackout+=1.1");

        tl.to(q3(".story-line"), { opacity: 0, duration: 1, stagger: 0.5 }, `blackout+=${blackoutDur - 6}`);
        tl.to(section3Ref.current, { autoAlpha: 0, duration: 0.5 }, `blackout+=${blackoutDur - 2}`);


        // === ACT 3.5: NEDUVAAI ACTIVATES (90% - 95%) ===
        tl.addLabel("activates", `blackout+=${blackoutDur}`); // Was blackout+=7

        const q35 = gsap.utils.selector(section35Ref.current);
        tl.to(section35Ref.current, { autoAlpha: 1, duration: 0.1 }, "activates");
        tl.to(q35(".story-line"), { opacity: 1, duration: 1, stagger: 1 }, "activates+=0.1");


        // Boat turns Violet (Neon Brighter)
        tl.to(boatMat.color, { r: 0.835, g: 0.301, b: 1.0, duration: 0.5 }, "activates");

        // Stop SOS Rings/Sphere
        // "when neduvaai activates remove the sos red signal"
        tl.to(boatPulseSphere.material, { opacity: 0, duration: 0.2 }, "activates");

        // Start Mesh Animation Trigger
        // We use a proxy object to control 'active' state via GSAP to ensure reversibility.
        const meshProxy = { value: 0 };
        tl.to(meshProxy, {
            value: 1,
            duration: 0.1,
            onUpdate: () => {
                if (meshProxy.value > 0.5) {
                    meshAnimState.active = true;
                    meshGroup.visible = true;
                    lineMat.opacity = 1;
                    // Note: Resetting timer continuously if we just sit here?
                    // We need to Detect EDGE.
                } else {
                    meshAnimState.active = false;
                    meshGroup.visible = false;
                    lineMat.opacity = 0;
                    // Clear lines on reverse?
                    const positionsArr = arcLines.geometry.attributes.position.array as Float32Array;
                    positionsArr.fill(0);
                    arcLines.geometry.attributes.position.needsUpdate = true;
                }
            },
            onReverseComplete: () => {
                // Double ensure closure
                meshAnimState.active = false;
                meshGroup.visible = false;
            }
        }, "activates");

        // Re-show Land
        // Fade Opacity back to 1
        tl.to([landMat, towerMat], { opacity: 1, duration: 2 }, "activates");

        const activatesDur = 20; // Increased spacing for reading Neduvaai Online part

        tl.to(q35(".story-line"), { opacity: 0, duration: 1, stagger: 0.5 }, `activates+=${activatesDur - 5}`);
        tl.to(section35Ref.current, { opacity: 0, duration: 0.5 }, `activates+=${activatesDur - 3.5}`);


        // === ACT 4: CONNECTION (95% - 100%) ===
        tl.addLabel("connection", `activates+=${activatesDur}`);

        // Camera zoom out to see everything
        // Needs to see from x=60 all the way to x=-50 (Land)
        // High Y, Mid Z.
        // Mobile: Needs much higher Y (150) to fit horizontal width in portrait
        tl.to(camera.position, { x: 20, y: isMobile ? 150 : 60, z: 20, duration: 4, ease: "power2.inOut" }, "connection");
        tl.to(camera.lookAt, { x: 0, y: 0, z: 0 }, "connection"); // Won't work with OrbitControls or manual pos/rot, better rotate
        tl.to(camera.rotation, { x: -Math.PI / 2, y: 0, z: 0, duration: 4 }, "connection");


        // 5. FINALLY Show the Card
        // (Now handled by static HTML flow @ bottom)
        // tl.fromTo(section4Ref.current, { opacity: 0 }, { opacity: 1, duration: 1 }, "connection+=3");


        // --- RENDER LOOP ---
        const clock = new THREE.Clock();

        const tick = () => {
            const delta = clock.getDelta();
            // Manually accumulate time based on variable timeScale
            oceanMaterial.uniforms.uTime.value += delta * sceneParams.timeScale;

            oceanMaterial.uniforms.uWaveHeight.value = sceneParams.waveHeight;
            oceanMaterial.uniforms.uSurfaceColor.value.setRGB(sceneParams.surfaceR, sceneParams.surfaceG, sceneParams.surfaceB);

            // Bobbing boat logic
            const waveY = Math.sin(oceanMaterial.uniforms.uTime.value) * sceneParams.waveHeight * 0.5;
            boatGroup.position.y = 0.5 + waveY;

            // Pitch/Roll based on wave intensity
            boatGroup.rotation.x = Math.sin(oceanMaterial.uniforms.uTime.value * 0.5) * sceneParams.waveHeight * 0.2;
            boatGroup.rotation.z = Math.cos(oceanMaterial.uniforms.uTime.value * 0.3) * sceneParams.waveHeight * 0.1;


            // Update Lines Animation (Pulse-then-Connect) WITH LOOPING
            if (meshAnimState.active) {
                // Loop handling
                meshAnimState.loopTimer += delta;

                // Define Chain
                // Define Chain (Dynamic Positions)
                const chain = [
                    boatGroup.position,
                    otherBoatsData[0].mesh.position,
                    otherBoatsData[1].mesh.position,
                    otherBoatsData[2].mesh.position,
                    otherBoatsData[3].mesh.position,
                    otherBoatsData[4].mesh.position,
                    new THREE.Vector3(-20, 8, 0) // Tower Tip
                ];

                const PULSE_SPEED = 30.0; // Fast data transmission

                // Helper to get SignalRing for a step
                const getSignalRing = (step: number) => {
                    if (step === 0) return mainSignalRing;
                    if (step > 0 && step <= 5) return otherBoatsData[step - 1].signalRing; // step 1 is boat 0
                    return null;
                };

                const positionsArr = arcLines.geometry.attributes.position.array as Float32Array;
                let idx = 0;

                const drawLine = (p1: THREE.Vector3, p2: THREE.Vector3, progress: number) => {
                    const mid = new THREE.Vector3().lerpVectors(p1, p2, 0.5);
                    mid.y += p1.distanceTo(p2) * 0.4;
                    const curve = new THREE.QuadraticBezierCurve3(p1, mid, p2);
                    const points = curve.getPoints(segmentsPerLine - 1);

                    // Draw subset based on progress
                    const limit = Math.floor(points.length * progress);
                    for (let k = 0; k < limit; k++) { // k < points.length - 1
                        if (k >= points.length - 1) break;

                        positionsArr[idx++] = points[k].x;
                        positionsArr[idx++] = points[k].y;
                        positionsArr[idx++] = points[k].z;

                        positionsArr[idx++] = points[k + 1].x;
                        positionsArr[idx++] = points[k + 1].y;
                        positionsArr[idx++] = points[k + 1].z;
                    }
                };

                // Reset Logic (Loop)
                // If we finished the chain, wait a bit then reset
                if (meshAnimState.step >= chain.length - 1) {
                    if (meshAnimState.loopTimer > 2.0) { // 2 Seconds pause after completion
                        // Reset
                        meshAnimState.step = 0;
                        meshAnimState.loopTimer = 0;
                        meshAnimState.pulseRadius = 0;

                        // Clear lines for new pulse
                        positionsArr.fill(0);
                        arcLines.geometry.attributes.position.needsUpdate = true;
                    }
                } else if (meshAnimState.step === -1) {
                    // Initial Wait
                    if (meshAnimState.loopTimer > 1.0) {
                        meshAnimState.step = 0;
                        meshAnimState.loopTimer = 0;
                        meshAnimState.pulseRadius = 0;
                    }
                } else {
                    // Re-render PREVIOUS fully connected lines to keep them visible during the chain
                    for (let k = 0; k < meshAnimState.step; k++) {
                        drawLine(chain[k], chain[k + 1], 1.0);
                    }

                    // Logic: Pulse expands -> Reaches Next -> Draw Line -> Move to Next Step
                    const i = meshAnimState.step;
                    const p1 = chain[i];
                    const p2 = chain[i + 1];
                    const distToNext = p1.distanceTo(p2);

                    meshAnimState.pulseRadius += delta * PULSE_SPEED;

                    // Pulse Visuals
                    const ring = getSignalRing(i);
                    if (ring) {
                        ring.visible = true;
                        ring.scale.setScalar(meshAnimState.pulseRadius);
                        const op = Math.max(0, 1.0 - (meshAnimState.pulseRadius / 30));
                        (ring.material as THREE.Material).opacity = op;
                        (ring.material as THREE.Material).color.setHex(colors.neonCyan.getHex());
                    }

                    // Draw Line Progressively
                    const progress = Math.min(1.0, meshAnimState.pulseRadius / distToNext);
                    drawLine(p1, p2, progress);

                    // Check Completion
                    // We need strict "Reached" check
                    if (meshAnimState.pulseRadius >= distToNext) {
                        // Ensure Line Full
                        drawLine(p1, p2, 1.0);

                        // Next Step
                        meshAnimState.step++;
                        meshAnimState.pulseRadius = 0;
                        // meshAnimState.loopTimer = 0; // Dont reset loopTimer, it's global for the loop phase

                        if (ring) {
                            ring.visible = false;
                        }
                    }
                }
                // IMPORTANT: Clear remainder of the buffer (if array is reused)
                for (let k = idx; k < positionsArr.length; k++) positionsArr[k] = 0;
                arcLines.geometry.attributes.position.needsUpdate = true;
            } else {
                // Not active? Clear lines? (Handled by GSAP proxy onReverse but good to enforce)
            }

            // Signal Pulse Animation (Tower)
            const t = oceanMaterial.uniforms.uTime.value;
            // Check land opacity AND signal start state to control visibility
            if (landMat.opacity > 0.01 && towerSignalState.opacity > 0.01) {
                pulseRings.forEach((ring, i) => {
                    // Calculate radius based on time + phase
                    let r = (t * pulseParams.speed + ring.userData.phase) % pulseParams.maxRadius;
                    ring.scale.setScalar(r);

                    // Smoother ease-out opacity
                    // r/max goes 0 to 1. Opacity goes 1 to 0.
                    // Use a curve to make it "glitch" less
                    const norm = r / pulseParams.maxRadius;
                    const opacity = (1.0 - norm) * (1.0 - norm); // Square it for smoother fade out
                    const fadeIn = Math.min(r, 2.0) / 2.0;

                    // Multiply by land opacity AND towerSignalState opacity
                    (ring.material as THREE.Material).opacity = opacity * fadeIn * 0.8 * landMat.opacity * towerSignalState.opacity;
                    ring.visible = true;
                });
            } else {
                pulseRings.forEach(r => r.visible = false);
            }

            // Boat SOS Pulse Animation (Sphere)
            // Checked via Opacity now
            // "red sos sphere, still pulses even when we scroll back" -> Logic: Only if opacity > 0
            const sosSpeed = 1.5; // VS 3.0 before. Slower.

            if ((boatPulseSphere.material as THREE.Material).opacity > 0.01) {
                boatPulseSphere.visible = true;
                const time = oceanMaterial.uniforms.uTime.value;
                const s = 1 + (time * sosSpeed) % 15;
                boatPulseSphere.scale.setScalar(s);
                const op = 1.0 - (s / 15);
                // Multiply with base opacity
                const baseOp = (boatPulseSphere.material as THREE.Material).opacity;
                // We cannot modify material opacity directly if GSAP controls it, effectively fighting.
                // But GSAP sets the 'base' opacity?
                // Wait, if GSAP sets .opacity to 0.5, and I set it to 0.5 * logic here, next frame GSAP sets it back to 0.5?
                // No, GSAP tweens are usually once or per scroll.
                // But if I scroll, GSAP updates it.
                // If I am in a "stable" scroll section, GSAP isn't updating it every frame, so this logic wins.
                // Ideally use a uniform or userData for base opacity.
                // For now, let's just act on scale and visibility, and hardcode opacity fade based on scale,
                // assuming GSAP set it to non-zero.
                // Actually, let's just make it visible/invisible based on GSAP opacity > 0.
                (boatPulseSphere.material as THREE.Material).opacity = baseOp * op;
            } else {
                boatPulseSphere.visible = false;
            }

            // Ambient Boats swaying (Enhanced to match Main Boat physics)
            ambientGroup.children.forEach((b, i) => {
                const phase = i; // Random phase offset
                // Bobbing height
                const wH = sceneParams.waveHeight;
                // Ambients are far away, maybe slightly less intense motion? No, logic should hold.
                b.position.y = 0.5 + Math.sin(oceanMaterial.uniforms.uTime.value + phase) * wH * 0.5;
                // Pitch/Roll
                b.rotation.x = Math.sin(oceanMaterial.uniforms.uTime.value * 0.5 + phase) * wH * 0.2;
                b.rotation.z = Math.cos(oceanMaterial.uniforms.uTime.value * 0.3 + phase) * wH * 0.1;
            });

            // Mesh Network Boats (Signal Carriers) - Previously Static, now Animated
            if (otherBoatsData) {
                otherBoatsData.forEach((data, i) => {
                    if (!data.mesh) return;
                    const phase = i * 2; // Distinct phase
                    const wH = sceneParams.waveHeight;
                    // Apply same physics
                    data.mesh.position.y = 0.5 + Math.sin(oceanMaterial.uniforms.uTime.value + phase) * wH * 0.5;
                    data.mesh.rotation.x = Math.sin(oceanMaterial.uniforms.uTime.value * 0.5 + phase) * wH * 0.2;
                    data.mesh.rotation.z = Math.cos(oceanMaterial.uniforms.uTime.value * 0.3 + phase) * wH * 0.1;
                });
            }

            renderer.render(scene, camera);
            requestAnimationFrame(tick);
        };

        tick();

        const handleResize = () => {
            camera.aspect = window.innerWidth / window.innerHeight;
            camera.updateProjectionMatrix();
            renderer.setSize(window.innerWidth, window.innerHeight);
        };
        window.addEventListener('resize', handleResize);

        return () => {
            window.removeEventListener('resize', handleResize);
            renderer.dispose();
        };
    }, []);

    return (
        <>
            {/* Canvas initially hidden below screen */}
            {/* Added fixed positioning so it stays as background while we scroll the relative spacer */}
            <canvas ref={canvasRef} id="canvas-container" className="fixed top-0 left-0 w-full h-full z-0" style={{ transform: 'translateY(100vh)' }} />

            {/* Increased height to allow for pause at end + Intro Scroll */}
            {/* Changed to RELATIVE so it takes up space in the document flow, pushing Section 4 down */}
            <div ref={scrollContainerRef} className="relative w-full" style={{ height: '700vh' }}></div>

            <div className="fixed top-0 left-0 w-full h-full pointer-events-none z-10 flex flex-col">

                {/* Header Removed */}



                {/* SECTION 0: INTRO - "NEDUVAAI" */}
                {/* Replaced with New Abyssal Interface */}
                <div ref={section0Ref} className="story-section absolute inset-0 opacity-100 pointer-events-auto">
                    <LandingOverlay />
                </div>

                {/* SECTION 1: DEPARTURE */}
                <div ref={section1Ref} className="story-section absolute inset-0 opacity-0 flex flex-col items-center justify-start pt-12 md:pt-20 pointer-events-none">
                    <div className="text-center max-w-2xl px-6">
                        <h2 className="text-4xl md:text-7xl font-bold tracking-tight text-[#D54DFF] mb-6">Leaving the Shore</h2>
                        <p className="text-lg md:text-3xl text-white leading-relaxed font-bold drop-shadow-md">
                            <span className="story-line font-medium opacity-0 text-white block">Someone leaves for work today.</span>
                            <span className="story-line font-medium opacity-0 text-white block">Their family waits behind.</span>
                        </p>
                    </div>
                </div>

                {/* SECTION 2: THE DEEP */}
                <div ref={section2Ref} className="story-section absolute inset-0 opacity-0 flex flex-col items-center justify-start pt-12 md:pt-20 pointer-events-none">
                    <div className="text-center max-w-2xl px-6">
                        <h2 className="text-4xl md:text-7xl font-bold text-[#D54DFF] mb-6 drop-shadow-lg">The Silent Dark</h2>
                        <p className="text-lg md:text-3xl text-red-50 leading-relaxed font-bold drop-shadow-md">
                            <span className="story-line font-medium opacity-0 text-white block">Beyond signal. Beyond visibility.</span>
                            <span className="story-line font-medium opacity-0 text-white block">No one is watching.</span>
                        </p>
                    </div>
                </div>

                {/* SECTION 3: THE BLACKOUT */}
                <div ref={section3Ref} className="story-section absolute inset-0 opacity-0 flex flex-col items-center justify-start pt-12 md:pt-20 pointer-events-none">
                    <div className="text-center max-w-2xl px-6">
                        <h2 className="text-4xl md:text-7xl font-bold text-red-500 mb-6 animate-pulse">EMERGENCY</h2>
                        <p className="text-lg md:text-3xl text-red-50 leading-relaxed font-bold drop-shadow-md">
                            <span className="story-line font-medium opacity-0 text-white block">The engine stops at sea.</span>
                            <span className="story-line font-large opacity-0 text-red-500 block">What if help never finds?</span>
                        </p>
                    </div>
                </div>

                {/* SECTION 3.5: NEDUVAAI ACTIVATES */}
                <div ref={section35Ref} className="story-section absolute inset-0 opacity-0 flex flex-col items-center justify-start pt-12 md:pt-20 pointer-events-none">
                    <div className="text-center">
                        <h2 className="text-4xl md:text-7xl font-bold text-white mb-2">
                            <span className="text-[#D54DFF]">NEDUVAAI</span><br />ONLINE
                        </h2>
                        <p className="text-[#D54DFF]/60 text-lg md:text-3xl text-red-50 leading-relaxed font-bold drop-shadow-md">
                            <span className="story-line font-medium opacity-0 text-white block">Boats connect without satellites.</span>
                            <span className="story-line font-medium opacity-0 text-white block">Communities protect their own.</span>
                        </p>
                    </div>
                </div>

            </div>

            {/* SECTION 4: CONNECTS (Static Footer Section below the scroll experience) */}
            <section ref={section4Ref} className="relative z-20 w-full min-h-screen bg-[#111116] flex items-center justify-center py-20">
                <div className="text-center max-w-4xl px-6 bg-[#050505]/80 backdrop-blur-xl p-8 md:p-12 rounded-2xl border border-[#D54DFF]/30 shadow-[0_0_80px_rgba(213,77,255,0.15)] transform translate-y-12">

                    {/* BRANDING REVEAL */}
                    <div className="flex flex-col items-center justify-center m-1">
                        <img
                            src="/icon.png"
                            className="w-24 h-24 md:w-32 md:h-32 mb-6 mix-blend-screen"
                            alt="Neduvaai Icon"
                        />
                        <h1 className="text-5xl md:text-8xl font-bold tracking-widest text-white">
                            NEDUVAAI
                        </h1>
                    </div>
                    <h2 className="text-3xl md:text-4xl font-light text-zinc-300 mb-6 uppercase tracking-widest">
                        Connects.
                    </h2>
                    <p className="text-2xl md:text-3xl mb-10 max-w-3xl mx-auto text-transparent bg-clip-text bg-gradient-to-r from-violet-300 via-[#D54DFF] to-cyan-300 font-medium tracking-wide drop-shadow-[0_0_15px_rgba(213,77,255,0.4)]">
                        Safety should not be a privilege.
                    </p>

                    {/* <div className="grid grid-cols-1 md:grid-cols-3 gap-6 text-left mb-10">
                        <div className="p-4 bg-zinc-900/50 rounded border border-zinc-800">
                            <h3 className="text-[#D54DFF] font-mono text-xs mb-2 uppercase">Tech</h3>
                            <p className="text-sm text-zinc-300 font-semibold">LoRa Mesh Network</p>
                        </div>
                        <div className="p-4 bg-zinc-900/50 rounded border border-zinc-800">
                            <h3 className="text-[#D54DFF] font-mono text-xs mb-2 uppercase">Hardware</h3>
                            <p className="text-sm text-zinc-300 font-semibold">ESP32 + GPS Module</p>
                        </div>
                        <div className="p-4 bg-zinc-900/50 rounded border border-zinc-800">
                            <h3 className="text-[#D54DFF] font-mono text-xs mb-2 uppercase">Impact</h3>
                            <p className="text-sm text-zinc-300 font-semibold">100% Offline Tracking</p>
                        </div>
                    </div> */}

                    <div className="flex flex-col md:flex-row items-center justify-center gap-4">
                        <button className="w-full md:w-auto bg-[#D54DFF] hover:bg-[#c02ceb] text-white font-bold py-4 px-8 rounded-full transition-all hover:scale-105 hover:shadow-[0_0_30px_rgba(213,77,255,0.4)] flex items-center justify-center gap-2">
                            <span>JOIN THE NETWORK</span>
                            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>
                        </button>
                        <button className="w-full md:w-auto bg-transparent hover:bg-zinc-800 text-[#D54DFF] border border-[#D54DFF]/50 font-bold py-4 px-8 rounded-full transition-all flex items-center justify-center gap-2">
                            <span>DONATE TO CAUSE</span>
                            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" /></svg>
                        </button>
                    </div>
                </div>
            </section>

            <style>{`
        .glitch-text {
            text-shadow: 2px 2px 0px #ff0000, -2px -2px 0px #0000ff;
            animation: glitch 0.2s infinite;
        }
        @keyframes glitch {
            0% { transform: translate(0) }
            20% { transform: translate(-2px, 2px) }
            40% { transform: translate(-2px, -2px) }
            60% { transform: translate(2px, 2px) }
            80% { transform: translate(2px, -2px) }
            100% { transform: translate(0) }
        }
      `}</style>
        </>
    );
};

export default App;
