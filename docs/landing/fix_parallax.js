const fs = require('fs');
let content = fs.readFileSync('index.html', 'utf8');

// 1. Add preserve-3d to dioramas
const dioramas = ['.visual-classify-diorama', '.visual-security-diorama', '.visual-tracking-diorama', '.visual-help-diorama', '.visual-start'];
dioramas.forEach(d => {
    content = content.replace(new RegExp(`(${d.replace(/\./g, '\\.')}\\s*{[^{}]*)`, 'g'), '$1 transform-style: preserve-3d;');
});

// 2. Classify (Stage 1)
content = content.replace('.mock-am-app { width: 340px;', '.mock-am-app { transform: translateZ(20px); width: 340px;');
content = content.replace('transform: translateY(-50%); z-index: 30;}', 'transform: translateY(-50%) translateZ(60px); z-index: 30;}');
content = content.replace(/@keyframes c-dragFile \{([^\}]+)\}/, `@keyframes c-dragFile { 0%, 10% { transform: translate(0, 0) scale(1) translateZ(40px); opacity: 1; } 25%, 40% { transform: translate(210px, -20px) scale(0.6) translateZ(20px); opacity: 1; } 45%, 85% { transform: translate(210px, -20px) scale(0.6) translateZ(20px); opacity: 0; } 90%, 100% { transform: translate(0, 0) scale(1) translateZ(40px); opacity: 0; } }`);

// 3. Security (Stage 2)
content = content.replace('.am-layer { width: 380px;', '.am-layer { transform: translateZ(60px); width: 380px;');
content = content.replace('.os-layer { width: 380px;', '.os-layer { transform: translateZ(20px); width: 380px;');
content = content.replace(/@keyframes s-shieldPulse \{([^\}]+)\}/, `@keyframes s-shieldPulse { 0%, 100% { transform: translate(-50%, -50%) translateZ(40px); box-shadow: 0 0 24px 6px rgba(241, 184, 78, 0.2); } 50% { transform: translate(-50%, -50%) translateZ(40px); box-shadow: 0 0 40px 10px rgba(241, 184, 78, 0.5); } }`);

// 4. Tracking (Stage 3)
content = content.replace('.mock-editor {', '.mock-editor { transform: translateZ(50px);');
content = content.replace('.sync-bridge {', '.sync-bridge { transform: translateZ(40px);');

// Need to specifically target mock-finder if it doesn't have a direct class rule for it, but we have .mock-finder
// I'll add .mock-finder { transform: translateZ(30px); }
content = content.replace('.mock-finder .mac-body {', '.mock-finder { transform: translateZ(30px); }\n        .mock-finder .mac-body {');

// 5. Help Engine (Stage 4)
content = content.replace('.fs-event-source { position: absolute;', '.fs-event-source { transform: translateZ(40px); position: absolute;');
content = content.replace('.db-target { position: absolute;', '.db-target { transform: translateZ(20px); position: absolute;');
content = content.replace(/@keyframes e-coreBeat \{([^\}]+)\}/, `@keyframes e-coreBeat { 0% { transform: scale(1) translateZ(80px); box-shadow: 0 0 20px rgba(147, 51, 234, 0.3); } 100% { transform: scale(1.05) translateZ(80px); box-shadow: 0 0 60px rgba(147, 51, 234, 0.6); } }`);

// 6. Start (Stage 5)
content = content.replace(/@keyframes hJumboPulse \{([^\}]+)\}/, `@keyframes hJumboPulse { 0%, 100% { transform: scale(1) translateZ(60px); filter: brightness(1); box-shadow: 0 0 40px rgba(16, 185, 129, 0.3); } 50% { transform: scale(1.05) translateZ(60px); filter: brightness(1.2); box-shadow: 0 0 80px rgba(52, 211, 153, 0.6); } }`);
content = content.replace(/@keyframes hAuraExpand \{([^\}]+)\}/, `@keyframes hAuraExpand { 0% { transform: translate(-50%, -50%) scale(0.9) translateZ(20px); opacity: 1; } 100% { transform: translate(-50%, -50%) scale(1.7) translateZ(20px); opacity: 0; } }`);

fs.writeFileSync('index.html', content);
