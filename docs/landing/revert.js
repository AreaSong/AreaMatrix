const fs = require('fs');
let html = fs.readFileSync('index.html', 'utf8');

// 1. Remove Auto-play Logic
html = html.replace(/\/\/ Auto-play Logic[\s\S]*?startAutoPlay\(\);\n/, '');

// 2. Remove hasUserInteracted = true;
html = html.replace(/hasUserInteracted = true;\n\s*clearInterval\(autoPlayTimer\);\n\s*/g, '');

fs.writeFileSync('index.html', html);
console.log('Reverted auto-play');
