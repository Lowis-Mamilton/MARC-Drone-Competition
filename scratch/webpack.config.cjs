const path = require('path');
module.exports = {
    mode:'production',
    entry:path.resolve(__dirname,'dependencies.js'),
    output:{path:path.resolve(__dirname,'../web/scratch'),filename:'dependencies.js'},
    optimization:{minimize:true},
    performance:{hints:false}
};
