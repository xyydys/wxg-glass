#ifndef WXG_DOCK_PRESENTATION_H
#define WXG_DOCK_PRESENTATION_H

typedef enum { WXGDockHidden, WXGDockReturning, WXGDockSettled } WXGDockPresentation;

/* The frontmost dock is visible only on a tab root or while returning to it.
   Pushes and chat/settings transitions never expose it. UIKit owns progress. */
static inline WXGDockPresentation WXGDockPresentationForState(int available,int rootVisible,int transitioning,int toRoot) {
    if(!available)return WXGDockHidden;
    if(transitioning)return toRoot?WXGDockReturning:WXGDockHidden;
    return rootVisible?WXGDockSettled:WXGDockHidden;
}
static inline WXGDockPresentation WXGDockPresentationAfterTransition(int available,int fromRoot,int toRoot,int cancelled) {
    return WXGDockPresentationForState(available,cancelled?fromRoot:toRoot,0,0);
}
#endif
