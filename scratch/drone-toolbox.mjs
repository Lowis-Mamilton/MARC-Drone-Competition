// Keep the VM-backed Scratch editor while exposing only drone programming.
const FLOW = new Set(['event_whenflagclicked','control_repeat','control_forever','control_if','control_if_else','control_wait_until','control_repeat_until','control_stop']);
const CONDITIONS = new Set(['operator_add','operator_subtract','operator_multiply','operator_divide','operator_random','operator_gt','operator_lt','operator_equals','operator_and','operator_or','operator_not','operator_mod','operator_round','operator_mathop']);

export function droneToolboxXML(xml) {
    const parser = new DOMParser();
    const source = parser.parseFromString(xml,'text/xml');
    const result = parser.parseFromString('<xml xmlns="http://www.w3.org/1999/xhtml"></xml>','text/xml');
    const root = result.documentElement;
    const drone = [...source.getElementsByTagName('category')].find(category=>(category.getAttribute('toolboxitemid') || category.getAttribute('id'))==='marc');
    if(drone) {
        const category=result.importNode(drone,true);
        category.setAttribute('name','無人機');
        root.appendChild(category);
    } else {
        const category=result.createElement('category');
        category.setAttribute('name','無人機');
        category.setAttribute('toolboxitemid','marc');
        category.setAttribute('colour','#167a91');
        category.setAttribute('secondaryColour','#0f6075');
        root.appendChild(category);
    }
    for(const [id,name,color,allowed] of [['control','流程','#ffab19',FLOW],['operators','判斷與運算','#59c059',CONDITIONS]]) {
        const category=result.createElement('category');
        category.setAttribute('toolboxitemid',id);
        category.setAttribute('name',name);
        category.setAttribute('colour',color);
        category.setAttribute('secondaryColour',color);
        for(const block of source.querySelectorAll('category > block')) {
            if(allowed.has(block.getAttribute('type'))) category.appendChild(result.importNode(block,true));
        }
        if(category.children.length) root.appendChild(category);
    }
    return new XMLSerializer().serializeToString(result);
}

export function installDroneToolbox(store) {
    if(store.marcToolboxInstalled) return;
    store.marcToolboxInstalled=true;
    const dispatch=store.dispatch.bind(store);
    store.dispatch=action=>dispatch(action.type==='scratch-gui/toolbox/UPDATE_TOOLBOX'
        ? {...action,toolboxXML:droneToolboxXML(action.toolboxXML)} : action);
    store.dispatch({type:'scratch-gui/toolbox/UPDATE_TOOLBOX',toolboxXML:store.getState().scratchGui.toolbox.toolboxXML});
}
