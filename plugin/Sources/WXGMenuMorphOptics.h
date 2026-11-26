#ifndef WXG_MENU_MORPH_OPTICS_H
#define WXG_MENU_MORPH_OPTICS_H

#include "WXGMenuMorphField.h"
#include "WXGLensCurve.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Tessellate the *sampling map*. A flat centre or straight edge needs few
// quads; the folded rim of a 20 pt band can change several texels per point.
// Test error in source points, including both directions of the colour split.
typedef struct {float x,y,offsetX,offsetY,splitX,splitY;} WXGMorphOpticalVertex;
typedef struct {unsigned index[4];} WXGMorphOpticalFace;
typedef struct {int x,y,w,h;} WXGMorphOpticalCell;
typedef struct {
    unsigned epoch,vertex;
    float distance;
    WXGMorphOpticalVertex ray;
} WXGMorphOpticalNode;

typedef struct {
    WXGMorphOpticalNode *nodes;
    WXGMorphOpticalVertex *vertices;
    WXGMorphOpticalFace *faces;
    WXGMorphOpticalCell *leaves;
    size_t nodeCapacity,vertexCapacity,faceCapacity,leafCapacity;
    unsigned epoch,vertexCount,faceCount,leafCount;
    int nx,ny;
    WXGMenuMorphFieldBox box;
    float stepX,stepY,band,amount,squeeze,dispersion;
    const WXGMenuMorphField *field;
} WXGMorphOpticalMesh;

static inline void WXGMorphOpticalFree(WXGMorphOpticalMesh *mesh) {
    free(mesh->nodes); free(mesh->vertices); free(mesh->faces); free(mesh->leaves);
    memset(mesh,0,sizeof(*mesh));
}

static inline bool WXGMorphOpticalReserve(void **buf,size_t *capacity,size_t needed,size_t size,bool zeroNew) {
    if(needed<=*capacity)return true;
    size_t next=needed+needed/3+16;
    void *grown=realloc(*buf,next*size);
    if(!grown)return false;
    if(zeroNew)memset((char *)grown+*capacity*size,0,(next-*capacity)*size);
    *capacity=next; *buf=grown;
    return true;
}
static inline WXGMorphOpticalVertex WXGMorphOpticalRay(const WXGMorphOpticalMesh *m,float x,float y,float *distance) {
    WXGMenuMorphFieldSample f=WXGMenuMorphOpticalRead(m->field,m->box.x+x,m->box.y+y);
    float shift=WXGLensCurveOffsetCapped(-f.distance,m->band,m->amount,m->squeeze);
    float a=-f.dx*shift,b=-f.dy*shift;
    float colour=m->dispersion*(2*x/m->box.width-1)*(2*y/m->box.height-1);
    if(distance)*distance=f.distance;
    return (WXGMorphOpticalVertex){x,y,a,b,a*colour,b*colour};
}
static inline WXGMorphOpticalNode *WXGMorphOpticalNodeAt(WXGMorphOpticalMesh *m,int x,int y) {
    WXGMorphOpticalNode *n=&m->nodes[y*(m->nx+1)+x];
    if(n->epoch!=m->epoch){
        n->ray=WXGMorphOpticalRay(m,m->stepX*x,m->stepY*y,&n->distance);
        n->epoch=m->epoch;n->vertex=0;
    }
    return n;
}
static inline unsigned WXGMorphOpticalAdd(WXGMorphOpticalMesh *m,WXGMorphOpticalVertex ray) {
    if(!WXGMorphOpticalReserve((void **)&m->vertices,&m->vertexCapacity,m->vertexCount+1,sizeof(ray),false))return 0;
    m->vertices[m->vertexCount++]=ray;
    return m->vertexCount; // 1-based: zero marks non-corners and allocation failure.
}
static inline unsigned WXGMorphOpticalCorner(WXGMorphOpticalMesh *m,int x,int y) {
    WXGMorphOpticalNode *n=WXGMorphOpticalNodeAt(m,x,y);
    if(!n->vertex)n->vertex=WXGMorphOpticalAdd(m,n->ray);
    return n->vertex;
}
static inline bool WXGMorphOpticalFaceAdd(WXGMorphOpticalMesh *m,unsigned a,unsigned b,unsigned c,unsigned d) {
    if(!a || !b || !c || !d || !WXGMorphOpticalReserve((void **)&m->faces,&m->faceCapacity,m->faceCount+1,sizeof(*m->faces),false))return false;
    m->faces[m->faceCount++]=(WXGMorphOpticalFace){{a-1,b-1,c-1,d-1}};
    return true;
}
// Compare the actual centre ray against both possible CA tessellation
// diagonals, and against the linear ray on each shared edge.
static inline bool WXGMorphOpticalNonlinear(WXGMorphOpticalNode *a,WXGMorphOpticalNode *b,WXGMorphOpticalNode *mid) {
    float ex=mid->ray.offsetX-.5f*(a->ray.offsetX+b->ray.offsetX);
    float ey=mid->ray.offsetY-.5f*(a->ray.offsetY+b->ray.offsetY);
    float sx=mid->ray.splitX-.5f*(a->ray.splitX+b->ray.splitX);
    float sy=mid->ray.splitY-.5f*(a->ray.splitY+b->ray.splitY);
    float dx=fabsf(ex)+.667f*fabsf(sx),dy=fabsf(ey)+.667f*fabsf(sy);
    return dx*dx+dy*dy>.15f*.15f;
}
static inline unsigned WXGMorphOpticalSplits(WXGMorphOpticalMesh *m,int x,int y,int w,int h) {
    int mx=x+w/2,my=y+h/2;
    WXGMorphOpticalNode *mid=WXGMorphOpticalNodeAt(m,mx,my);
    float reach=(m->stepX*w+m->stepY*h);
    if(mid->distance>reach || mid->distance < -m->band-reach)return 0;
    WXGMorphOpticalNode *a=WXGMorphOpticalNodeAt(m,x,y),*b=WXGMorphOpticalNodeAt(m,x+w,y);
    WXGMorphOpticalNode *c=WXGMorphOpticalNodeAt(m,x+w,y+h),*d=WXGMorphOpticalNodeAt(m,x,y+h);
    WXGMorphOpticalNode *top=WXGMorphOpticalNodeAt(m,mx,y),*bottom=WXGMorphOpticalNodeAt(m,mx,y+h);
    WXGMorphOpticalNode *left=WXGMorphOpticalNodeAt(m,x,my),*right=WXGMorphOpticalNodeAt(m,x+w,my);
    bool splitX=w>1 && (WXGMorphOpticalNonlinear(a,b,top) || WXGMorphOpticalNonlinear(d,c,bottom) || WXGMorphOpticalNonlinear(left,right,mid));
    bool splitY=h>1 && (WXGMorphOpticalNonlinear(a,d,left) || WXGMorphOpticalNonlinear(b,c,right) || WXGMorphOpticalNonlinear(top,bottom,mid));
    if(w>1 && h>1 && !splitX && !splitY && (WXGMorphOpticalNonlinear(a,c,mid) || WXGMorphOpticalNonlinear(b,d,mid)))
        return w*m->stepX>=h*m->stepY?1:2;
    return splitX+2*splitY;
}
static inline bool WXGMorphOpticalSubdivide(WXGMorphOpticalMesh *m,int x,int y,int w,int h) {
    unsigned split=w+h>2?WXGMorphOpticalSplits(m,x,y,w,h):0;
    if(split){
        int sw=split&1?w/2:w,sh=split&2?h/2:h;
        for(int row=y;row<y+h;row+=sh)for(int col=x;col<x+w;col+=sw)
            if(!WXGMorphOpticalSubdivide(m,col,row,sw,sh))return false;
        return true;
    }
    if(!WXGMorphOpticalCorner(m,x,y) || !WXGMorphOpticalCorner(m,x+w,y) ||
       !WXGMorphOpticalCorner(m,x+w,y+h) || !WXGMorphOpticalCorner(m,x,y+h))return false;
    if(!WXGMorphOpticalReserve((void **)&m->leaves,&m->leafCapacity,m->leafCount+1,sizeof(*m->leaves),false))return false;
    m->leaves[m->leafCount++]=(WXGMorphOpticalCell){x,y,w,h};
    return true;
}
static inline WXGMorphOpticalVertex WXGMorphOpticalMix(WXGMorphOpticalVertex a,WXGMorphOpticalVertex b,float t) {
    WXGMorphOpticalVertex v={a.x+(b.x-a.x)*t,a.y+(b.y-a.y)*t,
        a.offsetX+(b.offsetX-a.offsetX)*t,a.offsetY+(b.offsetY-a.offsetY)*t,
        a.splitX+(b.splitX-a.splitX)*t,a.splitY+(b.splitY-a.splitY)*t};
    return v;
}
enum {WXGMorphOpticalSubdivision=32};
static inline unsigned WXGMorphOpticalMarked(const WXGMorphOpticalMesh *m,int x,int y) {
    const WXGMorphOpticalNode *n=&m->nodes[y*(m->nx+1)+x];
    return n->epoch==m->epoch?n->vertex:0;
}
static inline unsigned WXGMorphOpticalEdgePoint(WXGMorphOpticalMesh *m,int x,int y,int dx,int dy) {
    unsigned id=WXGMorphOpticalMarked(m,x,y);
    if(id)return id;
    int lo=1,hi=1;
    while(!WXGMorphOpticalMarked(m,x-dx*lo,y-dy*lo))++lo;
    while(!WXGMorphOpticalMarked(m,x+dx*hi,y+dy*hi))++hi;
    unsigned a=WXGMorphOpticalMarked(m,x-dx*lo,y-dy*lo),b=WXGMorphOpticalMarked(m,x+dx*hi,y+dy*hi);
    WXGMorphOpticalVertex ray=WXGMorphOpticalMix(m->vertices[a-1],m->vertices[b-1],(float)lo/(lo+hi));
    ray.x=x*m->stepX;ray.y=y*m->stepY;
    return WXGMorphOpticalAdd(m,ray);
}
// Join every neighbouring boundary vertex with nondegenerate quads. An
// extra knot on the opposite side keeps exactly the linear source UV of
// that side (including its dispersion), so no T-junction breaks a glyph.
static inline bool WXGMorphOpticalTile(WXGMorphOpticalMesh *m,WXGMorphOpticalCell c) {
    int xs[WXGMorphOpticalSubdivision+1],ys[WXGMorphOpticalSubdivision+1],nx=0,ny=0;
    for(int x=c.x;x<=c.x+c.w;x++)
        if(WXGMorphOpticalMarked(m,x,c.y) || WXGMorphOpticalMarked(m,x,c.y+c.h))xs[nx++]=x;
    for(int y=c.y;y<=c.y+c.h;y++)
        if(WXGMorphOpticalMarked(m,c.x,y) || WXGMorphOpticalMarked(m,c.x+c.w,y))ys[ny++]=y;
    if(nx==2 && ny==2)
        return WXGMorphOpticalFaceAdd(m,WXGMorphOpticalMarked(m,xs[0],ys[0]),WXGMorphOpticalMarked(m,xs[1],ys[0]),
            WXGMorphOpticalMarked(m,xs[1],ys[1]),WXGMorphOpticalMarked(m,xs[0],ys[1]));
    unsigned rows[2][WXGMorphOpticalSubdivision+1];
    for(int j=0;j<ny;j++){
        unsigned *cur=rows[j%2],*prev=rows[(j+1)%2];
        for(int i=0;i<nx;i++){
            int x=xs[i],y=ys[j];
            if(j==0 || j+1==ny)cur[i]=WXGMorphOpticalEdgePoint(m,x,y,1,0);
            else if(i==0 || i+1==nx)cur[i]=WXGMorphOpticalEdgePoint(m,x,y,0,1);
            else cur[i]=WXGMorphOpticalAdd(m,WXGMorphOpticalNodeAt(m,x,y)->ray);
            if(!cur[i] || (i && j && !WXGMorphOpticalFaceAdd(m,prev[i-1],prev[i],cur[i],cur[i-1])))return false;
        }
    }
    return true;
}
static inline bool WXGMorphOpticalBuild(WXGMorphOpticalMesh *m,const WXGMenuMorphField *f,
                                        WXGMenuMorphFieldBox box,float band,float amount,float squeeze,float dispersion) {
    if(!(box.width>0 && box.height>0 && band>0 && amount>0))return false;
    // At most 512x512 cached sample sites for an exceptionally large panel.
    // The typical 225x164 panel uses a ~0.65 pt finest cell at the folded edge.
    int cols=(int)fminf(16.f,ceilf(box.width/22.f)),rows=(int)fminf(16.f,ceilf(box.height/22.f));
    m->nx=cols*WXGMorphOpticalSubdivision; m->ny=rows*WXGMorphOpticalSubdivision;
    if(!WXGMorphOpticalReserve((void **)&m->nodes,&m->nodeCapacity,(size_t)(m->nx+1)*(m->ny+1),sizeof(*m->nodes),true))return false;
    if(!++m->epoch){memset(m->nodes,0,m->nodeCapacity*sizeof(*m->nodes));m->epoch=1;}
    m->field=f;m->box=box;m->stepX=box.width/m->nx;m->stepY=box.height/m->ny;
    m->band=band;m->amount=amount;m->squeeze=squeeze;m->dispersion=dispersion;
    m->leafCount=m->faceCount=m->vertexCount=0;
    for(int y=0;y<m->ny;y+=WXGMorphOpticalSubdivision)for(int x=0;x<m->nx;x+=WXGMorphOpticalSubdivision)
        if(!WXGMorphOpticalSubdivide(m,x,y,WXGMorphOpticalSubdivision,WXGMorphOpticalSubdivision))return false;
    for(unsigned i=0;i<m->leafCount;i++)if(!WXGMorphOpticalTile(m,m->leaves[i]))return false;
    return true;
}
#endif
