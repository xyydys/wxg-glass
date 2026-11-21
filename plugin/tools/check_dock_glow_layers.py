#!/usr/bin/env python3
"""Check the runtime layer wiring used by Tests/DockGlowSceneTests.c."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('plugin', nargs='?', type=Path, default=Path(__file__).resolve().parents[1])
sources = parser.parse_args().plugin / 'Sources'
bar = (sources / 'WXGDemoBar.m').read_text()
glass = (sources / 'WXGGlassView.m').read_text()


def between(source, start, end):
    if start not in source:
        raise SystemExit('Missing runtime path: ' + start)
    return source.split(start, 1)[1].split(end, 1)[0]


def require(section, *entries):
    for entry in entries:
        if entry not in section:
            raise SystemExit('Missing layer wiring: ' + entry)


def forbid(section, entry):
    if entry in section:
        raise SystemExit('Late screen-space glow would light both clear strips: ' + entry)


forbid(bar, '[self addSubview:_glowHost]')
press = between(bar, '- (void)glowDownAt:', '- (BOOL)beginTrackingWithTouch:')
require(press, '[_glass attachDockMaterialGlow:_glow]', '[_fallback.contentView addSubview:_glow]')
attach = between(glass, '- (BOOL)attachDockMaterialGlow:', '- (void)setLensRect:')
require(attach, 'glow.frame=_bodyClip.bounds', '[_bodyClip addSubview:glow]')
require(glass, 'for(UIView *clip in @[_bodyClip,_lensClip])', '[self addSubview:clip]',
        '[self insertSubview:_bodyRim belowSubview:_lensClip]', '[self insertSubview:_body26 aboveSubview:_bodyRim]',
        '[self insertSubview:_lens26 belowSubview:_lensRim]', '[_lensClip insertSubview:v belowSubview:_lensMetal]',
        '[view configureSpectralGroup:_lensGroup', 'matrix.m[18]=1.f', 'tapIndex>0?WXGMakePlusLighter():nil')
require(bar, '[self insertSubview:_travelView aboveSubview:_glass]', '_glass.lensSeesBar?nil:_glass.backdropGroupName',
        '@"wxg.travel.%p"', '[self applyTravelGroup:[self travelGroup]]', '[_travelLens insertSublayer:layer atIndex:depth++]',
        '[_glass.layer removeAnimationForKey:@"wxg.travelScale"]')
require(glass, 'if(seesBar && barHeight>2 && barHeight<padded.height)', 'o.shrinkPress=(float)press;',
        'channel>1?WXGMakePlusLighter():nil')
light = between(bar, '@implementation WXGDockGlowView', '@interface WXGDemoBar ()')
require(light, '_spot.position=point', '_spot.opacity=_spotLevel', '_bar.opacity=_barLevel', 'a.duration=.10',
        'b.duration=.15', 'out=.45', '_spot.opacity=0;_bar.opacity=0', 'WXG_DOCK26_GLOW_GROW')
print('PASS: body-owned light, native/CA lens capture order and alpha, rim order and touch/release timing.')
