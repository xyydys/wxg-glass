#!/usr/bin/env python3
"""FIX113: rebuild Sources/WXGTelegramTabIcons.h from Telegram's tab animations.

The four Lottie files come from Telegram for iOS (GPLv2):
  github.com/TelegramMessenger/Telegram-iOS
  submodules/TelegramUI/Resources/Animations/{TabChats,TabContacts,TabCalls,TabSettings}.json
They are rendered frame by frame with rlottie (github.com/Samsung/rlottie, built
locally) by this small C program, at 512 x 512, alpha only:

  #include <rlottie_capi.h> ... for each frame: lottie_animation_render(a,f,buf,512,512,2048);
  write (buf[i] >> 24) for every pixel to <out>_NNN.raw

Usage: telegram_tab_icons.py <dir with TabChats_000.raw ...> <output header>
All four are cropped to one square of the canvas (87..425: the union of every
frame of all four, 95..414 x 105..405, with 8 px around it, so no frame touches
the edge), scaled to 96 x 96 and stacked into one grey PNG each.
Needs Pillow."""
import glob, io, sys
from PIL import Image
S, HALF, C, N = 512, 169, 256, 96   # FIX113 C: 8 px of the 512 canvas around the union (95..414 x 105..405)
NAMES = ['TabChats', 'TabContacts', 'TabCalls', 'TabSettings']

def main(raw, header):
    box = (C - HALF, C - HALF, C + HALF, C + HALF)
    lines = ['// Generated (FIX113): Telegram for iOS tab bar animations (GPLv2), see tools/telegram_tab_icons.py.',
             '#ifndef WXG_TELEGRAM_TAB_ICONS_H', '#define WXG_TELEGRAM_TAB_ICONS_H',
             'static const unsigned int WXGTelegramFrameSide=%d;' % N]
    for name in NAMES:
        files = sorted(glob.glob('%s/%s_*.raw' % (raw, name)))
        sheet = Image.new('L', (N, N * len(files)), 0)
        for k, f in enumerate(files):
            frame = Image.frombytes('L', (S, S), open(f, 'rb').read()).crop(box).resize((N, N), Image.LANCZOS)
            sheet.paste(frame, (0, k * N))
        buffer = io.BytesIO(); sheet.save(buffer, 'PNG', optimize=True); data = buffer.getvalue()
        lines += ['static const unsigned int WXG%sFrames=%d;' % (name, len(files)),
                  'static const unsigned int WXG%sLength=%d;' % (name, len(data)),
                  'static const unsigned char WXG%sPNG[]={' % name]
        numbers = [str(x) for x in data]
        for i in range(0, len(numbers), 40):
            lines.append(','.join(numbers[i:i + 40]) + (',' if i + 40 < len(numbers) else ''))
        lines.append('};')
    lines.append('#endif')
    open(header, 'w').write('\n'.join(lines) + '\n')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(__doc__); sys.exit(2)
    main(sys.argv[1], sys.argv[2])
