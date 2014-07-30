#target illustrator
#targetengine main
#include "./lib/l0utils.jsxinc"

var doc = app.activeDocument
l0_extendPaths()

function l0_extendPaths() {

    var extDlgRes ="Group { orientation: 'column', alignment:['fill', 'fill'],  \
        top: Group {orientation: 'row', spacing: 5, \
            st1: StaticText {text: 'Top:'},\
            val: EditText {text: '0', characters: 5}, \
            st2: StaticText {text: 'px'}, \
        },\
        left: Group {orientation: 'row', spacing: 5, \
            st1: StaticText {text: 'Left:'},\
            val: EditText {text: '0', characters: 5}, \
            st2: StaticText {text: 'px'}, \
        },\
        bottom: Group {orientation: 'row', spacing: 5, \
            st1: StaticText {text: 'Bottom:'},\
            val: EditText {text: '0', characters: 5}, \
            st2: StaticText {text: 'px'}, \
        },\
        right: Group {orientation: 'row', spacing: 5, \
            st1: StaticText {text: 'Right:'},\
            val: EditText {text: '0', characters: 5}, \
            st2: StaticText {text: 'px'}, \
        },\
        clip: Checkbox {text: 'Also process clipping paths', value: false},\
        extend: Button {text: 'Extend Paths', enabled: true, alignment: ['fill', 'fill']}, \
        progress: Progressbar {value: 0, size: [130,25]}\
    }"

    var dlg = new Window("dialog", "Extend Paths", void 0, {resizeable: true, independent: false})
    dlg.extDlg = dlg.add(extDlgRes);
    
    // properly handle resizing
    dlg.layout.layout(true);
    dlg.extDlg.minimumSize = dlg.extDlg.size;
    dlg.layout.resize();
    dlg.onResizing = dlg.onResize = function () {this.layout.resize()}

    // event handling
    dlg.extDlg.extend.onClick = function() {doExtend()}
    dlg.show()
    
    function doExtend()
    {
        dlg.extDlg.extend.enabled = false
        dlg.extDlg.extend.text = "Extending..."
        
        _(l0.getPaths(doc.selection, ["PathItem","CompoundPathItem"], dlg.extDlg.clip.value ? {} :  {'clipping' : false} )).filter(function(pI){
            return pI.width > 0 && pI.height >0
        }).forEach(function(pI,i,pIs)
        {
            pI.left = pI.left - parseFloat(dlg.extDlg.left.val.text)
            pI.width = pI.width + parseFloat(dlg.extDlg.left.val.text) + parseFloat(dlg.extDlg.right.val.text)
            pI.top = pI.top + parseFloat(dlg.extDlg.top.val.text)
            pI.height = pI.height + parseFloat(dlg.extDlg.top.val.text) + parseFloat(dlg.extDlg.bottom.val.text)
            dlg.extDlg.progress.value = ((i+1)/pIs.length) * 100
            dlg.update()
        })
        dlg.close()
    }
}