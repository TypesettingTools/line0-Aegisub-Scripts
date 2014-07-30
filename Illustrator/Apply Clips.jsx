#target illustrator
#targetengine main
#include "./lib/l0utils.jsxinc"

l0_applyClips()

function l0_applyClips() {
    var prog = l0.progressBar("Applying clips...", applyClips_process)
    prog.start()

    function applyClips_process()
    {
        var clipGroups = _.where(doc.groupItems, {'clipped' : true})
        l0.setCompoundPathClipping(doc)
        _(clipGroups).forEach(function(clipGroup,j)
        {
            var paths = l0.getPaths(clipGroup, ["PathItem", "CompoundPathItem"])
            var clipPath = _.where(paths, {'clipping' : true})[0]

            _.chain(paths).reject({'clipping' : true}).forEach(function(pI,i,pIs)
            {
                prog.setStatus("Group: " + (j+1) + "  Path: " + i)
                tmpGroup = clipGroup.parent.groupItems.add()
                tmpClipPath = clipPath.duplicate(tmpGroup, ElementPlacement.PLACEATEND)
                pI.move(tmpGroup, ElementPlacement.PLACEATEND)
                doc.selection = [tmpGroup]        
                app.executeMenuCommand("Live Pathfinder Crop")
                app.executeMenuCommand("expandStyle")
                while(doc.selection[0].pageItems.length>0) {
                    doc.selection[0].pageItems[0].move(doc.selection[0].parent, ElementPlacement.PLACEATEND)
                }
                prog.setProgress((j+1)*(i+1)/(clipGroups.length*pIs.length))
            })
            clipPath.remove()
        })
        prog.close()
    }
}