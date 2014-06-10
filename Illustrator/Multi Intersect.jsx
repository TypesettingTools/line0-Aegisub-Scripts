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
            
            // create temporary group for intersection 
            var tGrp = sGrp.duplicate(pLayer, ElementPlacement.PLACEATEND)
            
            // populate temporary group with copies of the original layer wrapped in a compound path (required for pathfinder to work) and intersection path
            // also generate GUIDs so we can track paths that didn't intersect and remove them later
            var intersectPathTmp = intersectPath.duplicate(pLayer, ElementPlacement.PLACEATBEGINNING)
            l0.genGUIDs(intersectPathTmp)
            var cmpPath = pLayer.compoundPathItems.add()        
            l0.movePathsToCompound(tGrp, cmpPath)
            cmpPath.move(tGrp, ElementPlacement.PLACEATEND)          
            intersectPathTmp.move(tGrp, ElementPlacement.PLACEATEND)
            
            // make sure intersection ignores colors and outlines just like the intersect pathfinder does. currently breaks with multicolored compound paths
            intersectPathTmp.filled = true
            intersectPathTmp.stroked = false
            intersectPathTmp.fillColor = cmpPath.pathItems[0].fillColor
            
            doc.selection = [tGrp]        
            app.executeMenuCommand("Live Pathfinder Intersect")
            app.executeMenuCommand("expandStyle")
            
            if (doc.selection[0].pageItems.length >= 1 && 
                l0.getGUID(intersectPathTmp) == l0.getGUID(doc.selection[0].pageItems[doc.selection[0].pageItems.length-1]))  {
                    tGrp.layer.pageItems.removeAll()
            }
        }
    })
}


