// FIX103 · 测试版 ABC（联网解锁）
// Which WeChat accounts may use the plugin is no longer in the build: the
// unlock server's list decides (wxg-glass worker.js, ALLOWLIST), and the glass
// shader comes from it (WXGUnlock.m). Each entry there is the account's
// licence code SHA-256("WXGLiquidGlass.license.v1:" + wxid), not the wxid;
// `python3 tools/license_hash.py <wxid>` prints the line to add, and the
// settings page of an unlisted account shows (and copies) its code.
// Testers A, B, C: a7a5fc72…, e7b744a4…, 037fb7b4… (all three on the server).
#define WXG_BUILD_LABEL @"测试版 ABC"
// The unlock server(s), tried in order (a failure moves on to the next): a
// custom domain on the same Worker can be put first. Kept as C string
// literal(s) so Arkari's -irobf-cse string encryption hides them in the dylib
// (Objective-C @"..." literals are NOT covered by that pass); WXGEndpoints()
// builds the NSString array from these at runtime. Add more, comma-separated:
//   #define WXG_UNLOCK_ENDPOINTS_C "https://a/v1/unlock", "https://b/v1/unlock"
#define WXG_UNLOCK_ENDPOINTS_C "https://xyylwc.kvgdth56kf.workers.dev/v1/unlock"
// The server's ECDSA P-256 public key, uncompressed 04||X||Y; its private key
// is the Worker's SIGN_PRIV secret. A GET on the server shows its key ("pub").
#define WXG_UNLOCK_PUBLIC_KEY "0473a7b661b9de7c97a538b8360584d0b1207815ebf48ddede0703ac03da8f722817c2944c0a8222d81daaeed2dbfd0dc4ec0bb4b07c810e2dc2745ab1736942d0"
// Settings modules not shown in this build (their values still apply),
// e.g. @[@"refraction"]. Empty: every module, 折射强度和色散 included, is open
// for all three accounts (FIX60 B hid the refraction module; this build doesn't).
#define WXG_HIDDEN_MODULES @[]
// This build's defaults, used for a fresh install (and the glass parameters by
// 恢复默认): an object of WXGConfig keys, or (FIX84) a settings export
// {"config":…,"integration":…,"ui":…}. `python3 tools/bake_defaults.py
// <exported settings or diagnostics JSON>` writes it. Empty: the built-in defaults.
#define WXG_DEFAULT_OPTICS_JSON \
    "{\"config\":{\"alwaysShow\":true,\"barBorderWidth\":1.2352,\"barGrowth\":1.035671,\"blur\":0.143794,\"blurC" \
    "overage\":67.675415,\"bodyPinch\":0.131029,\"borderHex\":\"#FFFFFFFF\",\"borderOpacity\":0.405681,\"bubble" \
    "Blur\":0.758854,\"bubbleBlurCoverage\":100,\"bubbleBorderWidth\":1.2352,\"bubbleDarkBorderWidth\":0.969" \
    "1,\"bubbleDarkRim27Angle\":90.07341,\"bubbleDarkRim27EndLevel\":0.145603,\"bubbleDarkRim27Falloff\":2." \
    "97582,\"bubbleDarkRim27Hex\":\"#000000FF\",\"bubbleDarkRim27Opacity\":1,\"bubbleDarkRim27Sharpness\":3.6" \
    "64598,\"bubbleDarkRim27Width\":0.982074,\"bubbleDarkRimBrightness\":0.8572,\"bubbleDarkRimFade\":1,\"bu" \
    "bbleDarkRimHex\":\"#C2C2C2FF\",\"bubbleDarkRimOpacity\":0.1361,\"bubbleDarkRimSampleBrightness\":0.8572" \
    ",\"bubbleDarkRimSampleFade\":1,\"bubbleDarkRimSampleOpacity\":0.1361,\"bubbleDarkRimSampleWidth\":0.96" \
    "91,\"bubbleDispersion\":4.966304,\"bubbleEdgeFade\":8,\"bubbleEdgeFadeEnabled\":false,\"bubbleEdgeWidth" \
    "\":5.727864,\"bubbleFullGlass\":true,\"bubbleIncomingHex\":\"#FFFFFF8C\",\"bubbleOutgoingHex\":\"#95EC6900" \
    "\",\"bubbleRefraction\":10.198232,\"bubbleRim27Angle\":0,\"bubbleRim27EndLevel\":0.097029,\"bubbleRim27F" \
    "alloff\":2.15903,\"bubbleRim27Hex\":\"#FFFFFFFF\",\"bubbleRim27Opacity\":0.701041,\"bubbleRim27Sharpness" \
    "\":2,\"bubbleRim27Width\":2.063489,\"bubbleRimBrightness\":1.0008,\"bubbleRimFade\":0.7095,\"bubbleRimHe" \
    "x\":\"#FFFFFFFF\",\"bubbleRimOpacity\":0.5057,\"bubbleRimSampleBrightness\":1.0008,\"bubbleRimSampleFade" \
    "\":0.7095,\"bubbleRimSampleOpacity\":0.5057,\"bubbleRimSampleWidth\":1.2352,\"bubbleRimStyle\":2,\"calib" \
    "ration\":false,\"calmMaterial\":0,\"calmMaterialOpacity\":0.521594,\"calmRange\":0.043843,\"calmThreshol" \
    "d\":0.223235,\"captureBudget\":80,\"captureFPS\":120,\"clearMaterial\":false,\"darkBarBorderWidth\":0.969" \
    "1,\"darkBubbleIncomingHex\":\"#2C2C2C2D\",\"darkBubbleOutgoingHex\":\"#95EC69CC\",\"darkCalmMaterialOpaci" \
    "ty\":0.82,\"darkLensBorderWidth\":0.6892,\"darkLensRimHex\":\"#D6D6D6FF\",\"darkLensRimOpacity\":0.2696,\"" \
    "darkMaterialHex\":\"#222222FF\",\"darkMaterialOpacity\":0.48241,\"darkRim27Angle\":89.883339,\"darkRim27" \
    "EndLevel\":0.195352,\"darkRim27Falloff\":3.921966,\"darkRim27Hex\":\"#000000FF\",\"darkRim27Opacity\":1,\"" \
    "darkRim27Sharpness\":5.221556,\"darkRim27Width\":1.951969,\"darkRimBrightness\":0.8572,\"darkRimFade\":" \
    "1,\"darkRimFadeBottomRight\":0,\"darkRimFadeTopLeft\":0,\"darkRimGain\":0.162379,\"darkRimHex\":\"#C2C2C2" \
    "FF\",\"darkRimInnerFade\":1.5,\"darkRimInnerShadowHex\":\"#000000FF\",\"darkRimInnerShadowOpacity\":0.22," \
    "\"darkRimInnerShadowRadius\":0.8711,\"darkRimOpacity\":0.1361,\"darkRimOuterFade\":0.3,\"darkRimSampleB" \
    "lur\":10,\"darkRimSampleBrightness\":0.8572,\"darkRimSampleContrast\":0.5,\"darkRimSampleFade\":1,\"dark" \
    "RimSampleGain\":2.5,\"darkRimSampleLift\":0.6,\"darkRimSampleOpacity\":0.1361,\"darkRimSampleSaturatio" \
    "n\":1.5931,\"darkRimSampleWidth\":0.9691,\"darkRimSideDarken\":false,\"darkRimSideLevel\":0.5595,\"darkS" \
    "electionHex\":\"#5C5C5C80\",\"dispersion\":1.942017,\"dockBlur\":1.088315,\"dockBlurCoverage\":71.650589," \
    "\"dockBorderWidth\":0.9871,\"dockCalmMaterialOpacity\":0.82,\"dockDarkBorderWidth\":1.0093,\"dockDarkCa" \
    "lmMaterialOpacity\":0.82,\"dockDarkMaterialHex\":\"#222222FF\",\"dockDarkMaterialOpacity\":0.748249,\"do" \
    "ckDarkRim27Angle\":0,\"dockDarkRim27EndLevel\":0.15,\"dockDarkRim27Falloff\":3.874029,\"dockDarkRim27H" \
    "ex\":\"#FFFFFFFF\",\"dockDarkRim27Opacity\":1,\"dockDarkRim27Sharpness\":5.761001,\"dockDarkRim27Width\":" \
    "2.042268,\"dockDarkRimBrightness\":0.5456,\"dockDarkRimFade\":0,\"dockDarkRimHex\":\"#FFFFFFFF\",\"dockDa" \
    "rkRimOpacity\":0.228,\"dockDarkRimSampleBrightness\":0.5456,\"dockDarkRimSampleFade\":0,\"dockDarkRimS" \
    "ampleOpacity\":0.228,\"dockDarkRimSampleWidth\":1.0093,\"dockDispersion\":2.216506,\"dockEdgeWidth\":9." \
    "528286,\"dockEndStretch\":true,\"dockEndStretchDistance\":18,\"dockIconOffset\":-0.582347,\"dockIconTit" \
    "leGap\":3.620297,\"dockMaterialEdgeFade\":3.540837,\"dockMaterialEdgeFadeEnabled\":false,\"dockMateria" \
    "lFadeWidth\":0,\"dockMaterialHex\":\"#F9F9F9FF\",\"dockMaterialOpacity\":0.637901,\"dockRefraction\":10.0" \
    "71515,\"dockRim27Angle\":90.237946,\"dockRim27EndLevel\":0.23693,\"dockRim27Falloff\":3.474776,\"dockRi" \
    "m27Hex\":\"#000000FF\",\"dockRim27Opacity\":0.740128,\"dockRim27Sharpness\":5.057376,\"dockRim27Width\":1" \
    ".500477,\"dockRimBrightness\":1,\"dockRimFade\":0,\"dockRimHex\":\"#FFFFFFFF\",\"dockRimOpacity\":0.4318,\"" \
    "dockRimSampleBrightness\":1,\"dockRimSampleFade\":0,\"dockRimSampleOpacity\":0.4318,\"dockRimSampleWid" \
    "th\":0.9871,\"dockRimStyle\":2,\"dockSearchGap\":8.215075,\"dockSearchHeightRatio\":0.901107,\"dockSearc" \
    "hWidthFraction\":0.94,\"dockSwitchTiming\":0,\"dockTapTravel\":true,\"dockTitleBolderSelected\":false,\"" \
    "dockTitleSize\":9.467164,\"dockTitleWeight\":2,\"edgeChatBlurBottom\":74.845871,\"edgeChatBlurBottomRa" \
    "dius\":0.489007,\"edgeChatBlurTop\":122.960503,\"edgeChatBlurTopRadius\":1.0719,\"edgeChatFadeBottom\":" \
    "57.739208,\"edgeChatFadeTop\":93.562401,\"edgeOtherBlurBottom\":58.11937,\"edgeOtherBlurBottomRadius\"" \
    ":0.345396,\"edgeOtherBlurTop\":122.960503,\"edgeOtherBlurTopRadius\":1.004318,\"edgeOtherFadeBottom\":" \
    "28.087681,\"edgeOtherFadeTop\":69.908768,\"edgeWidth\":7.745368,\"endWrap\":9.11254,\"fadeMaterialAtEdg" \
    "e\":false,\"haptics\":true,\"height\":61.071041,\"lensBlur\":0,\"lensBlurCoverage\":0,\"lensBorderWidth\":1" \
    ".1029,\"lensDispersion\":4.583065,\"lensDispersionTopRatio\":0.332732,\"lensDispersionWidth\":19.18059" \
    "9,\"lensEdgeSharpness\":3.253887,\"lensEdgeWidth\":19.180599,\"lensGrowth\":1.181511,\"lensRefraction\":" \
    "6.827437,\"lensRimHex\":\"#FFFFFFFF\",\"lensRimOpacity\":0.5859,\"lensTopEdgeRatio\":0.332732,\"lensZoom\"" \
    ":1.062969,\"lift\":-4.45887,\"materialEdgeFade\":15.895641,\"materialEdgeFadeEnabled\":false,\"material" \
    "FadeWidth\":7.43837,\"materialHex\":\"#F9F9F9FF\",\"materialOpacity\":0.07713,\"messageMenuCornerRadius\"" \
    ":25.744907,\"motionPrediction\":false,\"performanceMode\":true,\"pressStretch\":true,\"pressStretchAmou" \
    "nt\":0.863072,\"pressStretchCapsule\":0.305054,\"pressStretchDistance\":17.668806,\"pressStretchFollow" \
    "\":0.222689,\"pressStretchMax\":11.450727,\"pressStretchNative\":true,\"pressedOpacity\":0.4,\"refractio" \
    "n\":8.875051,\"renderMode\":2,\"rim27Angle\":0,\"rim27EndLevel\":0,\"rim27Falloff\":4,\"rim27Hex\":\"#FFFFFF" \
    "FF\",\"rim27Opacity\":0.858465,\"rim27Sharpness\":6,\"rim27Width\":4.868663,\"rimBrightness\":1.0008,\"rim" \
    "Details\":true,\"rimFade\":0.7095,\"rimFadeBottomRight\":0,\"rimFadeTopLeft\":0,\"rimHex\":\"#FFFFFFFF\",\"r" \
    "imInnerFade\":0.8,\"rimInnerShadowHex\":\"#000000FF\",\"rimInnerShadowOpacity\":0.0145,\"rimInnerShadowR" \
    "adius\":1.461,\"rimOpacity\":0.5057,\"rimOuterFade\":0.1,\"rimSampleBlur\":10,\"rimSampleBrightness\":1.0" \
    "008,\"rimSampleColor\":false,\"rimSampleContrast\":1.2569,\"rimSampleFade\":0.7095,\"rimSampleGain\":0.8" \
    "799,\"rimSampleLift\":0.4852,\"rimSampleOpacity\":0.5057,\"rimSamplePlusLighter\":true,\"rimSampleSatur" \
    "ation\":3,\"rimSampleWidth\":1.2352,\"rimSideDarken\":false,\"rimSideLevel\":0.1298,\"rimStyle\":2,\"sampl" \
    "erSource\":1,\"selectionHex\":\"#85858533\",\"selectionInset\":4.00067,\"selectionOpacity\":0.611066,\"syn" \
    "cBlurScale\":0.993364,\"syncCaptureScale\":3,\"syncDispersion\":true,\"syncMeshRefraction\":true,\"syncP" \
    "resent\":true,\"useWeChatIcons\":true,\"widthFraction\":0.918869},\"integration\":{\"adaptiveIdle\":true," \
    "\"avatarTitle\":false,\"bubbles\":true,\"dock\":true,\"dockSearch\":true,\"dockSearchLeading\":false,\"edge" \
    "Fade\":true,\"hideTopSearch\":true,\"input\":true,\"nativeInputTest\":true,\"nav\":true,\"sizeScale\":1.014" \
    "269},\"ui\":{\"cardRadius\":26}}"
