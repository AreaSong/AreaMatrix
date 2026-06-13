const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');

const styleMatch = html.match(/<style>([\s\S]*?)<\/style>/);
if (!styleMatch) process.exit(0);

const css = styleMatch[1];
let depth = 0;
const lines = css.split('\n');

for(let i=0; i<lines.length; i++) {
    const line = lines[i];
    for(let j=0; j<line.length; j++) {
        if (line[j] === '{') depth++;
        if (line[j] === '}') depth--;
    }
    if (depth < 0) {
        console.log(`Error on line ${i+1} of CSS. Depth is ${depth}`);
        console.log(line);
        break;
    }
}
console.log(`Final depth: ${depth}`);
