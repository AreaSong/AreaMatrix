const fs = require('fs');
let content = fs.readFileSync('index.html', 'utf8');

content = content.replace(/@keyframes c-dragFile \{[\s\S]*?opacity: 0;\n            }\n        \}/, `@keyframes c-dragFile { 0%, 10% { transform: translate(0, 0) scale(1) translateZ(40px); opacity: 1; } 25%, 40% { transform: translate(210px, -20px) scale(0.6) translateZ(20px); opacity: 1; } 45%, 85% { transform: translate(210px, -20px) scale(0.6) translateZ(20px); opacity: 0; } 90%, 100% { transform: translate(0, 0) scale(1) translateZ(40px); opacity: 0; } }`);

content = content.replace(/@keyframes s-shieldPulse \{[\s\S]*?rgba\(241, 184, 78, 0\.5\);\n            }\n        \}/, `@keyframes s-shieldPulse { 0%, 100% { transform: translate(-50%, -50%) translateZ(40px); box-shadow: 0 0 24px 6px rgba(241, 184, 78, 0.2); } 50% { transform: translate(-50%, -50%) translateZ(40px); box-shadow: 0 0 40px 10px rgba(241, 184, 78, 0.5); } }`);

content = content.replace(/@keyframes e-coreBeat \{[\s\S]*?rgba\(147, 51, 234, 0\.6\);\n            }\n        \}/, `@keyframes e-coreBeat { 0% { transform: scale(1) translateZ(80px); box-shadow: 0 0 20px rgba(147, 51, 234, 0.3); } 100% { transform: scale(1.05) translateZ(80px); box-shadow: 0 0 60px rgba(147, 51, 234, 0.6); } }`);

fs.writeFileSync('index.html', content);
