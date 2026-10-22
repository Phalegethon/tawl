#!/usr/bin/env python3
"""Rasterize frames from readme-demo.swift; never collects live process data.

Requires Pillow (documentation tooling only) and a monospace font. On macOS,
Menlo is used by default. Pass --font to use another installed monospace font.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import unicodedata

from PIL import Image, ImageDraw, ImageFont

BG = (26, 30, 38)
CHROME = (19, 23, 30)
FG = (230, 235, 242)
MUTED = (155, 167, 183)
ACCENT = (95, 215, 255)
CELL, LINE, PAD, TOP, BOTTOM = 10, 22, 20, 48, 52
SGR = re.compile(r'(\x1b\[[0-9;]*m)')
ANSI16 = [(0,0,0),(205,49,49),(13,188,121),(229,229,16),(36,114,200),(188,63,188),(17,168,205),(229,229,229),
          (102,102,102),(241,76,76),(35,209,139),(245,245,67),(59,142,234),(214,112,214),(41,184,219),(255,255,255)]


def color(n):
    if n >= 232:
        return (8 + (n - 232) * 10,) * 3
    if n >= 16:
        n -= 16
        v = [0, 95, 135, 175, 215, 255]
        return (v[n // 36], v[(n // 6) % 6], v[n % 6])
    return ANSI16[n]


def cells(line):
    fg, bg = FG, BG
    for part in SGR.split(line):
        if part.startswith('\x1b['):
            nums = [int(n or '0') for n in part[2:-1].split(';')]
            i = 0
            while i < len(nums):
                n = nums[i]
                if n in (38, 48) and i + 2 < len(nums) and nums[i+1] == 5:
                    if n == 38: fg = color(nums[i+2])
                    else: bg = color(nums[i+2])
                    i += 3
                elif n in (38, 48) and i + 4 < len(nums) and nums[i+1] == 2:
                    if n == 38: fg = tuple(nums[i+2:i+5])
                    else: bg = tuple(nums[i+2:i+5])
                    i += 5
                else:
                    if n == 0: fg, bg = FG, BG
                    elif n == 39: fg = FG
                    elif n == 49: bg = BG
                    elif 30 <= n <= 37: fg = color(n-30)
                    elif 40 <= n <= 47: bg = color(n-40)
                    elif 90 <= n <= 97: fg = color(n-90+8)
                    elif 100 <= n <= 107: bg = color(n-100+8)
                    i += 1
        else:
            for ch in part:
                w = 0 if unicodedata.combining(ch) else 2 if unicodedata.east_asian_width(ch) in ('W', 'F') else 1
                yield ch, w, fg, bg


def frame_image(frame, width, height, font, label_font, progress):
    im = Image.new('RGB', (width*CELL+PAD*2, height*LINE+TOP+BOTTOM), BG)
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, im.width, TOP-1), fill=CHROME)
    draw.text((PAD, 13), 'tawl  /  terminal walkthrough', font=label_font, fill=FG)
    badge = 'SYNTHETIC DATA'
    draw.text((im.width-PAD-draw.textlength(badge,font=label_font),13),badge,font=label_font,fill=MUTED)
    for row, line in enumerate(frame['lines']):
        x = PAD
        y = TOP + row*LINE
        for ch, w, fg, bg in cells(line):
            if w == 0:
                continue
            draw.rectangle((x,y,x+CELL*w-1,y+LINE-1),fill=bg)
            if '\u2581' <= ch <= '\u2588':
                h = round((ord(ch)-0x2580)*LINE/8)
                draw.rectangle((x,y+LINE-h,x+CELL*w-1,y+LINE-1),fill=fg)
            elif '\u2589' <= ch <= '\u258f':
                cw = round((0x2590-ord(ch))*CELL/8)
                draw.rectangle((x,y,x+cw-1,y+LINE-1),fill=fg)
            else:
                draw.text((x,y+1),ch,font=font,fill=fg)
            x += CELL*w
    footer = TOP + height*LINE
    draw.rectangle((0,footer,im.width,im.height),fill=CHROME)
    draw.rectangle((0,footer,round(im.width*progress),footer+1),fill=ACCENT)
    caption = frame['caption']
    assert draw.textlength(caption, font=label_font) <= im.width-PAD*2, caption
    draw.text((PAD,footer+17),caption,font=label_font,fill=ACCENT)
    return im


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('frames',type=Path)
    p.add_argument('--output',type=Path,default=Path('docs/media'))
    p.add_argument('--font',type=Path,default=Path('/System/Library/Fonts/Menlo.ttc'))
    args = p.parse_args()
    doc = json.loads(args.frames.read_text())
    width,height = doc['width'],doc['height']
    font=ImageFont.truetype(str(args.font),16)
    label_font=ImageFont.truetype(str(args.font),15)
    args.output.mkdir(parents=True,exist_ok=True)
    names={'overview':'tawl-overview','closure':'tawl-process-review'}
    for sequence,name in names.items():
        frames=doc['sequences'][sequence]
        assert len(frames)>1
        assert all(len(f['lines']) == height for f in frames)
        assert all(300<=f['durationMs']<=10000 for f in frames)
        for f in frames:
            assert all(sum(w for _,w,_,_ in cells(line)) <= width for line in f['lines'])
        images=[frame_image(f,width,height,font,label_font,(i+1)/len(frames)) for i,f in enumerate(frames)]
        # One palette across all frames avoids flicker; no dithering keeps text crisp.
        swatches=Image.new('RGB',(images[0].width,images[0].height*len(images)))
        for i,im in enumerate(images): swatches.paste(im,(0,i*im.height))
        palette=swatches.quantize(colors=128,method=Image.Quantize.MEDIANCUT)
        indexed=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in images]
        dest=args.output/f'{name}.gif'
        indexed[0].save(dest,save_all=True,append_images=indexed[1:],duration=[f['durationMs'] for f in frames],loop=0,optimize=True,disposal=1)
        poster=0 if sequence=='overview' else len(frames)-1
        images[poster].save(args.output/f'{name}.png',optimize=True)
        with Image.open(dest) as check:
            assert check.n_frames==len(frames), (dest,check.n_frames,len(frames))
            assert check.info.get('loop')==0
            duration=0
            for i in range(check.n_frames):
                check.seek(i);duration+=check.info['duration']
            assert duration==sum(f['durationMs']//10*10 for f in frames)
        assert dest.stat().st_size<2*1024*1024, 'Keep each README animation below 2 MiB.'
        print(f'{dest}: {len(frames)} frames, {duration/1000:.1f}s, {dest.stat().st_size/1024:.0f} KiB')


if __name__=='__main__':
    main()
