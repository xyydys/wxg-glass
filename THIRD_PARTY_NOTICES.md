# Third-party notices

This file records the origin and license of third-party material in wxg-glass.

## Backdrop (Liquid Glass for Compose Multiplatform), by Kyant

- Project: "Liquid Glass (Backdrop)", `io.github.kyant0:backdrop`
  (the AndroidLiquidGlass repository).
- Licence: Apache License, Version 2.0
  (<https://www.apache.org/licenses/LICENSE-2.0>).
- What follows it here: in `plugin/Sources/WXGLensCurve.h`, the colour split
  of the refraction (the intensity `x * y` over the half sides, and the three
  channel weights `+3/7`, `+2/21`, `-2/3`, the means of seven samples along
  the spectrum) and the quarter-circle form of the shift it scales. Both
  were written again in C for a Core Animation mesh; the cap on the
  outermost ring, the mesh and everything around them are this project's own.
- The shift's curve itself (its band and depth) was afterwards measured on
  iOS 26's own glass and is used with those measured values.

The Apache License 2.0 allows use, modification and distribution, also
commercially, provided its notices are kept: this file is that notice. A copy
of the licence is at the address above.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

## Uploaded Gemini optics patch

The user-supplied patch ports Kyant's Backdrop lens equations and seven-sample
spectral weights into WXGKyantOptics.h and WXGGlass.metal. Upstream reference:
https://github.com/Kyant0/AndroidLiquidGlass, commit eb4a0ea2e17542ea28c2e71088f7dd9acf77aad5.
Copyright 2025 Kyant. Apache License 2.0. Full license in LICENSES/.
The compiler/integration fixes and local-test shader selection are documented
in README_R4_原底栏透镜接入.md. The R4 integration is rebased on original FIX135, keeps its inner-bar mapping and adds lens-only native spectral sampling and matching glyph rays.

## Expo Glass Custom Menu

The home menu's glass morph ports the Android module's spring motion,
two-lobe outline, and refraction equations from
[xyydys/expo-glass-custom-menu](https://github.com/xyydys/expo-glass-custom-menu/tree/0021efd8ab0d068f155bbdac62c5f673ccc39a24/modules/glass-menu-android).

> The MIT License (MIT)
>
> Copyright (c) 2015-present 650 Industries, Inc. (aka Expo)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## MixBubble

The message bubble adapter follows the native cell coverage, single-line radius
reference, translated content geometry, voice transcription layout updates,
quote background and divider behavior,
and long-message identity rules in
[xyydys/MixBubble 2.9.4.6](https://github.com/xyydys/mixbubble/tree/6c4a4152536e8a383654deee2c04f81ea27dfd20).
