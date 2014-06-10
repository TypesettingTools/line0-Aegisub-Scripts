#target illustrator
#targetengine main
#include "./lib/l0utils.jsxinc"

l0_sort_pos()

function l0_sort_pos() {
    var doc = app.activeDocument
    l0.genGUIDs(doc.selection[0].layer)
    var pIs = doc.selection[0].layer.pageItems
    var pIsSort = []
    
    for(var i=0; i<pIs.length; i++) {
        pIsSort.push({'guid' : pIs[i].guid, 'x' : pIs[i].geometricBounds[0], 'y' : -pIs[i].geometricBounds[1], 'idx' : i})
    }
    _.chain(pIsSort).sortBy(['y','x']).forEach(function(pISort,i) {
        match = _.find(pIs, {'guid': pISort.guid})
        l0.reorderPageItem(match, i-pISort.idx)
    })
}
