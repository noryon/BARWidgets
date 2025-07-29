# BARLayoutPlanner

<p align="center">
  <img src="images/gui.png" width="400" alt="GUI">
</p>

This widget presents an interface that allows players to **draw, save, load and markup layouts** directly in-game.


### DISCLAIMERS
It's not a lightweight widget (by widget standards); if your computer struggles with performance — especially memory — this widget might cause some stutters; even if you have plenty of memory, this widget can reach the memory treshold allowed by Spring Engine, which force garbage collection at 1.2GB, specially while using big layouts. I don't know if the memory is shared between all widgets or just one, but either way, you've been warned.

> ⚠️ This widget **might use file reading and writing** from your computer for saving/loading layouts.  
> Please inspect the code and use the widget at your own risk. The Spring Engine (as far as I know) **does not allow a widget to access files outside the widget directory** for obvious security reasons. Performance wise, disk will be used only when a file is writen or read. If you're still suspicious, don't use this widget.  
> This was made with **AI assistance**, if you think this is unholy, don't use this widget.

### HOW TO USE THIS WIDGET:
To draw a layout check the "Enable Layout Draw" option. It will enable drawing layout mode. While ON, you can paint the layout using the mouse, placing building-sized units with [LMB] and place lines with [RMB]

There are help texts and option inside the widget itself.

To draw your layout, first click on "Enable Layout Draw". You will see a square at your mouse position; it is a preview of where you will draw to the layout. The small dot is where a line will begin.
Use [left mouse button] to place buildings, use [ALT] or [ALT + CTRL] keys to change the way it is placed.
Use [right mouse button] to render arbitrary lines to your layout; hold the [ALT] key so you can remove lines.
Select one size for the building (Small, Square, Big, Large or Chunk) to place. Adjacent buildings of the same size will be rendered together (i.e.: a single contour for the shape defined by buildings of the same type).
You can use CTRL+Z/CTRL+A to undo/redo your actions.
Once the layout is created, save it on a slot using a Save button below, you can load it anytime later pressing the Load button with same slot number.
A loaded layout can be rotated with the [R] key and inverted with the [I] key before being placed.
Press "Render" to draw the active layout to the game.
You can click and drag the widget window by the title bar.


IF YOUR ARE NEW:
    Draw your layout alligned to chunks. The size of a chunk is a multiple of almost every building in the game! You can optimize your layout space based on this.
    Use the "Snap" option! Its the best way to render regular layouts, which will be alligned to the grid.

Check and use the widget discord page if you have any trouble with this widget.

##### Draw the layout! Save it in one of the four slots.


  ![Drawing](https://github.com/noryon/BARLayoutPlanner/blob/main/images/drawing_layout-output.gif)

##### Load the layout to place it elsewhere. You can rotate and invert the layout orientation!.

  ![Loading](https://github.com/noryon/BARLayoutPlanner/blob/main/images/loading_layout-output.gif)
  
--

### TIPS
- **Disable the option "Auto erase map marks"** on your Settings -> Interface, so that the lines do not disappear during the game.
- **Test solo:** Load your map alone to experiment and save your layouts; load and use them in actual matches afterward.

### HOW TO INSTALL A WIDGET?
It is very simple, you just need a folder named Widgets inside your game folder, as such:

```[...]\Beyond-All-Reason\data\LuaUI\Widgets``` (one fast way to reach the root folder is to just click with the right mouse button on you game desktop icon and go "Open folder", then you create the LuaUI and Widget folder if needed.)

Once you have the widget folder you just copy the .lua files of the widgets you want to install.
In game you can enable/disable them by name on the widget menu (press [F11] inside a game)

### OUTRO
- I used a rendering line marks technique that I saw in another widget made by Lu5ck, which split longer lines and set them to a queue to be rendered during multiple frames, this avoid long lines and drawings limit per frame. Thank you. :)
