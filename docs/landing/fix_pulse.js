const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

html = html.replace(
    /animation: e-pulseIn 1\.5s infinite;/g,
    'animation: e-pulseIn1 1.5s infinite;'
);
html = html.replace(
    /animation: e-pulseIn 1\.5s infinite 0\.75s;/g,
    'animation: e-pulseIn2 1.5s infinite 0.75s;'
);

const newKeyframes = `
        @keyframes e-pulseIn1 {
            0% { transform: translate(0, 0); opacity: 0; }
            20% { opacity: 1; }
            80% { opacity: 1; }
            100% { transform: translate(65px, 15px); opacity: 0; }
        }
        @keyframes e-pulseIn2 {
            0% { transform: translate(0, 0); opacity: 0; }
            20% { opacity: 1; }
            80% { opacity: 1; }
            100% { transform: translate(65px, -15px); opacity: 0; }
        }
`;
html = html.replace(/@keyframes e-pulseIn \{[\s\S]*?100% \{ transform: translate\(65px, 0px\); opacity: 0; \}\s*\}/, newKeyframes);

fs.writeFileSync('index.html', html);
console.log('Fixed pulses');
