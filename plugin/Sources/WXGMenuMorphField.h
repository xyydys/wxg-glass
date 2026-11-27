#ifndef WXG_MENU_MORPH_FIELD_H
#define WXG_MENU_MORPH_FIELD_H

#include <math.h>
#include <stdbool.h>

/* Scalar port of RoundedField.kt and GlassGaussianField.kt from
   xyydys/expo-glass-custom-menu at 0021efd8ab0d068f155bbdac62c5f673ccc39a24.
   Copyright (c) 2015-present 650 Industries, Inc.
   Licensed under the MIT License. See LICENSES/ExpoGlassCustomMenu-MIT.txt. */

typedef struct {
    float x, y, width, height, radius;
} WXGMenuMorphFieldBox;

typedef struct {
    float centerX, centerY, halfWidth, halfHeight, radius;
    float expandedRadius, baseRadius, curvatureX, curvatureY;
    bool circular;
} WXGMenuMorphFieldShape;

typedef struct {
    float distance, dx, dy;
} WXGMenuMorphFieldSample;

enum { WXGMenuMorphFieldSide = 70, WXGMenuMorphFieldKernel = 16 };

typedef struct {
    float x, y, step;
    int width, height;
    float values[WXGMenuMorphFieldSide * WXGMenuMorphFieldSide];
    float opticalX[WXGMenuMorphFieldSide * WXGMenuMorphFieldSide];
    float opticalY[WXGMenuMorphFieldSide * WXGMenuMorphFieldSide];
    WXGMenuMorphFieldShape incoming, outgoing;
    float centerX, centerY, axisX, axisY, smoothing;
    bool hasOutgoing, gaussian;
} WXGMenuMorphField;

static inline float WXGMenuMorphUnit(float value) {
    return fminf(1.0f, fmaxf(0.0f, value));
}

static inline WXGMenuMorphFieldShape WXGMenuMorphFieldShapeForBox(WXGMenuMorphFieldBox box) {
    WXGMenuMorphFieldShape shape = {
        .centerX = box.x + box.width * 0.5f,
        .centerY = box.y + box.height * 0.5f,
        .halfWidth = box.width * 0.5f,
        .halfHeight = box.height * 0.5f,
        .radius = fmaxf(box.radius, 0.01f)
    };
    shape.expandedRadius = shape.radius * 1.5286649465560913f;
    shape.curvatureX = WXGMenuMorphUnit(2.8915570351735034f - 1.4457785175867517f * box.width / shape.expandedRadius);
    shape.curvatureY = WXGMenuMorphUnit(2.8915570351735034f - 1.4457785175867517f * box.height / shape.expandedRadius);
    shape.baseRadius = shape.radius * (1.5286649465560913f - 0.5286649465560913f * fmaxf(shape.curvatureX, shape.curvatureY));
    shape.circular = shape.curvatureX == 1.0f && shape.curvatureY == 1.0f;
    return shape;
}

static inline WXGMenuMorphFieldSample WXGMenuMorphFieldAt(WXGMenuMorphFieldShape shape, float x, float y) {
    float localX = x - shape.centerX;
    float localY = y - shape.centerY;
    float edgeX = fabsf(localX) - shape.halfWidth;
    float edgeY = fabsf(localY) - shape.halfHeight;
    float circleX = edgeX + shape.baseRadius;
    float circleY = edgeY + shape.baseRadius;
    float interior = fminf(fmaxf(circleX, circleY), 0.0f);
    float dx = fmaxf(circleX, 0.0f), dy = fmaxf(circleY, 0.0f);
    float cornerLength = sqrtf(dx * dx + dy * dy);
    float distance = interior + cornerLength - shape.radius;
    if (!shape.circular) {
        float ux = (edgeX + shape.expandedRadius) / shape.expandedRadius;
        float uy = (edgeY + shape.expandedRadius) / shape.expandedRadius;
        float zx = fmaxf(ux, 0.0f), zy = fmaxf(uy, 0.0f);
        float largest = fmaxf(zx, zy);
        float t = largest > 0.0f ? fminf(zx, zy) / largest : 0.0f;
        float length = sqrtf(zx * zx + zy * zy);
        float polynomial = ((((-0.926054f * t + 3.15601f) * t - 3.64122f) * t + 1.26803f) * t + 0.268531f) * t * t;
        float continuous = length + 1.0f - 1.0f / (1.0f - polynomial * fminf(length, 1.0f));
        float ax = fmaxf(1.5286649465560913f * ux - 0.5286649465560913f, 0.0f);
        float ay = fmaxf(1.5286649465560913f * uy - 0.5286649465560913f, 0.0f);
        float alternate = 0.3458344340324402f + 0.6541655659675598f * sqrtf(ax * ax + ay * ay);
        float weight = WXGMenuMorphUnit((zx < zy ? 1.0f : -1.0f) * (t - 1.0f) + 0.5f);
        float curvature = shape.curvatureX + (shape.curvatureY - shape.curvatureX) * weight;
        distance = interior + shape.expandedRadius * (continuous - 1.0f + (alternate - continuous) * curvature);
    }

    if (cornerLength > 0.000001f) {
        dx /= cornerLength;
        dy /= cornerLength;
    } else {
        dx = circleX > circleY;
        dy = 1.0f - dx;
    }
    if (localX < 0.0f) dx = -dx;
    if (localY < 0.0f) dy = -dy;
    float ovalY = localY * shape.halfWidth / fmaxf(shape.halfHeight, 0.000001f);
    float ovalLength = sqrtf(localX * localX + ovalY * ovalY);
    if (ovalLength > 0.000001f) {
        dx += localX / ovalLength;
        dy += ovalY / ovalLength;
    }
    float length = sqrtf(dx * dx + dy * dy);
    float inv = length > 0.000001f ? 1.0f / length : 0.0f;
    return (WXGMenuMorphFieldSample){distance, dx * inv, dy * inv};
}

static inline float WXGMenuMorphFieldUnion(WXGMenuMorphFieldSample menu, WXGMenuMorphFieldSample source, float smoothing) {
    if (fabsf(menu.distance - source.distance) >= smoothing) return fminf(menu.distance, source.distance);
    float radius = smoothing * WXGMenuMorphUnit(0.5f - 0.5f * (menu.dx * source.dx + menu.dy * source.dy));
    if (radius <= 0.000001f) return fminf(menu.distance, source.distance);
    float weight = WXGMenuMorphUnit(0.5f + 0.5f * (menu.distance - source.distance) / radius);
    return menu.distance + (source.distance - menu.distance) * weight - radius * weight * (1.0f - weight);
}

// RoundedField.kt's optical normal is a blend of the corner and oval
// normals. Differentiating the rasterized mask gives a different ray, and
// changes it discontinuously whenever a pixel crosses a grid cell.
static inline WXGMenuMorphFieldSample WXGMenuMorphOpticalAnalytic(const WXGMenuMorphField *f,float x,float y) {
    WXGMenuMorphFieldSample a=WXGMenuMorphFieldAt(f->incoming,(x-f->centerX)*f->axisX,(y-f->centerY)*f->axisY);
    a.dx*=f->axisX; a.dy*=f->axisY;
    if(!f->hasOutgoing)return a;
    WXGMenuMorphFieldSample b=WXGMenuMorphFieldAt(f->outgoing,x,y);
    if(f->smoothing<=.000001f)return a.distance<b.distance?a:b;
    if(fabsf(a.distance-b.distance)>=f->smoothing)return a.distance<=b.distance?a:b;
    float k=f->smoothing*WXGMenuMorphUnit(.5f-.5f*(a.dx*b.dx+a.dy*b.dy));
    if(k<=.000001f)return a.distance<=b.distance?a:b;
    float t=WXGMenuMorphUnit(.5f+.5f*(a.distance-b.distance)/k);
    return (WXGMenuMorphFieldSample){a.distance+(b.distance-a.distance)*t-k*t*(1.f-t),
        a.dx+(b.dx-a.dx)*t,a.dy+(b.dy-a.dy)*t};
}

static inline void WXGMenuMorphFieldTranslate(WXGMenuMorphField *f,float x,float y) {
    f->x+=x; f->y+=y;
    f->centerX+=x; f->centerY+=y;
    f->outgoing.centerX+=x; f->outgoing.centerY+=y;
}

typedef enum {
    WXGMorphFieldGeometry,       // the established silhouette grid and Gaussian cutoff
    WXGMorphFieldOptics,         // optical field for standalone callers
    WXGMorphFieldSessionTexture  // Expo's locked root-window lattice and RGBA16F
} WXGMorphFieldSampling;

static inline int WXGMenuMorphKernel(float localSigma,WXGMorphFieldSampling mode,float weights[WXGMenuMorphFieldKernel+1]) {
    (void)mode;
    int radius=localSigma<.000001f?0:
        (int)fminf(ceilf(localSigma*4.f),WXGMenuMorphFieldKernel);
    float sum=weights[0]=1.f;
    for(int i=1;i<=radius;i++){
        weights[i]=expf(-i*i/(2.f*localSigma*localSigma));sum+=2.f*weights[i];
    }
    while(radius>0 && weights[radius]/sum<.002f)--radius;
    sum=1.f;for(int i=1;i<=radius;i++)sum+=2.f*weights[i];
    for(int i=0;i<=radius;i++)weights[i]/=sum;
    return radius;
}
static inline float WXGMorphFieldHalf(float value) {
#if defined(__FLT16_MANT_DIG__) || defined(__ARM_FP16_FORMAT_IEEE)
    return (float)(_Float16)value;
#else
    return value;
#endif
}

// Sample the same anisotropic coordinates, SDF units and Gaussian grid as the
// ink shader. Keep only the part of the grid that can contain the zero contour.
static inline void WXGMenuMorphFieldBuildMode(WXGMenuMorphField *field, WXGMenuMorphFieldBox menu,
        float radiusY,WXGMenuMorphFieldBox source,float smoothing,float gridStep,WXGMorphFieldSampling mode) {
    float sigma = fmaxf(0.0f, smoothing);
    float ratio=fmaxf(menu.radius,radiusY)/fmaxf(.01f,fminf(menu.radius,radiusY));
    float grow=fminf(source.width,source.height)>=.01f?sigma*.25f*ratio:0.f;
    float left = fminf(menu.x, source.x) - grow;
    float top = fminf(menu.y, source.y) - grow;
    float right = fmaxf(menu.x + menu.width, source.x + source.width) + grow;
    float bottom = fmaxf(menu.y + menu.height, source.y + source.height) + grow;
    float step = fmaxf(gridStep, fmaxf(right - left, bottom - top) / 64.0f);
    field->step = step;
    field->x = floorf(left / step) * step - step;
    field->y = floorf(top / step) * step - step;
    int width = (int)ceilf((right - field->x) / step) + 2;
    int height = (int)ceilf((bottom - field->y) / step) + 2;
    field->width = width;
    field->height = height;

    float localSigma = sigma / step;
    float weights[WXGMenuMorphFieldKernel+1];
    int radius=WXGMenuMorphKernel(localSigma,mode,weights);

    float rx = fmaxf(menu.radius, .001f), ry = fmaxf(radiusY, .001f);
    float radiusMin = fminf(rx, ry), scaleX = radiusMin/rx, scaleY = radiusMin/ry;
    float cx = menu.x+menu.width*.5f, cy = menu.y+menu.height*.5f;
    WXGMenuMorphFieldBox local = {-menu.width*scaleX*.5f, -menu.height*scaleY*.5f,
                                  menu.width*scaleX, menu.height*scaleY, radiusMin};
    field->incoming=WXGMenuMorphFieldShapeForBox(local);
    field->outgoing=WXGMenuMorphFieldShapeForBox(source);
    field->centerX=cx; field->centerY=cy;
    field->axisX=scaleX; field->axisY=scaleY; field->smoothing=sigma;
    field->hasOutgoing=fminf(source.width,source.height)>=.01f;
    bool vectors=mode!=WXGMorphFieldGeometry;
    field->gaussian=radius>0 && vectors;
    // The scalar mask and its zero contour own the glass and rim.
    // The Gaussian branch also filters the two *optical* gradient channels.
    // Skip the temporary convolution workspace for analytic/settled frames.
    if(!radius) {
        for(int row=0;row<height;row++)for(int col=0;col<width;col++)
            field->values[row*width+col]=WXGMenuMorphOpticalAnalytic(field,field->x+col*step,field->y+row*step).distance;
        return;
    }

    WXGMenuMorphFieldSample horizontal[(WXGMenuMorphFieldSide + 2 * WXGMenuMorphFieldKernel) * WXGMenuMorphFieldSide];
    int paddedHeight = height + 2 * radius;
    for (int row = 0; row < paddedHeight; row++) {
        float y = field->y + (row - radius) * step;
        WXGMenuMorphFieldSample raw[WXGMenuMorphFieldSide + 2 * WXGMenuMorphFieldKernel];
        for (int column = 0; column < width + 2 * radius; column++)
            raw[column]=WXGMenuMorphOpticalAnalytic(field,field->x+(column-radius)*step,y);
        for (int column = 0; column < width; column++) {
            int center = column + radius;
            WXGMenuMorphFieldSample a=raw[center];
            a.distance*=weights[0]; a.dx*=weights[0]; a.dy*=weights[0];
            for(int i=1;i<=radius;i++) {
                WXGMenuMorphFieldSample l=raw[center-i],r=raw[center+i];
                a.distance+=(l.distance+r.distance)*weights[i];
                if(vectors){a.dx+=(l.dx+r.dx)*weights[i]; a.dy+=(l.dy+r.dy)*weights[i];}
            }
            horizontal[row*width+column]=a;
        }
    }
    for (int row=0;row<height;row++)for(int column=0;column<width;column++) {
        int center=(row+radius)*width+column, dst=row*width+column;
        WXGMenuMorphFieldSample a=horizontal[center];
        a.distance*=weights[0]; a.dx*=weights[0]; a.dy*=weights[0];
        for(int i=1;i<=radius;i++) {
            WXGMenuMorphFieldSample t=horizontal[center-i*width],b=horizontal[center+i*width];
            a.distance+=(t.distance+b.distance)*weights[i];
            if(vectors){a.dx+=(t.dx+b.dx)*weights[i]; a.dy+=(t.dy+b.dy)*weights[i];}
        }
        field->values[dst]=a.distance;
        if(vectors){
            float len=hypotf(a.dx,a.dy),inv=len>.000001f?1.f/len:0.f;
            float dx=a.dx*inv,dy=a.dy*inv;
            if(mode==WXGMorphFieldSessionTexture){
                field->values[dst]=WXGMorphFieldHalf(a.distance);dx=WXGMorphFieldHalf(dx);dy=WXGMorphFieldHalf(dy);
            }
            field->opticalX[dst]=dx;field->opticalY[dst]=dy;
        }
    }
}

static inline void WXGMenuMorphFieldBuild(WXGMenuMorphField *field,WXGMenuMorphFieldBox menu,float radiusY,
        WXGMenuMorphFieldBox source,float smoothing,float gridStep) {
    WXGMenuMorphFieldBuildMode(field,menu,radiusY,source,smoothing,gridStep,WXGMorphFieldOptics);
}

// Build using absolute window coordinates before snapping the Gaussian grid.
// Return the field to the surface's local coordinate space afterwards. A
// settled menu (zero smoothing) is analytic and never needs a texture.
static inline void WXGMenuMorphBuildSessionField(WXGMenuMorphField *out,const WXGMenuMorphField *shape,
        float originX,float originY,float step) {
    WXGMenuMorphFieldShape a=shape->incoming,b=shape->outgoing;
    float hw=a.halfWidth/shape->axisX,hh=a.halfHeight/shape->axisY;
    WXGMenuMorphFieldBox menu={shape->centerX-hw+originX,shape->centerY-hh+originY,2*hw,2*hh,a.radius/shape->axisX};
    WXGMenuMorphFieldBox source={b.centerX-b.halfWidth+originX,b.centerY-b.halfHeight+originY,
        2*b.halfWidth,2*b.halfHeight,b.radius};
    WXGMenuMorphFieldBuildMode(out,menu,a.radius/shape->axisY,source,shape->smoothing,step,WXGMorphFieldSessionTexture);
    WXGMenuMorphFieldTranslate(out,-originX,-originY);
}

// The reference samples the Gaussian distance/gradient texture with a cubic
// B-spline, keeping the vector continuous across four-pixel mesh/grid cells.
static inline void WXGMorphCubicWeights(float t,float w[4]) {
    float t2=t*t,t3=t2*t,s=1.f-t;
    w[0]=s*s*s/6.f;w[1]=(4.f-6.f*t2+3.f*t3)/6.f;
    w[2]=(1.f+3.f*t+3.f*t2-3.f*t3)/6.f;w[3]=t3/6.f;
}
static inline WXGMenuMorphFieldSample WXGMenuMorphOpticalRead(const WXGMenuMorphField *f,float x,float y) {
    if(!f->gaussian)return WXGMenuMorphOpticalAnalytic(f,x,y);
    float u=(x-f->x)/f->step,v=(y-f->y)/f->step;
    if(u<1.f || v<1.f || u>f->width-2.f || v>f->height-2.f)
        return WXGMenuMorphOpticalAnalytic(f,x,y);
    int ix=(int)u,iy=(int)v;float wx[4],wy[4];
    WXGMorphCubicWeights(u-ix,wx);WXGMorphCubicWeights(v-iy,wy);
    WXGMenuMorphFieldSample s={0};
    for(int j=0;j<4;j++)for(int i=0;i<4;i++){
        int xx=ix+i-1<f->width?ix+i-1:f->width-1, yy=iy+j-1<f->height?iy+j-1:f->height-1;
        int k=yy*f->width+xx;float q=wx[i]*wy[j];
        s.distance+=q*f->values[k];s.dx+=q*f->opticalX[k];s.dy+=q*f->opticalY[k];
    }
    return s;
}

// Sample a fine contour grid directly from the cubic B-spline of the session
// Gaussian field so CAShapeLayer masks/rims match the Metal & mesh zero-contour
// without hitting the 16-tap kernel cutoff on fine cell spacings.
static inline void WXGMenuMorphFieldSampleSession(WXGMenuMorphField *field,WXGMenuMorphFieldBox menu,
        float radiusY,WXGMenuMorphFieldBox source,float smoothing,float gridStep,
        const WXGMenuMorphField *session) {
    float sigma=fmaxf(0.0f,smoothing);
    float ratio=fmaxf(menu.radius,radiusY)/fmaxf(.01f,fminf(menu.radius,radiusY));
    bool hasSource=fminf(source.width,source.height)>=.01f;
    float grow=hasSource?sigma*.25f*ratio:0.f;
    float left=(hasSource?fminf(menu.x,source.x):menu.x)-grow;
    float top=(hasSource?fminf(menu.y,source.y):menu.y)-grow;
    float right=(hasSource?fmaxf(menu.x+menu.width,source.x+source.width):menu.x+menu.width)+grow;
    float bottom=(hasSource?fmaxf(menu.y+menu.height,source.y+source.height):menu.y+menu.height)+grow;
    float step=fmaxf(gridStep,fmaxf(right-left,bottom-top)/64.0f);
    field->step=step;
    field->x=floorf(left/step)*step-step;
    field->y=floorf(top/step)*step-step;
    int width=(int)ceilf((right-field->x)/step)+2;
    int height=(int)ceilf((bottom-field->y)/step)+2;
    field->width=width;
    field->height=height;
    float rx=fmaxf(menu.radius,.001f),ry=fmaxf(radiusY,.001f);
    float radiusMin=fminf(rx,ry),scaleX=radiusMin/rx,scaleY=radiusMin/ry;
    float cx=menu.x+menu.width*.5f,cy=menu.y+menu.height*.5f;
    WXGMenuMorphFieldBox local={-menu.width*scaleX*.5f,-menu.height*scaleY*.5f,
                                menu.width*scaleX,menu.height*scaleY,radiusMin};
    field->incoming=WXGMenuMorphFieldShapeForBox(local);
    field->outgoing=WXGMenuMorphFieldShapeForBox(source);
    field->centerX=cx; field->centerY=cy;
    field->axisX=scaleX; field->axisY=scaleY; field->smoothing=sigma;
    field->hasOutgoing=hasSource;
    field->gaussian=false;
    for(int row=0;row<height;row++) {
        float py=field->y+row*step;
        for(int col=0;col<width;col++)
            field->values[row*width+col]=WXGMenuMorphOpticalRead(session,field->x+col*step,py).distance;
    }
}

// The physical inward depth and outward normal of the interpolated field.
static inline WXGMenuMorphFieldSample WXGMenuMorphFieldRead(const WXGMenuMorphField *f, float x, float y) {
    float u=fminf(fmaxf((x-f->x)/f->step,0.f),f->width-1.001f);
    float v=fminf(fmaxf((y-f->y)/f->step,0.f),f->height-1.001f);
    int i=(int)u,j=(int)v;
    u-=i; v-=j;
    const float *p=f->values+j*f->width+i;
    float a=p[0], b=p[1], c=p[f->width], d=p[f->width+1];
    float dx=((1.f-v)*(b-a)+v*(d-c))/f->step,dy=((1.f-u)*(c-a)+u*(d-b))/f->step;
    float length=fmaxf(hypotf(dx,dy),.001f);
    return (WXGMenuMorphFieldSample){((1.f-v)*(a+u*(b-a))+v*(c+u*(d-c)))/length,dx/length,dy/length};
}

typedef enum {
    WXGMenuMorphContourMove,
    WXGMenuMorphContourLine,
    WXGMenuMorphContourClose
} WXGMenuMorphContourAction;

typedef void (*WXGMenuMorphContourVisitor)(WXGMenuMorphContourAction action, float x, float y, void *context);

/* Marching squares. Each traversed edge is flagged on both visits so rings
   are closed individually, including when the two lobes have separated. */
static inline unsigned WXGMenuMorphContourCell(const WXGMenuMorphField *field, int x, int y, float corners[4]) {
    int offset = y * field->width + x;
    corners[0] = field->values[offset];
    corners[1] = field->values[offset + 1];
    corners[2] = field->values[offset + field->width + 1];
    corners[3] = field->values[offset + field->width];
    unsigned mask = 0;
    for (int e = 0; e < 4; e++) if ((corners[e] < 0.0f) != (corners[(e + 1) & 3] < 0.0f)) mask |= 1u << e;
    return mask;
}

static inline void WXGMenuMorphFieldTrace(const WXGMenuMorphField *field, WXGMenuMorphContourVisitor visitor, void *context) {
    const int cellWidth = field->width - 1, cellHeight = field->height - 1;
    const int dx[4] = {0, 1, 0, -1}, dy[4] = {-1, 0, 1, 0};
    const int cornerX[4] = {0, 1, 1, 0}, cornerY[4] = {0, 0, 1, 1};
    unsigned char visited[WXGMenuMorphFieldSide * WXGMenuMorphFieldSide] = {0};
    for (int rows = 0; rows < cellHeight; rows++) {
        for (int columns = 0; columns < cellWidth; columns++) {
            float corners[4];
            unsigned startMask = WXGMenuMorphContourCell(field, columns, rows, corners);
            int startIndex = rows * cellWidth + columns;
            while (startMask & ~visited[startIndex]) {
                unsigned start = __builtin_ctz(startMask & ~visited[startIndex]);
                int x = columns, y = rows;
                unsigned edge = start;
                WXGMenuMorphContourAction action = WXGMenuMorphContourMove;
                do {
                    int offset = y * cellWidth + x;
                    unsigned mask = WXGMenuMorphContourCell(field, x, y, corners);
                    unsigned next = (edge + 1u) & 3u;
                    float fraction = corners[edge] / (corners[edge] - corners[next]);
                    float sampleX = x + cornerX[edge] + fraction * (cornerX[next] - cornerX[edge]);
                    float sampleY = y + cornerY[edge] + fraction * (cornerY[next] - cornerY[edge]);
                    visitor(action, field->x + field->step * sampleX, field->y + field->step * sampleY, context);
                    action = WXGMenuMorphContourLine;

                    unsigned exit;
                    if (mask == 15) {
                        // Separate the two connections by testing the bilinear saddle.
                        bool firstConnected = corners[0] * corners[2] >= corners[1] * corners[3];
                        exit = edge ^ (firstConnected ? 1u : 3u);
                    } else {
                        exit = __builtin_ctz(mask & ~(1u << edge));
                    }
                    visited[offset] |= (1u << edge) | (1u << exit);
                    x += dx[exit];
                    y += dy[exit];
                    edge = exit ^ 2u;
                } while (x >= 0 && x < cellWidth && y >= 0 && y < cellHeight && !(visited[y * cellWidth + x] & (1u << edge)));
                visitor(WXGMenuMorphContourClose, 0.0f, 0.0f, context);
            }
        }
    }
}

#endif
