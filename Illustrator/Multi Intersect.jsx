#target illustrator
#targetengine main
#include "./lib/l0utils.jsxinc"

 l0_batchTrace_multiIntersect()

function l0_batchTrace_multiIntersect() {
    var doc = app.activeDocument
    var orgLayerCnt = doc.layers.length

    _.chain(doc.layers[0].pageItems).filter(function(pageItem){
        return _.contains( ["PathItem", "CompoundPathItem"], pageItem.typename)
    }).forEach(function(intersectPath)
    {
        cLayer = doc.layers.add()
        cLayer.name = intersectPath.name
        cLayer.zOrder(ZOrderMethod.SENDTOBACK)

        for (var i=1; i < orgLayerCnt; i++) {
            sGrp = doc.layers[i].groupItems[0]
            pLayer = cLayer.layers.add()
            tGrp = sGrp.duplicate(pLayer, ElementPlacement.PLACEATEND)
            intersectPathTmp = intersectPath.duplicate(pLayer, ElementPlacement.PLACEATBEGINNING)
            intersectPathTmp.filled = true
            intersectPathTmp.stroked = false    
            cmpPath = pLayer.compoundPathItems.add()
            
            l0.movePathsToCompound(tGrp, cmpPath)
            cmpPath.move(tGrp, ElementPlacement.PLACEATEND)
            intersectPathTmp.move(tGrp, ElementPlacement.PLACEATEND)

            doc.selection = [tGrp]        
            app.executeMenuCommand("Live Pathfinder Intersect")
            app.executeMenuCommand("expandStyle")
        }
    })
}


