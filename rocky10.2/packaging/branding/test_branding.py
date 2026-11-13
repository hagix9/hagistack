#!/usr/bin/python3
"""Tests for make-branding.py and the images it made. Run: python3 -I test_branding.py

The committed images in ../files/python-django-horizon/ must be exactly what
the generator writes, the SVGs must hold nothing but shapes (no script, no
link, no external or embedded resource), and the bitmaps must be well-formed
icons of the sizes Horizon links to.
"""
import importlib.util
import os
import re
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
FILES = os.path.join(HERE, '..', 'files', 'python-django-horizon')
SVGS = ('hagistack-logo.svg', 'hagistack-logo-splash.svg', 'hagistack-safari-pinned-tab.svg',
        'hagistack-material-brand.svg')
NAMES = SVGS + ('hagistack-favicon.ico', 'hagistack-apple-touch-icon.png')
SVG_NS = '{http://www.w3.org/2000/svg}'
ALLOWED_TAGS = {'svg', 'title', 'g', 'rect', 'path', 'circle'}
ALLOWED_ATTRS = {'xmlns', 'viewBox', 'width', 'height', 'role', 'aria-label', 'x', 'y', 'rx',
                 'fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin',
                 'transform', 'd', 'cx', 'cy', 'r'}


def load_generator():
    spec = importlib.util.spec_from_file_location('make_branding', os.path.join(HERE, 'make-branding.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def png_chunks(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    i, out = 8, []
    while i < len(data):
        n, = struct.unpack('>I', data[i:i + 4])
        t = data[i + 4:i + 8]
        body = data[i + 8:i + 8 + n]
        crc, = struct.unpack('>I', data[i + 8 + n:i + 12 + n])
        assert zlib.crc32(t + body) & 0xffffffff == crc, 'bad CRC'
        out.append((t, body))
        i += 12 + n
    return out


def png_content(data):
    """Every chunk with IDAT decoded: what the image is, whatever zlib wrote."""
    out = []
    for t, body in png_chunks(data):
        out.append((t, zlib.decompress(body) if t == b'IDAT' else body))
    return out


def bitmap_content(data):
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return png_content(data)
    count, = struct.unpack('<H', data[4:6])
    out = []
    for k in range(count):
        w, h, c, r, planes, bpp, size, off = struct.unpack('<BBBBHHII', data[6 + 16 * k:22 + 16 * k])
        out.append(((w, h, c, r, planes, bpp), png_content(data[off:off + size])))
    return out


class Branding(unittest.TestCase):
    def test_committed_images_are_the_generator_output(self):
        # SVGs byte for byte. Bitmaps by content: the deflate stream may differ
        # between zlib builds (EL10 uses zlib-ng), the decoded pixels may not.
        gen = load_generator()
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(gen.main(['make-branding.py', d]), 0)
            for n in NAMES:
                with self.subTest(n=n), open(os.path.join(d, n), 'rb') as a, open(os.path.join(FILES, n), 'rb') as b:
                    new, old = a.read(), b.read()
                    if n.endswith('.svg'):
                        self.assertEqual(new, old, 'regenerate with make-branding.py')
                    else:
                        self.assertEqual(bitmap_content(new), bitmap_content(old), 'regenerate with make-branding.py')

    def test_svgs_hold_only_shapes(self):
        for n in SVGS:
            raw = open(os.path.join(FILES, n), 'rb').read()
            text = raw.decode('utf-8')
            with self.subTest(n=n):
                self.assertNotRegex(text.lower(), r'<script|javascript:|<image|<foreignobject|<use|<style|'
                                    r'href|url\(|@import|<!entity|<!doctype|\bon[a-z]+\s*=')
                # the only URL is the SVG namespace
                self.assertEqual(re.findall(r'https?://[^"\s]+', text), ['http://www.w3.org/2000/svg'])
                root = ET.fromstring(raw)
                for el in root.iter():
                    tag = el.tag.replace(SVG_NS, '')
                    self.assertIn(tag, ALLOWED_TAGS)
                    for k in el.attrib:
                        self.assertIn(k, ALLOWED_ATTRS, f'{tag} {k}')
                self.assertEqual(root.find(SVG_NS + 'title').text, 'Hagistack')
                allowed = ('#000000',) if 'pinned' in n else ('#3E6FE0', '#F0A830', 'none')
                for col in re.findall(r'(?:fill|stroke)="([^"]+)"', text):
                    self.assertIn(col, allowed)
        # included inline in HTML by the material theme: no XML declaration
        inline = open(os.path.join(FILES, 'hagistack-material-brand.svg')).read()
        self.assertTrue(inline.startswith('<svg '))
        # and no fixed size: the theme's CSS sets the height (M1 of the audit)
        self.assertNotRegex(inline.split('>', 1)[0], r'\s(width|height)=')

    def test_bitmaps_are_well_formed(self):
        ico = open(os.path.join(FILES, 'hagistack-favicon.ico'), 'rb').read()
        reserved, kind, count = struct.unpack('<HHH', ico[:6])
        self.assertEqual((reserved, kind, count), (0, 1, 3))
        sizes = []
        for k in range(count):
            w, h, _, _, planes, bpp, size, off = struct.unpack('<BBBBHHII', ico[6 + 16 * k:22 + 16 * k])
            chunks = png_chunks(ico[off:off + size])
            iw, ih = struct.unpack('>II', chunks[0][1][:8])
            self.assertEqual((iw, ih), (w, h))
            self.assertEqual(chunks[-1][0], b'IEND')
            sizes.append(w)
        self.assertEqual(sizes, [16, 32, 48])
        touch = png_chunks(open(os.path.join(FILES, 'hagistack-apple-touch-icon.png'), 'rb').read())
        self.assertEqual(struct.unpack('>II', touch[0][1][:8]), (180, 180))
        self.assertEqual({t for t, _ in touch}, {b'IHDR', b'tEXt', b'IDAT', b'IEND'})


if __name__ == '__main__':
    unittest.main()
