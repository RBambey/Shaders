// Glimpse Before Death — raymarched twisting tunnel with growing veins. The walls rotate
// automatically through four looks (pitted clay -> fuzzy coral -> wet flesh -> stones,
// vines and flowers), all under a drifting oil-slick sheen.
//
// Synesthesia inputs: TIME, RENDERSIZE, syn_HighLevel
// From script.js (bass-hit detector): pulse_age0..3, pulse_amp0..3
// Controls (scene.json): speed, twist, tunnel_radius, vein_density,
//   vein_growth_speed, bubbles, bubble_rate, sheen, hue_drift, hue_shift, audio_react

const float kTAU = 6.28318530718;

// Per-frame globals (set in renderTunnel)
float gT;       // time
float gTravel;  // camera z
float gHigh;

// Per-sample globals (written by map, read after the final map call)
float gVein;    // 0 = wall, 1 = vein
float gPulse;   // bass pulse passing this point (veins and bubbles only)
float gVeinId;
float gBubble;  // how far the nearest vein has turned into bubbles
float gContact; // distance to nearest vein (for contact shadows on the wall)
float gBump;    // coral: 0 in the crevices, 1 at polyp tips
float gRidge;   // flesh: 0 in the folds' valleys, 1 on their crests
float gStone;   // floral: 0 on the joints between stones, 1 on stone tops
float gVine;    // floral: wall vine coverage
float gLeaf;    // floral: wall leaf coverage
float gPetal;   // flower petal material at this point (0..1)
float gCenter;  // flower centre material at this point (0..1)
float gFlowerId;
float gPetalRho; // 0 at the flower's centre, 1 at the petal tips
vec4 gW;        // look weights at this point: x = clay, y = coral, z = flesh, w = floral

// flowerSDF scratch outputs
float gFCtr;
float gFRho;

// ---------------------------------------------------------------- noise

float vhash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float vhash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vhash31(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(vhash31(i),                   vhash31(i + vec3(1.0, 0.0, 0.0)), f.x),
                   mix(vhash31(i + vec3(0.0, 1.0, 0.0)), vhash31(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
               mix(mix(vhash31(i + vec3(0.0, 0.0, 1.0)), vhash31(i + vec3(1.0, 0.0, 1.0)), f.x),
                   mix(vhash31(i + vec3(0.0, 1.0, 1.0)), vhash31(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

vec3 hueRotate(vec3 c, float a) {
    // Rodrigues rotation around the grey axis
    const vec3 k = vec3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

// ---------------------------------------------------------------- tunnel

vec2 tunnelPath(float z) {
    return twist * vec2(2.2 * sin(z * 0.13) + 1.3 * sin(z * 0.057 + 1.7),
                        1.7 * cos(z * 0.097) + 1.5 * sin(z * 0.043 + 0.4));
}

// Looks cycle clay -> coral -> flesh -> floral along the tunnel (and slowly in time),
// holding each one and cross-fading into the next as you fly into it.
vec4 lookWeights(float z) {
    float u = z * 0.02 + gT * 0.01;
    float k = mod(floor(u), 4.0);
    float b = smoothstep(0.65, 1.0, fract(u));
    vec4 cur = vec4(k < 0.5 ? 1.0 : 0.0, abs(k - 1.0) < 0.5 ? 1.0 : 0.0,
                    abs(k - 2.0) < 0.5 ? 1.0 : 0.0, k > 2.5 ? 1.0 : 0.0);
    return mix(cur, cur.wxyz, b);
}

// Pitted, domain-warped clay. sp = point projected onto the tunnel cylinder.
float clayDisp(vec3 sp) {
    vec3 w = sp * 0.9 + vec3(0.0, 0.0, gT * 0.05);
    w += vnoise(w * 1.1) * 1.2;
    float base = vnoise(w) * 0.6 + vnoise(w * 2.1) * 0.3;
    float pits = smoothstep(0.5, 0.75, vnoise(sp * 2.6 + 11.0));
    float lod = 1.0 - smoothstep(4.0, 12.0, abs(sp.z - gTravel));
    float grain = lod > 0.0 ? vnoise(sp * 6.0) * 0.05 * lod : 0.0;
    return base * 0.35 - pits * 0.22 + grain;
}

// Rows of fuzzy rounded bumps.
float coralDisp(float a, float z, vec3 sp) {
    const float N = 28.0;
    vec2 g = vec2(a / kTAU * N, z / 0.32);
    g.x += 0.5 * mod(floor(g.y), 2.0);
    vec2 id = floor(g);
    vec2 f = fract(g) - 0.5;
    float h = vhash21(vec2(mod(id.x, N), id.y));
    f += (vec2(vhash11(h * 91.7), vhash11(h * 13.3)) - 0.5) * 0.25;
    float bump = 1.0 - smoothstep(0.0, 0.5, length(f));
    float height = (0.14 + 0.16 * h) * pow(bump, 0.4);   // blunt polyp fingers
    float rings = 0.08 * sin(z * 2.2 - gT * 0.5);
    float fuzz = vnoise(sp * 9.0 + gT * 0.3) * 0.04;

    // fine surface detail, faded with distance to avoid shimmer
    gBump = bump;
    float lod = 1.0 - smoothstep(4.0, 12.0, abs(z - gTravel));
    if (lod <= 0.0) return height + rings + fuzz;
    vec2 g2 = vec2(a / kTAU * N * 4.0, z / 0.08);
    g2.x += 0.5 * mod(floor(g2.y), 2.0);
    float nodules = 1.0 - smoothstep(0.15, 0.5, length(fract(g2) - 0.5));
    float pores = smoothstep(0.62, 0.78, vnoise(sp * 16.0));
    return height + rings + fuzz + lod * (nodules * 0.025 * (0.4 + bump) - pores * 0.02);
}

// Wet, folded vessel lining that squeezes with a heartbeat and peristaltic waves.
float fleshDisp(float z, vec3 sp) {
    vec3 w = vec3(sp.xy, sp.z * 0.35) * 1.4 + vec3(0.0, 0.0, gT * 0.04);
    w += vnoise(w * 0.8) * 1.5;
    float ridge = 1.0 - abs(vnoise(w) * 2.0 - 1.0);
    ridge = ridge * ridge * ridge;
    float lumps = vnoise(w * 2.3) * 0.1;
    float lod = 1.0 - smoothstep(4.0, 12.0, abs(z - gTravel));
    float wrinkles = lod > 0.0 ? (1.0 - abs(vnoise(w * 6.0) * 2.0 - 1.0)) * 0.035 * lod : 0.0;
    float wave = 0.07 * sin(z * 0.9 - gT * 2.0);
    float beat = pow(0.5 + 0.5 * sin(gT * 2.4), 6.0);
    gRidge = ridge;
    return 0.3 * ridge + lumps + wrinkles + wave + 0.08 * beat;
}

// Bass pulses: each hit from script.js launches a band that starts at the camera and races
// away down the tunnel, fading as it goes. Only the veins and bubbles respond to it.
float pulseBand(float ahead, float age, float amp) {
    float x = (ahead - age * 9.0) / 1.0;
    return amp * exp(-age * 0.7) * exp(-x * x);
}

float veinPulse(float z) {
    float ahead = z - gTravel;
    return audio_react * (pulseBand(ahead, pulse_age0, pulse_amp0) + pulseBand(ahead, pulse_age1, pulse_amp1)
                        + pulseBand(ahead, pulse_age2, pulse_amp2) + pulseBand(ahead, pulse_age3, pulse_amp3));
}

// Cobblestones with leafy vines creeping over them.
float floralDisp(float a, float z, vec3 sp) {
    // stones: Voronoi cells around the tunnel; F2 - F1 is ~0 along the joints
    const float N = 18.0;
    vec2 g = vec2(a / kTAU * N, z / 0.42);
    vec2 id = floor(g);
    vec2 f = fract(g);
    float F1 = 8.0;
    float F2 = 8.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 c = vec2(float(i), float(j));
            vec2 cid = vec2(mod(id.x + c.x, N), id.y + c.y);
            vec2 o = 0.5 + 0.7 * (vec2(vhash21(cid), vhash21(cid + 17.3)) - 0.5);
            float dd = length(c + o - f);
            if (dd < F1) { F2 = F1; F1 = dd; } else if (dd < F2) { F2 = dd; }
        }
    }
    float stone = smoothstep(0.0, 0.35, F2 - F1);
    float h = 0.17 * sqrt(stone);
    float lod = 1.0 - smoothstep(4.0, 12.0, abs(z - gTravel));
    if (lod > 0.0) h += (vnoise(sp * 4.0) - 0.5) * 0.04 * lod * stone;

    // three vines wandering along the tunnel, with leaves alternating either side
    float vine = 0.0;
    float leaf = 0.0;
    for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float ac = fk / 3.0 * kTAU + 0.7 * sin(z * 0.3 + fk * 2.1) + 0.25 * sin(z * 0.85 + fk * 4.0 + gT * 0.1);
        float du = (mod(a - ac + 0.5 * kTAU, kTAU) - 0.5 * kTAU) * tunnel_radius;
        vine = max(vine, sqrt(max(0.0, 1.0 - du * du / (0.045 * 0.045))));
        float lz = z / 0.38 + fk * 0.37;
        float side = mod(floor(lz), 2.0) * 2.0 - 1.0;
        vec2 lp = vec2(du - side * 0.085, (fract(lz) - 0.5) * 0.38);
        lp = mat2(0.8, -0.6 * side, 0.6 * side, 0.8) * lp;   // tilt leaves away from the stem
        leaf = max(leaf, 1.0 - smoothstep(0.7, 1.0, length(lp / vec2(0.06, 0.1))));
    }
    gStone = stone;
    gVine = vine;
    gLeaf = leaf;
    float vineH = vine > 0.0 ? 0.17 + 0.045 * vine : 0.0;
    float leafH = leaf > 0.0 ? 0.19 + 0.025 * leaf : 0.0;
    return max(h, max(vineH, leafH));
}

// A cupped flower facing the tunnel axis. lp: x/z = across the wall, y = up towards the axis.
float flowerSDF(vec3 lp, float R, float hb) {
    R = max(R, 1e-3);
    float petals = 5.0 + floor(hb * 3.0);              // 5-7 petals
    float rho = length(lp.xz);
    float th = atan(lp.z, lp.x) + hb * kTAU;
    float lobe = 1.0 - pow(1.0 - (0.5 + 0.5 * cos(th * petals)), 2.0);
    float edge = R * (0.3 + 0.7 * lobe);
    float cupY = 0.5 * rho * rho / R;                  // petals curl up towards the axis
    float thick = 0.01 + 0.015 * (1.0 - clamp(rho / R, 0.0, 1.0));
    vec2 q = vec2(rho - edge, abs(lp.y - cupY) - thick);
    float dPet = min(max(q.x, q.y), 0.0) + length(max(q, 0.0));
    float dCtr = length(lp - vec3(0.0, 0.02 + 0.08 * R, 0.0)) - 0.26 * R;
    gFCtr = dCtr < dPet ? 1.0 : 0.0;
    gFRho = rho / R;
    return min(dPet, dCtr) * 0.8;                      // the petal outline isn't an exact distance
}

// One layer of writhing veins lying on the wall, growing along z and respawning.
// 0 = veins, 1 = bubbles. The change sweeps down the tunnel as a wave, each vein slightly out of step.
float bubbleAmount(float z, float h) {
    float ph = gT * bubble_rate * 0.05 + z * 0.015 + h * 0.15;
    return bubbles * smoothstep(0.35, 0.65, 0.5 + 0.5 * sin(ph * kTAU));
}

// Growth: each vein is split into segments of length kSegLen that grow from their start, then shrink away.
// Returns (position within the segment, grown tip position, fade).
const float kSegLen = 6.0;
vec3 veinSegment(float zs, float idw, float seed) {
    float seg = floor(zs / kSegLen);
    float phase = fract(gT * vein_growth_speed * 0.15 + vhash21(vec2(idw + seed * 7.0, seg)));
    float grow = smoothstep(0.0, 0.6, phase);
    float fade = 1.0 - smoothstep(0.8, 1.0, phase);
    return vec3(zs - seg * kSegLen, 0.5 + grow * (kSegLen - 1.0), fade);
}

// fw = floral weight: veins straighten into green stems and their beads bloom into flowers.
// vmat = (bubble amount, petal material, centre material, flower id); vrho = position across the petals.
float veinLayer(float r, float a, float z, float wallR, float N, float spiral, float seed, float fw, float pulse,
                out float vid, out vec4 vmat, out float vrho) {
    float s = a / kTAU * N + z * spiral;
    float idw = mod(floor(s), N);
    float h = vhash11(idw * 17.31 + seed);
    float cellW = kTAU * wallR / N;
    float wobAmt = 1.0 - 0.6 * fw;                  // stems are straighter, leaving room for flowers

    float wob = (0.28 * sin(z * (0.9 + 0.8 * h) + gT * (0.6 + h) + h * kTAU)
               + 0.08 * sin(z * 3.1 - gT * 1.3 + h * 20.0)) * wobAmt;
    float du = (fract(s) - 0.5 - wob) * cellW;

    float zs = z + h * kSegLen;
    vec3 sg = veinSegment(zs, idw, seed);
    float zl = sg.x;
    float tip = sg.y;
    float fade = sg.z;
    float dz = max(0.0, max(0.5 - zl, zl - tip));

    float rv = (0.035 + 0.045 * h) * fade * (1.0 + 0.9 * pulse);
    rv *= 0.35 + 0.65 * smoothstep(0.0, 0.8, tip - zl);

    // bubbles: the tube thins away while a string of beads swells out of it, drifts off
    // the wall and flows along, then the beads shrink back into the regrowing vein
    float bub = bubbleAmount(z, h);

    // some veins arch away from the wall
    float lift = 0.25 * pow(max(0.0, sin(z * 0.7 + h * 13.0 + gT * 0.4)), 2.0) * step(0.5, h);
    float dr = r - (wallR - rv * 0.5 - lift);
    // tube radius goes slightly negative at full bubble so no zero-width line is left behind;
    // floral stems are thinner than veins
    float tubeR = rv * mix(1.0, 0.45, fw);
    float d = length(vec3(du, dr, dz)) - (tubeR * (1.0 - bub) - 0.01 * bub);

    vid = h;
    vmat = vec4(bub, 0.0, 0.0, 0.0);
    vrho = 0.0;

    // beads appear when the bubble wave passes, and always in the floral look (as flowers)
    float beads = max(bub, fw);
    if (beads > 0.001) {
        const float S = 0.34;                       // bead spacing
        float laneAng = kTAU / N;
        float zb = zs - gT * 0.2;
        float bi = floor(zb / S);
        // check this bead cell and the nearer neighbour, so rays don't step into a bead
        // from the next cell over (which would land them inside it)
        float nb = fract(zb / S) < 0.5 ? -1.0 : 1.0;
        float dBeads = 1e5;
        float bestCtr = 0.0;
        float bestId = 0.0;
        float bestRho = 0.0;
        for (int k = 0; k < 2; k++) {
            float bk = bi + (k == 0 ? 0.0 : nb);
            float hb = vhash21(vec2(idw * 3.1 + seed, bk));
            float zc = zb - (bk + 0.5) * S;         // offset from the bead centre along the vein
            float zC = z - zc;                      // bead centre
            // place the bead using the vein's path at its centre, so it stays round
            float wobC = (0.28 * sin(zC * (0.9 + 0.8 * h) + gT * (0.6 + h) + h * kTAU)
                        + 0.08 * sin(zC * 3.1 - gT * 1.3 + h * 20.0)) * wobAmt;
            float liftC = 0.25 * pow(max(0.0, sin(zC * 0.7 + h * 13.0 + gT * 0.4)), 2.0) * step(0.5, h);
            float drift = bub * (0.05 + 0.35 * hb);
            // lateral distance as true arc length at this radius (bubbles float inward, where
            // measuring along the wall would stretch them sideways)
            float duC = (fract(s) - 0.5 - wobC - zc * spiral) * laneAng * r;
            // a bead exists where the grown vein covers its centre (looked up in the centre's own segment);
            // not every bead becomes a flower
            vec3 sc = veinSegment(zs - zc, idw, seed);
            float onVein = step(0.5, sc.x) * step(sc.x, sc.y) * mix(1.0, step(0.25, hb), fw);
            float size = mix(0.06 + 0.08 * hb, 0.1 + 0.1 * hb, fw);
            float rb = size * sc.z * onVein * (1.0 + 0.6 * pulse);
            // stay inside this vein's lane and bead cell (flowers may overlap their neighbours)
            float rc = wallR - 0.14 - liftC - drift;
            rb = min(rb, min((0.5 - abs(wobC)) * laneAng * rc, mix(0.5, 0.9, fw) * S) - 0.01);
            rb *= smoothstep(0.0, 0.6, beads);
            rb *= mix(1.0, smoothstep(0.02, 0.05, rb), fw);   // no flower crumbs where a vein is fading out
            // spheres rest on the wall; flowers sit flat against it
            float drb = r - (wallR - mix(rb, 0.04, fw) - liftC - drift);
            float dSphere = length(vec3(duC, drb, zc)) - rb;
            float dB = dSphere;
            float ctr = 0.0;
            float rho = 0.0;
            if (fw > 0.001) {
                // the whole flower fits in a sphere of 1.15 x its radius: only shape it when we're close
                float dBound = dSphere - 0.15 * rb;
                float dFlower = dBound > 0.03 ? dBound : flowerSDF(vec3(duC, -drb, zc), rb, hb);
                dB = mix(dSphere, dFlower, fw);
                ctr = gFCtr;
                rho = gFRho;
            }
            dB += 0.05 * (1.0 - smoothstep(0.0, 0.02, rb));   // empty bead slots can't be hit as specks
            if (dB < dBeads) {
                dBeads = dB;
                bestCtr = ctr;
                bestId = hb;
                bestRho = rho;
            }
        }
        float onBead = dBeads < d ? fw : 0.0;
        vmat = vec4(bub, onBead * (1.0 - bestCtr), onBead * bestCtr, bestId);
        vrho = bestRho;
        d = smin(d, dBeads, 0.03);
    }

    return d;
}

float map(vec3 p) {
    vec2 q = p.xy - tunnelPath(p.z);
    float r = length(q);
    float a = atan(q.y, q.x);
    vec3 sp = vec3(q / max(r, 1e-4) * tunnel_radius, p.z);

    vec4 w = lookWeights(p.z);
    float disp = 0.0;
    gBump = 1.0;
    gRidge = 0.0;
    gStone = 1.0;
    gVine = 0.0;
    gLeaf = 0.0;
    if (w.x > 0.001) disp += w.x * clayDisp(sp);
    if (w.y > 0.001) disp += w.y * coralDisp(a, p.z, sp);
    if (w.z > 0.001) disp += w.z * fleshDisp(p.z, sp);
    if (w.w > 0.001) disp += w.w * floralDisp(a, p.z, sp);

    float R = tunnel_radius * (1.0 + 0.15 * sin(p.z * 0.21 + 1.0));
    float wallR = R - disp;
    float dWall = wallR - r;

    // veins rest on a smoothed wall so they don't dive into every pit;
    // in coral mode they ride on top of the bumps instead of being swallowed
    float veinR = R - dot(w, vec4(0.12, 0.3, 0.16, 0.2));
    float id1, id2, rho1, rho2;
    vec4 m1, m2;
    float pulse = veinPulse(p.z);
    float v1 = veinLayer(r, a, p.z, veinR, floor(vein_density), 0.05, 1.0, w.w, pulse, id1, m1, rho1);
    float v2 = veinLayer(r, a, p.z, veinR, floor(vein_density * 0.7) + 2.0, -0.11, 5.0, w.w, pulse, id2, m2, rho2);
    float dv = smin(v1, v2, 0.04);   // overlapping bubbles / crossing veins fuse instead of seaming

    bool first = v1 < v2;
    vec4 vm = first ? m1 : m2;
    gVeinId = first ? id1 : id2;
    gBubble = vm.x;
    gPetal = vm.y;
    gCenter = vm.z;
    gFlowerId = vm.w;
    gPetalRho = first ? rho1 : rho2;
    gPulse = pulse;
    gVein = clamp(0.5 + 0.5 * (dWall - dv) / 0.006, 0.0, 1.0);
    gContact = dv;
    gW = w;
    return smin(dWall, dv, 0.025);
}

vec3 calcNormal(vec3 p, float t) {
    float e = 0.0015 * (1.0 + t * 0.3);
    const vec2 k = vec2(1.0, -1.0);
    return normalize(k.xyy * map(p + k.xyy * e) + k.yyx * map(p + k.yyx * e) +
                     k.yxy * map(p + k.yxy * e) + k.xxx * map(p + k.xxx * e));
}

float calcAO(vec3 p, vec3 n) {
    float occ = 0.0;
    float w = 1.0;
    for (int i = 1; i <= 2; i++) {
        float h = 0.08 * float(i);
        occ += (h - map(p + n * h)) * w;
        w *= 0.6;
    }
    return clamp(1.0 - occ * 3.0, 0.0, 1.0);
}

// ---------------------------------------------------------------- shading

vec3 surfaceColor(vec3 sp, float t) {
    // each look's palette is only evaluated where that look is visible
    // clay: purple / teal blotches
    vec3 clayWall = vec3(0.0);
    if (gW.x > 0.001) {
        clayWall = mix(vec3(0.34, 0.06, 0.48), vec3(0.04, 0.55, 0.46),
                       smoothstep(0.35, 0.65, vnoise(sp * 0.6 + 3.0)));
        clayWall = mix(clayWall, vec3(0.75, 0.15, 0.7), 0.35 * smoothstep(0.6, 0.85, vnoise(sp * 1.3 - 5.0)));
        clayWall *= 1.0 - 0.65 * smoothstep(0.5, 0.75, vnoise(sp * 2.6 + 11.0));   // dark pit interiors
    }

    // coral: depth bands purple -> red/orange -> green, with speckles
    vec3 coralWall = vec3(0.0);
    if (gW.y > 0.001) {
        coralWall = mix(vec3(0.42, 0.12, 1.0), vec3(1.0, 0.22, 0.08), smoothstep(2.0, 5.5, t));
        coralWall = mix(coralWall, vec3(1.0, 0.55, 0.1), smoothstep(5.0, 7.5, t) * 0.6);
        coralWall = mix(coralWall, vec3(0.25, 0.85, 0.12), smoothstep(6.5, 10.0, t));
        float speck = smoothstep(0.68, 0.8, vnoise(sp * 6.0));
        float speck2 = smoothstep(0.7, 0.82, vnoise(sp * 5.0 + 9.0));
        coralWall = mix(coralWall, vec3(0.3, 1.0, 0.65), speck * 0.75);
        coralWall = mix(coralWall, vec3(1.0, 0.15, 0.2), speck2 * 0.6 * (1.0 - smoothstep(3.0, 6.0, t)));
        coralWall = mix(coralWall, coralWall * 1.6 + 0.08, smoothstep(0.7, 1.0, gBump) * 0.5);    // pale tips
        coralWall *= mix(0.3, 1.0, smoothstep(0.0, 0.6, gBump));                                 // dark crevices
        coralWall *= 1.0 - 0.45 * smoothstep(0.62, 0.78, vnoise(sp * 16.0));                     // pores
    }

    // flesh: deep crimson valleys, rosy crests, faint capillary mottling
    vec3 fleshWall = vec3(0.0);
    if (gW.z > 0.001) {
        fleshWall = mix(vec3(0.18, 0.0, 0.05), vec3(1.0, 0.38, 0.45), smoothstep(0.05, 0.7, gRidge));
        fleshWall = mix(fleshWall, vec3(0.6, 0.05, 0.35), 0.4 * smoothstep(0.55, 0.8, vnoise(sp * 3.5 + 2.0)));
    }

    // floral: weathered stones with mossy joints, dark vines and bright leaves
    vec3 floralWall = vec3(0.0);
    if (gW.w > 0.001) {
        vec3 stoneCol = mix(vec3(0.62, 0.56, 0.48), vec3(0.5, 0.48, 0.62), vnoise(sp * 0.9 + 4.0));
        stoneCol *= 0.75 + 0.35 * vnoise(sp * 3.0);
        floralWall = mix(vec3(0.12, 0.3, 0.06), stoneCol, smoothstep(0.05, 0.5, gStone));
        float vine = smoothstep(0.0, 0.3, gVine);
        floralWall = mix(floralWall, vec3(0.3, 0.8, 0.15), smoothstep(0.0, 0.4, gLeaf) * (1.0 - vine));
        floralWall = mix(floralWall, vec3(0.08, 0.38, 0.06), vine);
    }

    // veins
    float h = gVeinId;
    // veins: colors opposite the walls on the color wheel so they pop
    vec3 clayVein = h < 0.33 ? vec3(1.0, 0.85, 0.15) : (h < 0.66 ? vec3(1.0, 0.45, 0.1) : vec3(1.0, 0.97, 0.85));   // gold / orange / cream on purple-teal
    vec3 coralVein = h < 0.5 ? vec3(0.1, 0.95, 1.0) : vec3(0.95, 1.0, 0.9);                                       // cyan / white on purple-red-green
    vec3 fleshVein = h < 0.5 ? vec3(0.1, 0.55, 1.0) : vec3(0.7, 1.0, 0.25);                                       // electric blue / lime on crimson
    vec3 floralVein = h < 0.5 ? vec3(0.25, 0.75, 0.15) : vec3(0.45, 0.85, 0.2);                                   // green stems

    vec3 wall = clayWall * gW.x + coralWall * gW.y + fleshWall * gW.z + floralWall * gW.w;
    vec3 vein = clayVein * gW.x + coralVein * gW.y + fleshVein * gW.z + floralVein * gW.w;

    // flowers: each one picks a color; petals deepen towards the middle
    if (gPetal + gCenter > 0.001) {
        float fi = floor(gFlowerId * 6.0);
        vec3 petal = fi < 1.0 ? vec3(1.0, 0.25, 0.6)        // pink
                   : fi < 2.0 ? vec3(1.0, 0.96, 0.92)       // white
                   : fi < 3.0 ? vec3(1.0, 0.82, 0.1)        // yellow
                   : fi < 4.0 ? vec3(0.55, 0.25, 1.0)       // violet
                   : fi < 5.0 ? vec3(1.0, 0.45, 0.15)       // orange
                   :            vec3(0.95, 0.1, 0.18);      // red
        petal *= 0.55 + 0.45 * smoothstep(0.1, 0.9, gPetalRho);
        vec3 centre = gFlowerId > 0.7 ? vec3(0.25, 0.12, 0.03) : vec3(1.0, 0.7, 0.05);
        vein = mix(vein, petal, gPetal);
        vein = mix(vein, centre, gCenter);
    }
    return mix(wall, vein, gVein);
}

// Pass 0: the expensive raymarch, rendered into the low-res tunnelBuf (see scene.json PASSES).
vec4 renderTunnel() {
    gT = TIME;
    gHigh = syn_HighLevel;
    gTravel = speed * TIME;

    // camera rides the path, looking ahead, rolling into turns
    float z = gTravel;
    vec3 ro = vec3(tunnelPath(z), z);
    vec3 ta = vec3(tunnelPath(z + 2.0), z + 2.0);
    vec3 fw = normalize(ta - ro);
    float roll = 0.3 * sin(gT * 0.11) + (tunnelPath(z + 3.0).x - tunnelPath(z).x) * 0.15;
    vec3 up = vec3(sin(roll), cos(roll), 0.0);
    vec3 rt = normalize(cross(up, fw));
    up = cross(fw, rt);

    vec2 uv = (gl_FragCoord.xy - 0.5 * RENDERSIZE) / RENDERSIZE.y;
    vec3 rd = normalize(uv.x * rt + uv.y * up + 1.1 * fw);

    float t = 0.05;
    const float kFar = 24.0;   // walls are faded to black by here anyway
    for (int i = 0; i < 72; i++) {
        float d = map(ro + rd * t);
        if (d < 0.0012 * t) break;
        // far away the fine detail is faded out, so the field is smoother and we can stride further
        t += d * mix(0.6, 0.85, smoothstep(5.0, 14.0, t));
        if (t > kFar) break;
    }
    // rays that run out of steps (grazing silhouettes) still shade as a hit
    bool hit = t < kFar;

    vec3 col = vec3(0.0);
    if (hit) {
        vec3 pos = ro + rd * t;
        vec3 n = calcNormal(pos, t);
        float ao = calcAO(pos, n);
        map(pos); // refresh material globals for this point
        float vein = gVein;
        float flower = clamp(gPetal + gCenter, 0.0, 1.0);
        float bub = vein * gBubble * (1.0 - flower);     // soap-bubble look (floating flowers stay flowers)
        vec4 w = gW;

        vec2 q = pos.xy - tunnelPath(pos.z);
        vec3 sp = vec3(normalize(q) * tunnel_radius, pos.z);
        vec3 alb = surfaceColor(sp, t);
        // dark contact shadow on the wall around each vein so they read as separate
        alb *= mix(0.25 + 0.75 * smoothstep(0.0, 0.07, gContact), 1.0, vein);

        // oil-slick thin film: interference colors from view angle + flowing thickness
        float ndv = max(dot(n, -rd), 0.0);
        float fres = pow(1.0 - ndv, 2.0);
        float film = 1.6 * (1.0 - ndv) + 1.4 * vnoise(sp * 0.7 + vec3(0.0, 0.0, gT * 0.15)) + gT * 0.05;
        vec3 iri = 0.5 + 0.5 * cos(kTAU * (film + vec3(0.0, 0.33, 0.67)));
        float tube = vein - bub;                     // veins and flowers keep their own colors; bubbles take the film
        alb = mix(alb, alb * 0.6 + iri * 0.65, sheen * (0.15 + 0.85 * fres) * (1.0 - 0.85 * tube));
        alb *= 1.0 - 0.75 * bub;                     // bubble bodies read as see-through

        vec3 lightDir = normalize(ro - pos);
        float wrap = clamp((dot(n, lightDir) + 0.4) / 1.4, 0.0, 1.0);
        float atten = 1.0 / (1.0 + 0.035 * t * t);
        float shin = mix(24.0, 80.0, w.z);                       // flesh is wet and glossy
        float spec = pow(max(dot(reflect(rd, n), lightDir), 0.0), shin) * (mix(0.15, 0.5, vein) + 0.8 * w.z);
        float rim = pow(1.0 - ndv, 3.0);

        col = alb * (0.12 + 1.15 * wrap) * ao;
        col += alb * rim * 0.45;
        col += alb * pow(1.0 - ndv, 1.5) * 0.5 * w.y * (1.0 - vein);   // velvet sheen on coral
        col += alb * tube * 0.3;                                        // self-glow so veins read even in shadow
        col *= mix(1.0, 0.4 + 0.6 * ndv, tube);                      // darker silhouettes keep them round and outlined
        col += vec3(0.9, 0.1, 0.15) * (1.0 - gRidge) * 0.25 * w.z * ao; // blood glow in flesh folds
        col += spec * mix(vec3(1.0), iri, sheen * 0.8);
        col += bub * (iri * (0.15 + 1.4 * fres) + spec * 1.5);   // soap-film rim + glint
        col *= atten;
        col += alb * vein * gPulse * 0.9 * atten;                       // bass pulse lights up as it passes

        // highs: sparkle on the veins and bubbles
        float sparkleAmt = gHigh * audio_react * vein;
        if (sparkleAmt > 0.01) {
            float sparkle = pow(vnoise(sp * 14.0 + gT * 4.0), 8.0);
            col += vec3(0.8, 1.0, 0.9) * sparkle * sparkleAmt * 6.0 * atten;
        }
    }

    // saturate, drifting hue, tone map, vignette
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = max(mix(vec3(lum), col, 1.25), 0.0);
    col = hueRotate(col, (hue_shift + gT * 0.02 * hue_drift) * kTAU);
    col = 1.0 - exp(-col * 1.6);
    col = pow(col, vec3(0.9));
    col *= 1.0 - 0.35 * dot(uv, uv);

    return vec4(col, 1.0);
}

// Final pass: upscale tunnelBuf to the output size, with a light unsharp mask
// to win back some of the crispness lost to the lower render resolution.
vec4 upscale() {
    vec2 texel = 1.0 / vec2(textureSize(tunnelBuf, 0));
    vec2 lo = 0.5 * texel;
    vec2 hi = 1.0 - 0.5 * texel;
    vec2 uv = clamp(gl_FragCoord.xy / RENDERSIZE, lo, hi);
    vec3 c = texture(tunnelBuf, uv).rgb;
    vec3 blur = texture(tunnelBuf, clamp(uv + vec2(texel.x, 0.0), lo, hi)).rgb
              + texture(tunnelBuf, clamp(uv - vec2(texel.x, 0.0), lo, hi)).rgb
              + texture(tunnelBuf, clamp(uv + vec2(0.0, texel.y), lo, hi)).rgb
              + texture(tunnelBuf, clamp(uv - vec2(0.0, texel.y), lo, hi)).rgb;
    c += (c - blur * 0.25) * 0.5;
    return vec4(clamp(c, 0.0, 1.0), 1.0);
}

vec4 renderMain(void) {
    if (PASSINDEX == 0) return renderTunnel();
    return upscale();
}
