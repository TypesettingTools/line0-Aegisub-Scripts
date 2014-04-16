var sel = app.activeDocument.selection;
for (var i=0; i<sel.length; i++) {
	if(sel[i].typename == "CompoundPathItem") {
		pathItems = sel[i].pathItems;
		for(var j=0; j<pathItems.length; j++)  {
			if (removeUnpaintedPath(pathItems[j])) {j--}
		}
	} else { removeUnpaintedPath(sel[i]); }
}


function removeUnpaintedPath(pathItem)
{
		if(pathItem.typename == "PathItem" && !(pathItem.filled || pathItem.stroked))
		{
			pathItem.remove();
			return true;
		}
		else return false;
}