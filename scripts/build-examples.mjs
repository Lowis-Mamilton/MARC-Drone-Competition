import {createRequire} from 'node:module';
import {mkdir,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import path from 'node:path';
const require=createRequire(path.resolve(import.meta.dirname,'../scratch/package.json'));
const JSZip=require('jszip');
const out=path.resolve(import.meta.dirname,'../examples');
await mkdir(out,{recursive:true});
const costume='<svg xmlns="http://www.w3.org/2000/svg" width="80" height="80"><circle cx="40" cy="40" r="30" fill="#167a91"/><text x="40" y="47" text-anchor="middle" font-family="sans-serif" font-size="18" fill="white">MARC</text></svg>';
const assetId=createHash('md5').update(costume).digest('hex');
function makeProject(steps){
    const blocks={green:{opcode:'event_whenflagclicked',next:steps.length?'b0':null,parent:null,inputs:{},fields:{},shadow:false,topLevel:true,x:80,y:60}};
    steps.forEach(([op,args],i)=>{
        const inputs={};
        for(const [key,value] of Object.entries(args||{})) inputs[key]=[1,[typeof value==='number'?4:10,String(value)]];
        blocks[`b${i}`]={opcode:`marc_${op}`,next:i+1<steps.length?`b${i+1}`:null,parent:i?`b${i-1}`:'green',inputs,fields:{},shadow:false,topLevel:false};
    });
    return {targets:[{isStage:true,name:'Stage',variables:{},lists:{},broadcasts:{},blocks,comments:{},currentCostume:0,costumes:[{name:'MARC',assetId,md5ext:assetId+'.svg',dataFormat:'svg',rotationCenterX:40,rotationCenterY:40}],sounds:[],volume:100,layerOrder:0,tempo:60,videoTransparency:50,videoState:'off',textToSpeechLanguage:null}],monitors:[],extensions:['marc'],meta:{semver:'3.0.0',vm:'15.2.0',agent:'MARC Drone Simulator'}};
}
const examples={
    takeoff:[['takeoff',{H:50}],['wait',{S:2}],['land']],
    forward:[['takeoff',{H:50}],['move',{X:60,Y:0,H:0}],['wait',{S:1}],['move',{X:-60,Y:0,H:0}],['land']],
    led:[['takeoff',{H:50}],['led',{COLOR:'red'}],['wait',{S:1}],['led',{COLOR:'green'}],['wait',{S:1}],['led',{COLOR:'blue'}],['wait',{S:1}],['led',{COLOR:'white'}],['land']],
    color:[['takeoff',{H:50}],['goto',{X:220,Y:140,H:50}],['goto',{X:220,Y:140,H:20}],['match'],['wait',{S:2.2}],['led',{COLOR:'white'}],['goto',{X:220,Y:140,H:50}],['goto',{X:40,Y:160,H:50}],['land']],
    shortcut:[['takeoff',{H:90}],['goto',{X:100,Y:200,H:90}],['goto',{X:180,Y:200,H:90}],['goto',{X:180,Y:160,H:90}],['goto',{X:40,Y:160,H:50}],['land']]
};
for(const [name,steps] of Object.entries(examples)){
    const zip=new JSZip();
    zip.file('project.json',JSON.stringify(makeProject(steps)));
    zip.file(assetId+'.svg',costume);
    await writeFile(path.join(out,name+'.sb3'),await zip.generateAsync({type:'nodebuffer',compression:'DEFLATE'}));
}
console.log('Created five drone .sb3 examples');
