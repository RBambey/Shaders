// Bass-hit detector. Each hit becomes a pulse that the shader sends racing down the tunnel
// along the veins and bubbles. Keeps the last 4 hits and hands the shader:
//   pulse_age0..3: seconds since each hit (100 = no hit)
//   pulse_amp0..3: how hard each hit was (0..1)

var MAX_PULSES = 4;
var pulses = [];    // newest first: {age, amp}
var avg = 0.0;      // slow average of the bass level, for a threshold that adapts to the track
var prev = 0.0;
var cooldown = 0.0;

function update(dt) {
    var bass = syn_BassLevel;

    for (var i = 0; i < pulses.length; i++) pulses[i].age += dt;
    cooldown -= dt;
    avg += (bass - avg) * Math.min(1.0, dt * 1.5);

    // a hit = bass rising through a threshold above its recent average
    if (bass > prev && bass > avg * 1.25 + 0.12 && cooldown <= 0.0) {
        pulses.unshift({ age: 0.0, amp: Math.min(1.0, bass) });
        if (pulses.length > MAX_PULSES) pulses.pop();
        cooldown = 0.18;
    }
    prev = bass;

    var p0 = pulses[0], p1 = pulses[1], p2 = pulses[2], p3 = pulses[3];
    setUniform("pulse_age0", p0 ? p0.age : 100.0);
    setUniform("pulse_amp0", p0 ? p0.amp : 0.0);
    setUniform("pulse_age1", p1 ? p1.age : 100.0);
    setUniform("pulse_amp1", p1 ? p1.amp : 0.0);
    setUniform("pulse_age2", p2 ? p2.age : 100.0);
    setUniform("pulse_amp2", p2 ? p2.amp : 0.0);
    setUniform("pulse_age3", p3 ? p3.age : 100.0);
    setUniform("pulse_amp3", p3 ? p3.amp : 0.0);
}
