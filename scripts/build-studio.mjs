import {mkdir,copyFile,writeFile,access} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'..');
const output=process.env.STUDIO_OUTPUT_DIR ? path.resolve(process.env.STUDIO_OUTPUT_DIR) : path.join(root,'.runtime/studio');
const sdk=process.env.WEBVIEW2_SDK_DIR || 'C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/PrivateAssemblies';
const framework='C:/Windows/Microsoft.NET/Framework64/v4.0.30319';
await mkdir(output,{recursive:true});
for(const file of ['Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll','WebView2Loader.dll']){
    try{await access(path.join(sdk,file));}catch{throw new Error('Set WEBVIEW2_SDK_DIR to the WebView2 .NET Framework SDK folder containing '+file);}
    await copyFile(path.join(sdk,file),path.join(output,file));
}
const args=['/nologo','/target:winexe','/platform:x64','/optimize+','/out:'+path.join(output,'MARCDroneStudio.exe')];
for(const file of ['System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll','System.Xaml.dll']) args.push('/reference:'+path.join(framework,file));
for(const file of ['WindowsBase.dll','PresentationFramework.dll','PresentationCore.dll','WindowsFormsIntegration.dll']) args.push('/reference:'+path.join(framework,'WPF',file));
for(const file of ['Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll']) args.push('/reference:'+path.join(output,file));
args.push('/win32manifest:'+path.join(root,'desktop/studio.manifest'),path.join(root,'desktop/Studio.cs'));
const code=await new Promise((resolve,reject)=>{const child=spawn(path.join(framework,'csc.exe'),args,{cwd:root,windowsHide:true,stdio:'inherit'});child.on('error',reject);child.on('exit',resolve);});
if(code!==0) process.exit(code||1);
await writeFile(path.join(output,'MARCDroneStudio.exe.config'),'<?xml version="1.0"?><configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>');
console.log('STUDIO_BUILD_OK '+path.join(output,'MARCDroneStudio.exe'));
