import {spawn} from 'node:child_process';
import {existsSync} from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const exe=path.join(root,'.runtime/studio/MARCDroneStudio.exe');
if(!existsSync(exe)) throw new Error('Run npm run studio:build first.');
const child=spawn(exe,[root],{cwd:root,detached:true,stdio:'ignore',windowsHide:false});
child.on('error',error=>{console.error(error);process.exitCode=1;});
child.unref();
