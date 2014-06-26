#target illustrator
#targetengine main
#include "./lib/l0utils.jsxinc"

var doc = app.activeDocument
var clipGroups = _.where(doc.groupItems, {'clipped' : true})

_(clipGroups).forEach(function(clipGroup)
{
    
    var clipPath = _.filter(clipGroup.pageItems, function(pI){
        // return pI.clipping || pI.typename=="CompoundPathItem" && pI.pathItems[0].clipping})[0]
        // apparently compound clipping paths always return 0 pathItems which leaves me with no way to determine wether a compound path is a clipping path. bug?
        return pI.clipping || pI.typename=="CompoundPathItem"})[0]
    
    _.chain(l0.getAllPaths(clipGroup)).reject({'clipping' : true}).forEach(function(path)
    {
        tmpGroup = clipGroup.parent.groupItems.add()
        tmpClipPath = clipPath.duplicate(tmpGroup, ElementPlacement.PLACEATEND)
        path.move(tmpGroup, ElementPlacement.PLACEATEND)
        doc.selection = [tmpGroup]        
        app.executeMenuCommand("Live Pathfinder Crop")
        app.executeMenuCommand("expandStyle")
    })
})