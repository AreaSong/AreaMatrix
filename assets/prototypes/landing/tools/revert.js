const fs = require('fs');
const path = require('path');

const prototypeRoot = path.resolve(__dirname, '..');
const indexPath = path.join(prototypeRoot, 'index.html');
let html = fs.readFileSync(indexPath, 'utf8');

// 1. Remove Auto-play Logic
html = html.replace(/\/\/ Auto-play Logic[\s\S]*?startAutoPlay\(\);\n/, '');

// 2. Remove hasUserInteracted = true;
html = html.replace(/hasUserInteracted = true;\n\s*clearInterval\(autoPlayTimer\);\n\s*/g, '');

fs.writeFileSync(indexPath, html);
console.log('Reverted auto-play');
