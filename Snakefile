from collections import OrderedDict
import os.path as op
import xmltodict
import flatten_dict

# this is probably correct on Linux. Since we're using op.expanduser, you can
# include a tilde (~) in your path, which we'll expand to your home directory.
INKSCAPE_PREF_FILE = op.expanduser("~/.config/inkscape/preferences.xml")


rule link_bitmap_images:
    input:
        'template.svg',
        'einstein.png',
        'curie.png',
    output:
        'figure.svg',
    run:
        import subprocess
        import shutil
        shutil.copy(input[0], output[0])
        for i, im in enumerate(input[1:]):
            print(f"Copying {im} into IMAGE{i+1}, by calling 'sed -i s|IMAGE{i+1}\"|{im}\"|g {output[0]}'")
            # we add the trailing " to make sure we only replace IMAGE1, not IMAGE10
            subprocess.call(['sed', '-i', f's|IMAGE{i+1}"|{im}"|g', output[0]])


rule embed_bitmaps_into_figure:
    input:
        # marking this as ancient means we don't rerun this step if the
        # preferences file has changed, which is good because it changes
        # everytime we run this step
        ancient(INKSCAPE_PREF_FILE),
        'figure.svg',
    output:
        'figure_dpi-{bitmap_dpi}.svg',
    run:
        import subprocess
        import shutil
        from glob import glob
        shutil.copy(input[1], output[0])
        # set the bitmap dpi to the user-specified values, holding onto
        # whatever value is there before the process is run.
        orig_dpi = write_create_bitmap_resolution(input[0], wildcards.bitmap_dpi)
        # grab the ids of the linked images
        ids = get_image_ids(input[1])
        print(f"Embedding images with ids: {ids}")
        # construct the string that selects these images...
        select_ids = ''.join([f'select-by-id:{id};' for id in ids])
        # embeds them in a new bitmap, then deletes the linked images...
        action_str = select_ids + "SelectionCreateBitmap;select-clear;" + select_ids + "EditDelete;"
        # and saves and quit out of the file
        action_str += "FileSave;FileQuit;"
        print(f"Inkscape action string:\n{action_str}")
        subprocess.call(['inkscape', '-g', f'--actions={action_str}', output[0]])
        # the inkscape call above embeds the bitmaps but also
        # apparently creates a separate png file containing the
        # embedded bitmaps, which we want to remove. commas get
        # replaced with underscores in the paths of those files, so
        # check for those as well
        extra_files = glob(output[0] + '-*') + glob(output[0].replace(',', '_') + '-*')
        print(f"Will remove the following: {extra_files}")
        for f in extra_files:
            try:
                os.remove(f)
            except FileNotFoundError:
                # then the file was removed by something else. this happens if
                # multiple of these processes is run simultaneously, I think.
                continue
        # reset the bitmap dpi to its value before this process was run.
        write_create_bitmap_resolution(input[0], orig_dpi)


rule convert_to_pdf:
    input:
        '{file_name}.svg'
    output:
        '{file_name}.pdf'
    shell:
        "inkscape -o {output} {input}"


def write_create_bitmap_resolution(path, res=300):
    """Write specified create bitmap resolution to inkscape preferences.xml.

    Intended to be used once at the beginning and once at the end, like so:

    ```
    orig_dpi = write_create_bitmap_resolution(path, 300)
    # DO SOME STUFF
    write_create_bitmap_resolution(path, orig_dpi)
    ```

    Thus we don't end up permanently modifying the resolution.

    Parameters
    ----------
    path : str
        path to the inkscape preferences file, probably
        ~/.config/inkscape/preferences.xml
    res : int or str, optional
        Target resolution for create bitmap.

    Returns
    -------
    orig : str
        The original dpi of createbitmap. If none found, returns '64', the
        default.

    """
    with open(op.expanduser(path)) as f:
        doc = xmltodict.parse(f.read())
    opts = [i for i in doc['inkscape']['group'] if 'options' == i['@id']][0]
    create_bm =[i for i in opts['group'] if 'createbitmap' == i['@id']]
    orig = '64'
    if len(create_bm) > 0 and '@resolution' in create_bm[0]:
        orig = create_bm[0]['@resolution']
        create_bm[0]['@resolution'] = str(res)
    elif len(create_bm) > 0:
        create_bm[0]['@resolution'] = str(res)
    else:
        create_bm = OrderedDict({'@id': 'createbitmap', '@resolution': str(res)})
        opts.append(create_bm)
    with open(path, 'w') as f:
        xmltodict.unparse(doc, output=f)
    return orig


def get_image_ids(path):
    """Get inkscape ids of images that are linked (vs embedded).

    We only check the images, and we return the ids of all that contain an
    @xlink:href field which points to an existing file.

    Parameters
    ----------
    path : str
        Path to the svg.

    Returns
    -------
    ids : list
        List of strings containing the ids of these images. These can then be
        used with the inskcape command line, like so: `f'inkscape -g
        --action="select-by-id:{ids[0]};EditDelete;" {path}'`

    """
    # svgs are just xml, so we can read them like any other xml file.
    with open(path) as f:
        doc = xmltodict.parse(f.read())
    # we can have a strange hierarchy in the svg, depending on how we've
    # grouped images. this avoids all that by flattening it out...
    flattened_svg = flatten_dict.flatten(doc['svg']['g'], enumerate_types=(list, ))
    # then we grab the xlink:href field for each image
    images = {k: v for k, v in flattened_svg.items() if 'image' in k
              and '@xlink:href' in k}
    # and grab only the ids of those images whose xlink:href exists
    ids = [flattened_svg[(*k[:-1], '@id')] for k, v in images.items()
           if op.exists(v)]
    return ids
