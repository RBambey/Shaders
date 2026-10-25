// Glimpse Before Death — raymarched twisting tunnel with growing veins. The walls rotate
// automatically through three looks (pitted clay -> fuzzy coral -> wet flesh),
// all under a drifting oil-slick sheen.
//
// Synesthesia inputs: TIME, RENDERSIZE, syn_BassLevel, syn_HighLevel, syn_BassTime
// Controls (scene.json): speed, twist, tunnel_radius, vein_density,
//   vein_growth_speed, sheen, hue_drift, hue_shift, audio_react

const float kTAU = 6.28318530718;

// Per-frame globals (set in renderTunnel)
float gT;       // time
float gTravel;  // camera z
float gBass;
float gHigh;

// Per-sample globals (written by map, read after the final map call)
float gVein;    // 0 = wall, 1 = vein
float gVeinId;
float gContact; // distance to nearest vein (for contact shadows on the wall)
float gBump;    // coral: 0 in the crevices, 1 at polyp tips
float gRidge;   // flesh: 0 in the folds' valleys, 1 on their crests
vec3 gW;        // look weights at this point: x = clay, y = coral, z = flesh

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

// Looks cycle clay -> coral -> flesh along the tunnel (and slowly in time),
// holding each one and cross-fading into the next as you fly into it.
vec3 lookWeights(float z) {
    float u = z * 0.02 + gT * 0.01;
    float k = mod(floor(u), 3.0);
    float b = smoothstep(0.65, 1.0, fract(u));
    vec3 cur = vec3(k < 0.5 ? 1.0 : 0.0, abs(k - 1.0) < 0.5 ? 1.0 : 0.0, k > 1.5 ? 1.0 : 0.0);
    return mix(cur, cur.zxy, b);
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
    float beat = pow(0.5 + 0.5 * sin(gT * 2.4), 6.0) + gBass * audio_react;
    gRidge = ridge;
    return 0.3 * ridge + lumps + wrinkles + wave + 0.08 * beat;
}

// One layer of writhing veins lying on the wall, growing along z and respawning.
float veinLayer(float r, float a, float z, float wallR, float N, float spiral, float seed, out float vid) {
    float s = a / kTAU * N + z * spiral;
    float idw = mod(floor(s), N);
    float h = vhash11(idw * 17.31 + seed);
    float cellW = kTAU * wallR / N;

    float wob = 0.28 * sin(z * (0.9 + 0.8 * h) + gT * (0.6 + h) + h * kTAU)
              + 0.08 * sin(z * 3.1 - gT * 1.3 + h * 20.0);
    float du = (fract(s) - 0.5 - wob) * cellW;

    // growth: each segment of length L grows from its start, then shrinks away
    const float L = 6.0;
    float zs = z + h * L;
    float seg = floor(zs / L);
    float zl = zs - seg * L;
    float phase = fract(gT * vein_growth_speed * 0.15 + vhash21(vec2(idw + seed * 7.0, seg)));
    float grow = smoothstep(0.0, 0.6, phase);
    float fade = 1.0 - smoothstep(0.8, 1.0, phase);
    float tip = 0.5 + grow * (L - 1.0);
    float dz = max(0.0, max(0.5 - zl, zl - tip));

    float rv = (0.035 + 0.045 * h) * fade * (1.0 + gBass * 0.8 * audio_react);
    rv *= 0.35 + 0.65 * smoothstep(0.0, 0.8, tip - zl);

    // some veins arch away from the wall
    float lift = 0.25 * pow(max(0.0, sin(z * 0.7 + h * 13.0 + gT * 0.4)), 2.0) * step(0.5, h);
    float dr = r - (wallR - rv * 0.5 - lift);

    vid = h;
    return length(vec3(du, dr, dz)) - rv;
}

float map(vec3 p) {
    vec2 q = p.xy - tunnelPath(p.z);
    float r = length(q);
    float a = atan(q.y, q.x);
    vec3 sp = vec3(q / max(r, 1e-4) * tunnel_radius, p.z);

    vec3 w = lookWeights(p.z);
    float disp = 0.0;
    gBump = 1.0;
    gRidge = 0.0;
    if (w.x > 0.001) disp += w.x * clayDisp(sp);
    if (w.y > 0.001) disp += w.y * coralDisp(a, p.z, sp);
    if (w.z > 0.001) disp += w.z * fleshDisp(p.z, sp);

    float R = tunnel_radius * (1.0 + 0.15 * sin(p.z * 0.21 + 1.0)) * (1.0 - 0.04 * gBass * audio_react);
    float wallR = R - disp;
    float dWall = wallR - r;

    // veins rest on a smoothed wall so they don't dive into every pit;
    // in coral mode they ride on top of the bumps instead of being swallowed
    float veinR = R - dot(w, vec3(0.12, 0.3, 0.16));
    float id1, id2;
    float v1 = veinLayer(r, a, p.z, veinR, floor(vein_density), 0.05, 1.0, id1);
    float v2 = veinLayer(r, a, p.z, veinR, floor(vein_density * 0.7) + 2.0, -0.11, 5.0, id2);
    float dv = min(v1, v2);

    gVeinId = v1 < v2 ? id1 : id2;
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

    // veins
    float h = gVeinId;
    vec3 clayVein = h < 0.33 ? vec3(1.0, 0.55, 0.82) : (h < 0.66 ? vec3(0.55, 1.0, 0.85) : vec3(0.95, 0.9, 1.0));
    vec3 coralVein = h < 0.5 ? vec3(1.0, 0.45, 0.1) : vec3(0.35, 1.0, 0.3);
    vec3 fleshVein = h < 0.5 ? vec3(0.25, 0.2, 0.95) : vec3(0.85, 0.05, 0.15);

    vec3 wall = clayWall * gW.x + coralWall * gW.y + fleshWall * gW.z;
    vec3 vein = clayVein * gW.x + coralVein * gW.y + fleshVein * gW.z;
    return mix(wall, vein, gVein);
}

// Pass 0: the expensive raymarch, rendered into the low-res tunnelBuf (see scene.json PASSES).
vec4 renderTunnel() {
    gT = TIME;
    gBass = syn_BassLevel;
    gHigh = syn_HighLevel;
    gTravel = speed * mix(TIME, syn_BassTime, audio_react);

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
        vec3 w = gW;

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
        alb = mix(alb, alb * 0.6 + iri * 0.65, sheen * (0.15 + 0.85 * fres));

        vec3 L = normalize(ro - pos);
        float wrap = clamp((dot(n, L) + 0.4) / 1.4, 0.0, 1.0);
        float atten = 1.0 / (1.0 + 0.035 * t * t);
        float shin = mix(24.0, 80.0, w.z);                       // flesh is wet and glossy
        float spec = pow(max(dot(reflect(rd, n), L), 0.0), shin) * (mix(0.15, 0.5, vein) + 0.8 * w.z);
        float rim = pow(1.0 - ndv, 3.0);

        col = alb * (0.12 + 1.15 * wrap) * ao;
        col += alb * rim * 0.45;
        col += alb * pow(1.0 - ndv, 1.5) * 0.5 * w.y * (1.0 - vein);   // velvet sheen on coral
        col += alb * vein * 0.25;                                       // soft subsurface glow
        col += vec3(0.9, 0.1, 0.15) * (1.0 - gRidge) * 0.25 * w.z * ao; // blood glow in flesh folds
        col += spec * mix(vec3(1.0), iri, sheen * 0.8);
        col *= atten;
        col += alb * vein * gBass * 0.6 * audio_react * atten;

        // highs: sparkle on coral tips
        float sparkleAmt = gHigh * audio_react;
        if (sparkleAmt > 0.01) {
            float sparkle = pow(vnoise(sp * 14.0 + gT * 4.0), 8.0);
            col += vec3(0.8, 1.0, 0.9) * sparkle * sparkleAmt * 6.0 * (0.3 + 0.7 * w.y) * atten;
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
