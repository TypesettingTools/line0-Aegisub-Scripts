#target illustrator
#targetengine main

// Polyfill for indexOf pasted from https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/indexOf
if (!Array.prototype.indexOf) {
    Array.prototype.indexOf = function (searchElement, fromIndex) {
      if ( this === undefined || this === null ) {
        throw new TypeError( '"this" is null or not defined' );
      }

      var length = this.length >>> 0; // Hack to convert object.length to a UInt32

      fromIndex = +fromIndex || 0;

      if (Math.abs(fromIndex) === Infinity) {
        fromIndex = 0;
      }

      if (fromIndex < 0) {
        fromIndex += length;
        if (fromIndex < 0) {
          fromIndex = 0;
        }
      }

      for (;fromIndex < length; fromIndex++) {
        if (this[fromIndex] === searchElement) {
          return fromIndex;
        }
      }

      return -1;
    };
}

app.userInteractionLevel = UserInteractionLevel.DONTDISPLAYALERTS
app.documents.length > 0 ? main() : alert("Please create an empty document before running this script.");

function main() {
    var folders = []
    var doc = app.activeDocument

    var traceDlgRes ="Group { orientation:'column', alignment:['fill', 'fill'], alignChildren:['fill', 'fill'], \
        imgFolder: Panel { orientation:'row', text: 'Image Folder', \
            edit: EditText {text: ' [Pick a folder of images to batch trace]', characters: 50}\
            btn: Button { text:'...' , preferredSize: [30,24]} ,\
        }, \
        bgFolder: Panel { orientation:'row', text: 'Background Image Folder (optional)', \
            edit: EditText {text: ' [none]', characters: 50}, \
            btn: Button { text:'...', preferredSize: [30,24] } \
        }, \
        sti: Group { orientation: row,\
            settings: Panel {orientation: 'column', alignment:['left', 'fill'], alignChildren: ['left','fill'], text: 'Settings', \
                preset: DropDownList {characters: 50, title: 'Tracing Preset:'}, \
                imgPos: Group {orientation: 'row', spacing: 5, \
                    st1: StaticText {text: 'Image Position:'}, \
                    x: EditText {text: '0', characters: 5}, \
                    st2: StaticText {text: 'x'}, \
                    y: EditText {text: '0', characters: 5}, \
                    st3: StaticText {text: 'px'}, \
                }, \
                intersect: Checkbox{text:'Intersect with predefined Path', enabled: false}, \
            }, \
            info: Panel {orientation: 'column', text: 'Information', alignment:['right', 'fill'], alignChildren: ['left','fill'], \
                imgFolder: Group {orientation: 'row', spacing: 5, \
                    st1: StaticText {text: 'Image Count: '}, \
                    cnt: StaticText {text: 'No Folder', characters: 9}, \
                }, \
                bgFolder: Group {orientation: 'row', spacing: 5,\
                    st1: StaticText {text: 'Background Image Count: '}, \
                    cnt: StaticText {text: 'No Folder', characters: 9}, \
                }, \
            progress: Progressbar {value: 0, size: [250,25]}\
            }, \
      }, \
      trace: Button {text: 'Trace', enabled: false, alignment: ['fill', 'fill']}, \
    }"

    var dlg = new Window("dialog", "Batch Trace", void 0, {resizeable: true, independent: true})
    dlg.traceDlg = dlg.add(traceDlgRes);

    // populate tracing presets list
    for (i=0; i<app.tracingPresetsList.length; i++) { dlg.traceDlg.sti.settings.preset.add("item", app.tracingPresetsList[i]) }
    dlg.traceDlg.sti.settings.preset.selection = app.tracingPresetsList.indexOf("_autoTrace") >= 0 ? app.tracingPresetsList.indexOf("_autoTrace") : app.tracingPresetsList.indexOf("[Default]") 
    
    // properly handle resizing
    dlg.layout.layout(true);
    dlg.traceDlg.minimumSize = dlg.traceDlg.size;
    dlg.layout.resize();
    dlg.onResizing = dlg.onResize = function () {this.layout.resize()}

    // event handling
    dlg.traceDlg.imgFolder.btn.onClick = function() {pickFolder("imgFolder", true, "Select the folder of images to trace...")}
    dlg.traceDlg.imgFolder.edit.onChanging = function() {pickFolder("imgFolder", false)}
    dlg.traceDlg.bgFolder.btn.onClick = function() {pickFolder("bgFolder", true, "Select the background image folder...")}
    dlg.traceDlg.bgFolder.edit.onChanging = function() {pickFolder("bgFolder", false)}   
    dlg.traceDlg.trace.onClick = function() {doTrace()}
    
    dlg.traceDlg.sti.settings.intersect.enabled = checkIntersect()
    dlg.show()


    
function pickFolder(folder, showPicker, prompt)
    {
            if (showPicker) {
                    folders[folder] = Folder.selectDialog(prompt)
                    if(folders[folder] != null) dlg.traceDlg[folder].edit.text = folders[folder].fsName
            } else {
                    folders[folder] = new Folder(dlg.traceDlg[folder].edit.text)
            }
            if(folders[folder] && folders[folder].exists) {
                dlg.traceDlg.sti.info[folder].cnt.text = getImageFiles(folders[folder]).length 
                dlg.traceDlg.trace.enabled = true
            } else {
                dlg.traceDlg.sti.info[folder].cnt.text = "No Folder"
                dlg.traceDlg.trace.enabled = false
            }
    }

    function checkIntersect()
    {
        return doc.pageItems.length > 0 && (doc.pageItems[0].typename == "PathItem" || doc.pageItems[0].typename == "CompoundPathItem") ? true : false
    }

    function getImageFiles(folder)
    {
        if(folder instanceof Folder)
        {
            var extensions = ["bmp", "gif", "giff", "jpeg", "jpg", "pct", "pic", "psd", "png", "tif", "tiff"]
            var files = folder.getFiles()
            
            for (var i=0; i<files.length; i++)
            {
                var fileExt = splitFilename(String(files[i]),true)
                if (!(files[i] instanceof File) || extensions.indexOf(fileExt) == -1) {
                    files.splice(i,1)
                    i--
                }
            }
            return files
        } else return false
    }
    
    function splitFilename(name, returnExt)
    {
        var basename = name.split(".")
        var ext = basename.pop()
        return returnExt ? ext : basename.join(".")
    }

    function placeImg(file, layer)
    {
            var img = doc.placedItems.add()
            img.file = new File(file)
            img.layer = layer
            img.position = [parseInt(dlg.traceDlg.sti.settings.imgPos.x.text,10), parseInt(dlg.traceDlg.sti.settings.imgPos.y.text,10)]
            return img
    }

    function movePathsToCompound(container, cmpnd)
    {
           while(container.pathItems.length > 0) {
                container.pathItems[0].move(cmpnd, ElementPlacement.PLACEATEND)
           } 
           if(container.compoundPathItems) {
                while(container.compoundPathItems.length > 0) { 
                     movePathsToCompound(container.compoundPathItems[0], cmpnd)
                      container.compoundPathItems[0].remove()
                }
           }
     }
    function doTrace()
    {
        dlg.traceDlg.trace.enabled = false
        dlg.traceDlg.trace.text = "Tracing..."
        
        var images = getImageFiles (folders["imgFolder"])
        var bgimages = getImageFiles (folders["bgFolder"])
        var intersectPath = dlg.traceDlg.sti.settings.intersect.enabled ? doc.pageItems[0] : null
        
        for (var i=0; i<images.length; i++)
        {
            layer = doc.layers.add()
            layer.name = splitFilename(images[i].displayName)
            
            if(bgimages[i]) 
            {
                bgimg = placeImg(bgimages[i], layer)
                bgimg.locked = true
            }
            pimg = placeImg(images[i], layer)
            
            var t = pimg.trace()
            t.tracing.tracingOptions.loadFromPreset(dlg.traceDlg.sti.settings.preset.selection.text)
            app.redraw()
            traceGrp = t.tracing.expandTracing()
            if(intersectPath)
            {
                    intersectPathTmp = intersectPath.duplicate(layer, ElementPlacement.PLACEATBEGINNING)
                    intersectPathTmp.filled = true
                    intersectPathTmp.stroked = false    
                    cmpPath = layer.compoundPathItems.add()
                    
                    movePathsToCompound (traceGrp, cmpPath)
                    cmpPath.move(traceGrp, ElementPlacement.PLACEATEND)
                    intersectPathTmp.move(traceGrp, ElementPlacement.PLACEATEND)

                    doc.selection = [traceGrp]        
                    app.executeMenuCommand("Live Pathfinder Intersect")
                    app.executeMenuCommand("expandStyle")
            }
            layer.visible = (i==images.length -1) ? true : false
            dlg.traceDlg.sti.info.progress.value = ((i+1)/images.length) * 100
            dlg.update()
        }
        dlg.close()
    }
}

