# Third-party notices

This project re-implements, in its own C code, one formula that follows
another open-source project. No source file of that project is included.

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
