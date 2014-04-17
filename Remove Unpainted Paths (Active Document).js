var sel = app.activeDocument.pageItems;
for (var i=0; i<sel.length; i++) {
	if (processPageItem(sel[i])) {i--}
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

function recurseGroup(groupItem)
{
	for(var i=0; i<groupItem.pageItems.length; i++) {
		if(processPageItem(groupItem.pageItems[i])) {i--}
	}
	if (groupItem) return false else return true; 
}


function recurseCompound(compoundPathItem)
{
	for(var i=0; i<compoundPathItem.pathItems.length; i++) {
		if(processPageItem(compoundPathItem.pathItems[i])) {i--}
	}
	if (compoundPathItem) return false else return true; 
}

function processPageItem(pageItem)
{
	if(pageItem.typename == "CompoundPathItem") {
		return recurseCompound(pageItem);
	}
	else if(pageItem.typename == "GroupItem") {
		return recurseGroup(pageItem);
	} else {
		 return removeUnpaintedPath(pageItem); 
	}
}