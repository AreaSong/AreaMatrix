const fs = require('fs');
const path = require('path');

const prototypeRoot = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(prototypeRoot, 'index.html'), 'utf8');

const defaultMatch = html.substring(html.indexOf('<div class="stage-view active" id="stage-default">'), html.indexOf('<div class="stage-view" id="stage-feat-1">'));
console.log("stage-default block:\n", defaultMatch);
