import {spawn} from 'node:child_process';
import {mkdirSync,existsSync} from 'node:fs';
import path from 'node:path';
const root = path.resolve(import.meta.dirname,'..');
const local = path.join(root,'.runtime');
for(const name of ['roaming','local','logs']) mkdirSync(path.join(local,name),{recursive:true});
const engine = process.env.GODOT_PATH || path.join(local,'engine','Godot.exe');
if(!existsSync(engine)) throw new Error('Set GODOT_PATH to Godot 4.7.2 or place it at .runtime/engine/Godot.exe');
const child = spawn(engine,['--path',root,'--log-file',path.join(local,'logs/godot.log'),...process.argv.slice(2)],{
    cwd:root,windowsHide:true,stdio:'inherit',env:{...process.env,APPDATA:path.join(local,'roaming'),LOCALAPPDATA:path.join(local,'local')}
});
for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>child.kill());
child.on('exit',code=>process.exit(code||0));
