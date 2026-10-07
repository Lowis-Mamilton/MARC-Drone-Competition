import {installDroneToolbox} from './drone-toolbox.mjs';
import {MARCConnection, MARCExtension} from './marc-extension.mjs';
const status = document.querySelector('#status');
const errorBox = document.querySelector('#error');
let vm;
let halted = false;
let stopSuppressed = false;
let runGeneration = 0;
let starterLoaded = false;
let projectLoading = true;
let projectDirty = false;
let currentExample = '';
let lastHostState = '';
let vmRunning = false;
const exampleSelect = document.querySelector('#example');
const hint = document.querySelector('#example-hint');
const publishState = () => {
    const state = {type:'state', connected:connection.connected, running:vmRunning};
    const key = JSON.stringify(state);
    if (key !== lastHostState) {lastHostState=key; notifyHost(state);}
};
const markClean = () => {projectDirty=false;notifyHost({type:'loaded'});};
const markChanged = () => {
    if(projectLoading || projectDirty) return;
    projectDirty=true;
    currentExample=''; exampleSelect.value='';
    hint.textContent='自訂程式 · 拖曳積木編排飛行動作，按「執行」試飛。記得儲存你的修改。';
    notifyHost({type:'dirty'});
};
let connectionReady;
const EXAMPLES = {
    takeoff:'起飛到 50 公分 → 懸停 2 秒 → 降落。按上方「執行」試飛。',
    forward:'起飛 → 向前 60 公分 → 等待 1 秒 → 返回 → 降落。',
    led:'起飛 → 紅、綠、藍燈各亮 1 秒 → 降落。',
    color:'進階：飛至色卡上方、讀色並同步 LED，最後返回停機坪。',
    shortcut:'進階：以底部高度 90 公分穿越捷徑圈，再返航降落。'
};
const showError = error => {
    notifyHost({type:'error',message:error.message || String(error)});
    document.documentElement.classList.remove('drone-loading');
    errorBox.textContent = error.message || String(error);
    errorBox.style.display = 'block';
    if (vm && !halted) {halted = true; vm.stopAll(); halted = false;}
};
const connection = new MARCConnection(state => {
    status.textContent = state.error || (vmRunning ? '● 程式執行中' : '● 模擬器已連線');
    status.classList.toggle('offline', Boolean(state.error));
    document.querySelector('#reconnect').hidden = !state.error;
    publishState();
});
window.marcConnection = connection;
const connect = () => {
    connectionReady=connection.connect().then(()=>{errorBox.style.display='none';publishState();}).catch(showError);
    return connectionReady;
};
const setupVM = nextVM => {
    vm = nextVM;
    window.marcVM = vm;
    vm.runtime.on('PROJECT_CHANGED',markChanged);
    vm.runtime.on('PROJECT_RUN_START',()=>{vmRunning=true;publishState();});
    vm.runtime.on('PROJECT_RUN_STOP',()=>{
        vmRunning=false;publishState();
        if(!stopSuppressed && connection.connected) connection.stop().catch(()=>{});
    });
    vm.runtime.on('PROJECT_LOADED',()=>{
        if(!starterLoaded) {starterLoaded=true;queueMicrotask(()=>loadPreset('takeoff').catch(showError));}
    });
    const extension = new MARCExtension(connection,showError);
    const manager = vm.extensionManager;
    const service = manager._registerInternalExtension(extension);
    manager._loadedExtensions.set('marc',service);
    // Register before deserializing .sb3 so MARC opcodes survive project loads.
    const originalGreenFlag = vm.greenFlag.bind(vm);
    vm.greenFlag = () => {
        const generation = ++runGeneration;
        stopSuppressed = true;
        vm.stopAll();
        stopSuppressed = false;
        errorBox.style.display='none';
        connection.stop().then(()=>generation === runGeneration ? connection.start() : null).then(()=>{
            if (generation !== runGeneration) return;
            stopSuppressed = true;
            originalGreenFlag();
            stopSuppressed = false;
        }).catch(showError);
    };
    vm.runtime.on('PROJECT_STOP_ALL',()=> {
        if(!stopSuppressed && connection.connected) {runGeneration++; connection.stop().catch(()=>{});}
    });
};
const loadPreset = async name => {
    ++runGeneration;
    await connectionReady;
    if(!connection.connected) throw new Error('模擬器尚未連線，請按重新連線後再載入範例');
    stopSuppressed=true;
    vm.stopAll();
    stopSuppressed=false;
    await connection.stop().catch(()=>{});
    const response = await fetch(`/examples/${name}.sb3`);
    if(!response.ok) throw new Error('找不到範例專案');
    projectLoading=true;
    try {await vm.loadProject(await response.arrayBuffer());}
    finally {projectLoading=false;}
    currentExample=name; exampleSelect.value=name;
    hint.textContent=EXAMPLES[name];
    markClean();
    document.documentElement.classList.remove('drone-loading');
    window.marcReady=true;
};
const loadExample = async name => {
    if(!name || !vm) return;
    if(projectDirty && !confirm('載入範例將取代尚未儲存的修改。請先按上方「儲存」保留程式。是否繼續？')) {exampleSelect.value=currentExample;return;}
    exampleSelect.disabled=true;
    try {await loadPreset(name);}
    catch(error) {exampleSelect.value=currentExample;throw error;}
    finally {exampleSelect.disabled=false;}
};
document.querySelector('#reconnect').onclick=connect;
document.querySelector('#run').onclick=()=>vm?.greenFlag();
document.querySelector('#emergency').onclick=()=>{vm?.stopAll();connection.stop().catch(showError);};
document.querySelector('#reset').onclick=()=>window.marcStudio.reset();
document.querySelector('#example').onchange=event=>loadExample(event.target.value).catch(showError);

const embedded = new URLSearchParams(location.search).get('embedded') === '1';
if (embedded) document.documentElement.classList.add('embedded');
const notifyHost = message => window.chrome?.webview?.postMessage(message);
if(embedded) document.addEventListener('keydown',event=>{
    if(event.altKey || event.metaKey || event.repeat) return;
    let action;
    if(event.key==='F5' && !event.ctrlKey) action=event.shiftKey?'stop':'run';
    if(event.ctrlKey && !event.shiftKey) action={s:'save',o:'open',r:'reset'}[event.key.toLowerCase()];
    if(!action) return;
    event.preventDefault();event.stopImmediatePropagation();
    notifyHost({type:'shortcut',action});
},true);
const toBase64 = bytes => {
    let text = '';
    for(let offset=0;offset<bytes.length;offset+=32768) text+=String.fromCharCode(...bytes.subarray(offset,offset+32768));
    return btoa(text);
};
window.marcStudio = {
    run() {if(!vmRunning) vm.greenFlag();},
    markSaved() {projectDirty=false;},
    markUnsaved() {projectDirty=false;markChanged();},
    async openControllerSettings(tab = 'controller') {
        try {await connection.request('controller_settings', {tab});}
        catch(error) {showError(error);}
    },
    async reset() {
        ++runGeneration;
        stopSuppressed = true;
        try {
            vm.stopAll();
            await connection.reset();
            errorBox.style.display = 'none';
            notifyHost({type:'reset'});
            return true;
        } catch(error) {showError(error); return false;}
        finally {stopSuppressed = false;}
    },
    async save() {
        try {
            const file = await vm.saveProjectSb3();
            notifyHost({type:'saved',base64:toBase64(new Uint8Array(await file.arrayBuffer()))});
        } catch(error) {showError(error);}
    },
    async load(base64) {
        try {
            ++runGeneration;
            vm.stopAll();
            await connection.stop().catch(()=>{});
            const bytes=Uint8Array.from(atob(base64),character=>character.charCodeAt(0));
            projectLoading=true;
            try {await vm.loadProject(bytes.buffer);} finally {projectLoading=false;}
            currentExample=''; exampleSelect.value='';
            hint.textContent='自訂程式 · 按「執行」試飛，按「重置」返回停機坪。';
            markClean();
        } catch(error) {showError(error);}
    }
};

const GUI = window.GUI;
if (!GUI?.default || !GUI.AppStateHOC) throw new Error('Scratch 編輯器未完整建置');
GUI.setAppElement(document.querySelector('#app'));
const DroneEditor = props => {
    const store=window['react-redux'].useStore();
    installDroneToolbox(store);
    return window.react.createElement(GUI.default,props);
};
const Wrapped = GUI.AppStateHOC(DroneEditor);
const root = window.MARCRoot.createRoot(document.querySelector('#app'));
root.render(window.react.createElement(Wrapped, {
    canSave:false, canEditTitle:true, backpackVisible:false, showComingSoon:false,
    onVmInit:setupVM, onProjectLoaded:()=>{},
    onClickLogo:()=>{},
    basePath:'editor/',
    projectId:'0',
    assetHost:location.origin,
    projectHost:location.origin,
    intl:undefined
}));
connect();
