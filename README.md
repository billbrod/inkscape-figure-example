# Inkscape figure example

Example of how to script figure creation with inkscape and python.

Generally, when creating figures, I use [matplotlib](https://matplotlib.org/)
and [seaborn](https://seaborn.pydata.org/) to create and save plots as svgs (an
open standard for vector graphics) and combine them, possibly with some, using
[svgutils](https://svgutils.readthedocs.io/en/latest/). However, for one of my
[research projects](https://github.com/billbrod/foveated-metamers/) occasionally
I want to include .png images in my figures. These are raster graphics and so
suddenly I have to worry about the resolution of the images included in my
figure, because I want them to be visible and not alias. For smaller images, I
might simply down-sample them until they have the appropriate resolution, but
for large images, this won't do. 

A standard way to handle this problem is to use a vector graphics editing
program, such as inkscape or Adobe Illustrator, and link the images, then, when
the figure is finished, export it to a pdf and set the dpi then. This works, but
I try to script as much of my workflow as possible, especially while writing a
paper, when I might go through many different versions of a figure while trying
to find the right one. So I managed to come up with the following solution,
in which:

1. The user creates a template svg file in inkscape, which defines where the
   different images will go (as well as any additional image content, such as
   text or shapes). This template has dummy paths, (`IMAGE1`, `IMAGE2`, etc)
   which will be replaced with the png images.
2. sed replaces those dummy paths with the path to the actual image.
3. inkscape embeds those png files in the svg with a user-specified dpi.
4. inkscape converts that svg to a pdf.

Snakemake is used to manage everything after step 1.

# Requirements

- Python 3, with following packages, all of which can be installed via `pip`:
    - [Snakemake](https://snakemake.readthedocs.io/en/stable/), a python-based
      workflow manager.
    - [flatten-dict](https://github.com/ianlini/flatten-dict), for easily
      flattening nested dictionaries.
    - [xmltodict](https://github.com/martinblech/xmltodict), for parsing xml and
      svg files.
- [Inkscape](https://inkscape.org/), an open source vector graphics editor.
- [sed](https://www.gnu.org/software/sed/), "stream editor", a non-interactive command-line text editor (this is probably already installed on your system if it's Mac or Linux).


# Usage

This example repo already includes the `template.svg` and png files to embed,
`curie.png` and `einstein.png`. Our template also inlcudes an already-embedded
png file (a patch of white noise), as well as text and shapes. You can open this
up with inkscape to see what it looks like; you'll notice four "Linked image not
found" boxes of different sizes (you can also open up the file with your
browser, but at least for me, those boxes are just not rendered).

Before running anything, we need to know where your inkscape preferences file
is. If you open inkscape and go to `Edit -> Preferences -> System`, you can see
the `User preferences` field underneath the `System info` section. Copy this
path and paste it `INKSCAPE_PREF_FILE` at the top of the `Snakefile`.

To embed the image, we just use snakemake: `snakemake -n -prk figure_dpi-10.pdf
figure.pdf`. This is a dry-run (because of the `-n` flag), so you can see what
steps will be run. Here, we're creating two versions of the pdf file: one with
the png files embedded at 10 dpi, one with them embedded at their full dpi. To
run, simply replace the `-n` with `-j 1`, which tells snakemake to run only one
process at a time.

At the end of this, you'll have two pdf files, as well as several intermediate
svgs. You can use `du -hs ./*pdf` to see that the `dpi-10` version is much
smaller, and you can see why when you open the files up to view -- 10 dpi is
really low! The use of 10 dpi is just for example purposes, it's way too low to
actually use for anything. Simply change the number in the path (e.g.,
`figure_dpi-300.pdf`) to change it.

# Understanding what's going on

All the code can be found in `Snakefile`, which contains two python functions
and three snakemake rules. All are commented and documented, so you're
encouraged to read through them, but you should only need to understand the
snakemake rules:

- `link_bitmap_images`: use `sed` to replace our dummy paths (`"IMAGE1"`, etc)
  with the paths to the png files.
- `embed_bitmaps_into_images`: find the ids of the linked images (taking
  advantage of the fact that svgs are just a special type of xml file), then use
  `inkscape`'s scripting ability to embed them all at the specified dpi.
- `convert_to_pdf`: convert an svg to a pdf. This is so simple it probably
  doesn't need to be a rule, but this way we can script the whole process.
  
# Using this trick yourself

If you'd like to use this trick for your own work, here's a handful of things
you might like to do:

- Rearrange things in the template: simply edit this file in inkscape, moving
  them around as you see fit. Add any amount of additional svg elements you'd
  like (including embedding other raster images directly); they won't interfere
  with this process.
- Link and embed other images using this process: copy one of the existing
  linked images, right click on it and select image properties. In the pane that
  opened up, set the `URL` to `IMAGE3` (or whatever the next sequential image
  is). Then, in the `Snakefile`, go to the `link_bitmap_images` rule and add the
  path to the image you'd like embedded after `'curie.png'` in the `input:`
  section.
    - Similarly, if you'd like to replace one of the existing images, just
      change the path in the `input:` section of that rule.
    - Make sure the aspect of your placeholder matches what you want for your
      embedded image. As you can see in the example, the embedded image will be
      stretched to match the placeholder.
- Create a new template: just open up inkscape and create a new svg with some
  placeholders! I do this by linking the image I want to embed, then resizing it
  to my desired size (starting from the image I want makes it easier to keep
  the aspect consistent). Then, as above, change the `URL` to `IMAGE1`.
    - I've sometimes been unable to set the `URL` to an invalid one like this.
      If that's the case for you, save your template svg and open it with a text
      editor. Find your image (I recommend searching by its path), and edit the
      `xlink:href` field to `"IMAGE1"` (note the quotes!).
- Change the output dpi: when running the snakemake rule to create the figure,
  simply change the number after `dpi-` in its path.
- Combine with plots: if you want to combine the figure created here with plots
  created by matplotlib or other python plotting libraries, I recommend saving
  those as svg files and then using
  [svgutils](https://svgutils.readthedocs.io/en/latest/) to combine the two. I
  would insert a rule after `link_bitmap_images` and before
  `embed_bitmaps_into_images` which combines the two svgs before embedding the
  bitmaps. `svgutils` will not display the linked image, so to make developing
  this easier, I'd recommend creating a rectangle with black stroke and empty
  fill of the same size as your placeholder, and place it in the same location;
  that way, you'll know where the placeholder is. You can also use `svgutils` to
  programmatically add text, though I'm pretty sure `svgutils` assumes there are
  always 90 pixels per inch, so you'll need to take that into account when
  figuring out sizes.
- Note: I'd save the svg as a "Plain svg" rather than an "Inkscape svg" (in the
  dropdown menu, when you go to save), since this strips out some unnecessary
  tags from the svg file, which makes it easier to go through if you edit the
  svg as a text file.
- Note: When creating your template, I think its helpful to set the display
  units to go to `File -> Document Properties` and set the `Display units:` to
  `px`, and then, under `Scale`, set both the x and y values to `1.0`. This
  makes it easier to ensure your sizes are consistent when editing your image in
  multiple programs (e.g., with both `inkscape` and the python `svgutils`
  library). 
