import {cp, mkdir, readFile, writeFile, readdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {gzipSync} from 'node:zlib';
import path from 'node:path';
const root = path.resolve(import.meta.dirname,'..');
const scratch = path.join(root,'scratch');
const require = createRequire(path.join(scratch,'package.json'));
const guiEntry = require.resolve('@scratch/scratch-gui');
const guiDist = path.dirname(guiEntry);
const out = path.join(root,'web/scratch');
await mkdir(out,{recursive:true});
const result = spawnSync(process.execPath,[require.resolve('webpack-cli/bin/cli.js'),'--config',path.join(scratch,'webpack.config.cjs')],{cwd:scratch,stdio:'inherit'});
if(result.status !== 0) process.exit(result.status || 1);
await mkdir(path.join(out,'editor'),{recursive:true});
await cp(guiDist,path.join(out,'editor'),{recursive:true,filter:source=> !source.endsWith('.map') && !source.includes('standalone') && !source.includes(`${path.sep}types`)});
await cp(path.join(scratch,'marc-extension.mjs'),path.join(out,'marc-extension.mjs'));
await cp(path.join(scratch,'editor.mjs'),path.join(out,'editor.mjs'));
await cp(path.join(scratch,'drone-toolbox.mjs'),path.join(out,'drone-toolbox.mjs'));
await cp(path.join(scratch,'index.html'),path.join(out,'index.html'));
for(const name of ['scratch-gui.js']) {
    const file = path.join(out,'editor',name);
    await writeFile(file+'.gz',gzipSync(await readFile(file),{level:9}));
}
const versions = {};
for(const pkg of ['@scratch/scratch-gui','@scratch/scratch-vm']) {
    const dir = path.resolve(require.resolve(pkg),'../..');
    const pkgRoot = pkg.endsWith('gui') ? path.dirname(guiDist) : path.join(scratch,'node_modules',pkg);
    versions[pkg] = JSON.parse(await readFile(path.join(pkgRoot,'package.json'),'utf8')).version;
    await cp(path.join(pkgRoot,'LICENSE'),path.join(out,pkg.endsWith('gui') ? 'SCRATCH-GUI-LICENSE' : 'SCRATCH-VM-LICENSE'));
}
await mkdir(path.join(out,'licenses'),{recursive:true});
for(const pkg of ['react','react-dom','react-redux','redux']){
    const pkgRoot=path.join(scratch,'node_modules',pkg);
    for(const name of ['LICENSE','LICENSE.md']){
        try{await cp(path.join(pkgRoot,name),path.join(out,'licenses',pkg+'-LICENSE'));break;}catch{}
    }
}
await writeFile(path.join(out,'versions.json'),JSON.stringify(versions,null,2));
console.log('Built local Scratch editor',versions);
