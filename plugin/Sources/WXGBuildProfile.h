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
    "{\"config\":{\"alwaysShow\":true,\"avatarBorderHex\":\"#FFFFFF3E\",\"avatarBorderWidth\":0.998891,\"avatarC" \
    "apsuleHeight\":34.777061,\"avatarDarkBorderHex\":\"#9E9E9E6B\",\"avatarOffsetY\":0,\"avatarSize\":60.2531" \
    "32,\"barBorderWidth\":1.2352,\"barGrowth\":1.035671,\"blur\":0.906752,\"blurCoverage\":67.675415,\"bodyPi" \
    "nch\":0.090514,\"borderHex\":\"#FFFFFFFF\",\"borderOpacity\":0.405681,\"bubbleBlur\":1.000937,\"bubbleBlur" \
    "Coverage\":100,\"bubbleBorderWidth\":1.2352,\"bubbleDarkBorderWidth\":0.9691,\"bubbleDarkRim27Angle\":9" \
    "0.07341,\"bubbleDarkRim27DarkModeAngle\":90.07341,\"bubbleDarkRim27DarkModeEndLevel\":0.260384,\"bubb" \
    "leDarkRim27DarkModeFalloff\":2.97582,\"bubbleDarkRim27DarkModeHex\":\"#000000FF\",\"bubbleDarkRim27Dar" \
    "kModeOpacity\":1,\"bubbleDarkRim27DarkModeSharpness\":3.664598,\"bubbleDarkRim27DarkModeWidth\":1.426" \
    "596,\"bubbleDarkRim27EndLevel\":0.260384,\"bubbleDarkRim27Falloff\":2.97582,\"bubbleDarkRim27Hex\":\"#0" \
    "00000FF\",\"bubbleDarkRim27Opacity\":1,\"bubbleDarkRim27Sharpness\":3.664598,\"bubbleDarkRim27Width\":1" \
    ".426596,\"bubbleDarkRimBrightness\":0.8572,\"bubbleDarkRimFade\":1,\"bubbleDarkRimHex\":\"#C2C2C2FF\",\"b" \
    "ubbleDarkRimOpacity\":0.1361,\"bubbleDarkRimSampleBrightness\":0.8572,\"bubbleDarkRimSampleFade\":1,\"" \
    "bubbleDarkRimSampleOpacity\":0.1361,\"bubbleDarkRimSampleSoftLevel\":0.5,\"bubbleDarkRimSampleSoftWi" \
    "dth\":0.8,\"bubbleDarkRimSampleWidth\":0.9691,\"bubbleDarkRimSoftLevel\":0.5,\"bubbleDarkRimSoftWidth\"" \
    ":0.8,\"bubbleDispersion\":4.966304,\"bubbleEdgeFade\":8,\"bubbleEdgeFadeEnabled\":false,\"bubbleEdgeWid" \
    "th\":5.727864,\"bubbleFullGlass\":true,\"bubbleIncomingHex\":\"#FFFFFF00\",\"bubbleOutgoingHex\":\"#95EC69" \
    "00\",\"bubbleRefraction\":10.198232,\"bubbleRim27Angle\":0,\"bubbleRim27DarkModeAngle\":0,\"bubbleRim27D" \
    "arkModeEndLevel\":0.097029,\"bubbleRim27DarkModeFalloff\":2.15903,\"bubbleRim27DarkModeHex\":\"#FFFFFF" \
    "FF\",\"bubbleRim27DarkModeOpacity\":0.861663,\"bubbleRim27DarkModeSharpness\":2,\"bubbleRim27DarkModeW" \
    "idth\":2.063489,\"bubbleRim27EndLevel\":0.097029,\"bubbleRim27Falloff\":2.15903,\"bubbleRim27Hex\":\"#FF" \
    "FFFFFF\",\"bubbleRim27Opacity\":0.861663,\"bubbleRim27Sharpness\":2,\"bubbleRim27Width\":2.063489,\"bubb" \
    "leRimBrightness\":1.0008,\"bubbleRimFade\":0.7095,\"bubbleRimHex\":\"#FFFFFFFF\",\"bubbleRimInward\":1,\"b" \
    "ubbleRimOpacity\":0.5057,\"bubbleRimSampleBrightness\":1.0008,\"bubbleRimSampleFade\":0.7095,\"bubbleR" \
    "imSampleOpacity\":0.5057,\"bubbleRimSampleSoft\":1,\"bubbleRimSampleSoftLevel\":0.5,\"bubbleRimSampleS" \
    "oftWidth\":0.8,\"bubbleRimSampleWidth\":1.2352,\"bubbleRimSoftLevel\":0.5,\"bubbleRimSoftWidth\":0.8,\"b" \
    "ubbleRimStyle\":1,\"calibration\":false,\"captureBudget\":80,\"captureFPS\":120,\"cardBlur\":0.143794,\"ca" \
    "rdBlurCoverage\":67.675415,\"cardBorderWidth\":1.2352,\"cardDarkBorderWidth\":0.9691,\"cardDarkMateria" \
    "lHex\":\"#2C2C2EFF\",\"cardDarkMaterialOpacity\":0.86,\"cardDarkRim27Angle\":90.192924,\"cardDarkRim27Da" \
    "rkModeAngle\":90.192924,\"cardDarkRim27DarkModeEndLevel\":0.195352,\"cardDarkRim27DarkModeFalloff\":4" \
    ",\"cardDarkRim27DarkModeHex\":\"#000000FF\",\"cardDarkRim27DarkModeOpacity\":0.809269,\"cardDarkRim27Da" \
    "rkModeSharpness\":6,\"cardDarkRim27DarkModeWidth\":1.525563,\"cardDarkRim27EndLevel\":0.195352,\"cardD" \
    "arkRim27Falloff\":4,\"cardDarkRim27Hex\":\"#000000FF\",\"cardDarkRim27Opacity\":0.809269,\"cardDarkRim27" \
    "Sharpness\":6,\"cardDarkRim27Width\":1.525563,\"cardDarkRimBrightness\":0.8572,\"cardDarkRimFade\":1,\"c" \
    "ardDarkRimHex\":\"#C2C2C2FF\",\"cardDarkRimOpacity\":0.1361,\"cardDarkRimSampleBrightness\":0.8572,\"car" \
    "dDarkRimSampleFade\":1,\"cardDarkRimSampleOpacity\":0.1361,\"cardDarkRimSampleSoftLevel\":0.383702,\"c" \
    "ardDarkRimSampleSoftWidth\":0.888126,\"cardDarkRimSampleWidth\":0.9691,\"cardDarkRimSoftLevel\":0.383" \
    "702,\"cardDarkRimSoftWidth\":0.888126,\"cardDispersion\":1.942017,\"cardEdgeWidth\":7.745368,\"cardMate" \
    "rialEdgeFade\":0,\"cardMaterialEdgeFadeEnabled\":0,\"cardMaterialHex\":\"#FFFFFFFF\",\"cardMaterialOpaci" \
    "ty\":0.82,\"cardRefraction\":8.875051,\"cardRim27Angle\":88.842445,\"cardRim27DarkModeAngle\":88.842445" \
    ",\"cardRim27DarkModeEndLevel\":0.203765,\"cardRim27DarkModeFalloff\":4,\"cardRim27DarkModeHex\":\"#FFFF" \
    "FFFF\",\"cardRim27DarkModeOpacity\":0.889544,\"cardRim27DarkModeSharpness\":6,\"cardRim27DarkModeWidth" \
    "\":1.189057,\"cardRim27EndLevel\":0.203765,\"cardRim27Falloff\":4,\"cardRim27Hex\":\"#FFFFFFFF\",\"cardRim" \
    "27Opacity\":0.889544,\"cardRim27Sharpness\":6,\"cardRim27Width\":1.189057,\"cardRimBrightness\":1.0008," \
    "\"cardRimFade\":0.7095,\"cardRimHex\":\"#FFFFFFFF\",\"cardRimInward\":1,\"cardRimOpacity\":0.5057,\"cardRim" \
    "SampleBrightness\":0.524732,\"cardRimSampleFade\":0,\"cardRimSampleOpacity\":0.193126,\"cardRimSampleS" \
    "oft\":1,\"cardRimSampleSoftLevel\":0.132096,\"cardRimSampleSoftWidth\":1.723244,\"cardRimSampleWidth\":" \
    "0.894766,\"cardRimSoftLevel\":0.5,\"cardRimSoftWidth\":0.8,\"cardRimStyle\":0,\"chatAvatarInset\":2.4973" \
    "55,\"chatNativeBar\":0,\"chatSegments\":1,\"clearMaterial\":true,\"darkBarBorderWidth\":0.9691,\"darkBubb" \
    "leIncomingHex\":\"#2C2C2C00\",\"darkBubbleOutgoingHex\":\"#95EC6900\",\"darkLensBorderWidth\":1.025723,\"d" \
    "arkLensRimHex\":\"#5C5C5CFF\",\"darkLensRimOpacity\":0.626474,\"darkLensTintHex\":\"#FFFFFF00\",\"darkLens" \
    "TintOpacity\":0,\"darkMaterialHex\":\"#222222FF\",\"darkMaterialOpacity\":0.461763,\"darkRim27Angle\":90." \
    "192924,\"darkRim27DarkModeAngle\":90.192924,\"darkRim27DarkModeEndLevel\":0.042337,\"darkRim27DarkMod" \
    "eFalloff\":2.831458,\"darkRim27DarkModeHex\":\"#333333FF\",\"darkRim27DarkModeOpacity\":0.684352,\"darkR" \
    "im27DarkModeSharpness\":6,\"darkRim27DarkModeWidth\":2.590193,\"darkRim27EndLevel\":0.195352,\"darkRim" \
    "27Falloff\":4,\"darkRim27Hex\":\"#000000FF\",\"darkRim27Opacity\":0.879421,\"darkRim27Sharpness\":6,\"dark" \
    "Rim27Width\":1.525563,\"darkRimBrightness\":0.8572,\"darkRimFade\":1,\"darkRimFadeBottomRight\":0,\"dark" \
    "RimFadeTopLeft\":0,\"darkRimGain\":0.162379,\"darkRimHex\":\"#C2C2C2FF\",\"darkRimInnerFade\":1.5,\"darkRi" \
    "mInnerShadowHex\":\"#000000FF\",\"darkRimInnerShadowOpacity\":0.22,\"darkRimInnerShadowRadius\":0.8711," \
    "\"darkRimOpacity\":0.1361,\"darkRimOuterFade\":0.3,\"darkRimSampleBlur\":10,\"darkRimSampleBrightness\":" \
    "0.8572,\"darkRimSampleContrast\":0.5,\"darkRimSampleFade\":1,\"darkRimSampleGain\":2.5,\"darkRimSampleL" \
    "ift\":0.6,\"darkRimSampleOpacity\":0.1361,\"darkRimSampleSaturation\":1.5931,\"darkRimSampleSoftLevel\"" \
    ":0.383702,\"darkRimSampleSoftWidth\":0.888126,\"darkRimSampleWidth\":0.9691,\"darkRimSideDarken\":fals" \
    "e,\"darkRimSideLevel\":0.5595,\"darkRimSoftLevel\":0.383702,\"darkRimSoftWidth\":0.888126,\"darkSelecti" \
    "onHex\":\"#5C5C5C80\",\"dispersion\":1.38478,\"dockAccentHex\":\"#0088FFFF\",\"dockBlur\":1.088315,\"dockBlu" \
    "rCoverage\":71.650589,\"dockBorderWidth\":0.9871,\"dockDarkBorderWidth\":0.70418,\"dockDarkMaterialHex" \
    "\":\"#191919FF\",\"dockDarkMaterialOpacity\":0.748249,\"dockDarkRim27Angle\":0,\"dockDarkRim27DarkModeAn" \
    "gle\":0,\"dockDarkRim27DarkModeEndLevel\":0.15,\"dockDarkRim27DarkModeFalloff\":3.874029,\"dockDarkRim" \
    "27DarkModeHex\":\"#FFFFFFFF\",\"dockDarkRim27DarkModeOpacity\":0.687889,\"dockDarkRim27DarkModeSharpne" \
    "ss\":5.761001,\"dockDarkRim27DarkModeWidth\":2.042268,\"dockDarkRim27EndLevel\":0.15,\"dockDarkRim27Fa" \
    "lloff\":3.874029,\"dockDarkRim27Hex\":\"#FFFFFFFF\",\"dockDarkRim27Opacity\":0.687889,\"dockDarkRim27Sha" \
    "rpness\":5.761001,\"dockDarkRim27Width\":2.042268,\"dockDarkRimBrightness\":0.5456,\"dockDarkRimFade\":" \
    "0.811897,\"dockDarkRimHex\":\"#FFFFFFFF\",\"dockDarkRimOpacity\":0.110932,\"dockDarkRimSampleBrightness" \
    "\":0.5456,\"dockDarkRimSampleFade\":0,\"dockDarkRimSampleOpacity\":0.228,\"dockDarkRimSampleSoftLevel\"" \
    ":0.5,\"dockDarkRimSampleSoftWidth\":0.8,\"dockDarkRimSampleWidth\":1.0093,\"dockDarkRimSoftLevel\":0.5" \
    ",\"dockDarkRimSoftWidth\":0.8,\"dockDiscrete\":false,\"dockDiscreteBall\":1.004019,\"dockDiscreteConnec" \
    "ted\":false,\"dockDiscreteContentShift\":5.032154,\"dockDiscreteDamping\":0.6,\"dockDiscreteGap\":8,\"do" \
    "ckDiscreteGather\":0.182845,\"dockDiscreteIconSize\":27.999245,\"dockDiscreteLight\":false,\"dockDiscr" \
    "etePill\":false,\"dockDiscreteResponse\":0.45,\"dockDiscreteSubtitleSize\":11,\"dockDiscreteTitleSize\"" \
    ":13.208338,\"dockDiscreteWide\":2,\"dockDispersion\":2.216506,\"dockEdgeWidth\":10.833332,\"dockEndStre" \
    "tch\":false,\"dockEndStretchDistance\":18,\"dockIconOffset\":-0.582347,\"dockIconTitleGap\":3.620297,\"d" \
    "ockMaterialEdgeFade\":3.540837,\"dockMaterialEdgeFadeEnabled\":false,\"dockMaterialFadeWidth\":0,\"doc" \
    "kMaterialHex\":\"#FFFFFFFF\",\"dockMaterialOpacity\":0.637901,\"dockRefraction\":7.513397,\"dockRim27Ang" \
    "le\":90.237946,\"dockRim27DarkModeAngle\":90.237946,\"dockRim27DarkModeEndLevel\":0.23693,\"dockRim27D" \
    "arkModeFalloff\":3.474776,\"dockRim27DarkModeHex\":\"#000000FF\",\"dockRim27DarkModeOpacity\":0.8517,\"d" \
    "ockRim27DarkModeSharpness\":5.057376,\"dockRim27DarkModeWidth\":0.756373,\"dockRim27EndLevel\":0.2369" \
    "3,\"dockRim27Falloff\":3.474776,\"dockRim27Hex\":\"#000000FF\",\"dockRim27Opacity\":0.8517,\"dockRim27Sha" \
    "rpness\":5.057376,\"dockRim27Width\":0.756373,\"dockRimBrightness\":1,\"dockRimFade\":0.79582,\"dockRimH" \
    "ex\":\"#FFFFFFFF\",\"dockRimInward\":1,\"dockRimOpacity\":0.42926,\"dockRimSampleBrightness\":1,\"dockRimS" \
    "ampleFade\":0,\"dockRimSampleOpacity\":0.4318,\"dockRimSampleSoft\":1,\"dockRimSampleSoftLevel\":0.5,\"d" \
    "ockRimSampleSoftWidth\":0.8,\"dockRimSampleWidth\":0.9871,\"dockRimSoftLevel\":0.5,\"dockRimSoftWidth\"" \
    ":0.8,\"dockRimStyle\":0,\"dockSearchGap\":8.215075,\"dockSearchHeightRatio\":1,\"dockSearchWidthFractio" \
    "n\":0.94,\"dockSwitchTiming\":0,\"dockTapCalmWaitOn\":0,\"dockTapCatchUp\":true,\"dockTapDropTime\":0.251" \
    "704,\"dockTapLensShare\":0.715514,\"dockTapMoveScale\":1.4,\"dockTapSimpleTravel\":false,\"dockTapSwitc" \
    "hWhen\":0,\"dockTapTravel\":true,\"dockTelegramIcons\":1,\"dockTitleBolderSelected\":false,\"dockTitleSi" \
    "ze\":9.467164,\"dockTitleWeight\":1,\"dockTitleWeightNative\":1,\"edgeChatBlurBottom\":74.845871,\"edgeC" \
    "hatBlurBottomRadius\":0.489007,\"edgeChatBlurTop\":123.644142,\"edgeChatBlurTopRadius\":1.0719,\"edgeC" \
    "hatFadeBottom\":57.739208,\"edgeChatFadeTop\":94.195511,\"edgeOtherBlurBottom\":58.11937,\"edgeOtherBl" \
    "urBottomRadius\":0.345396,\"edgeOtherBlurTop\":73.226143,\"edgeOtherBlurTopRadius\":1.004318,\"edgeOth" \
    "erFadeBottom\":28.087681,\"edgeOtherFadeTop\":69.908768,\"edgeWidth\":8.367094,\"endWrap\":9.11254,\"fad" \
    "eMaterialAtEdge\":false,\"haptics\":false,\"height\":61.350483,\"inputSystemIcons\":1,\"lensBarDispersio" \
    "n\":2,\"lensBarDispersionNearRim\":1,\"lensBarDispersionOn\":false,\"lensBarOutlineOn\":0,\"lensBarVeilO" \
    "n\":0,\"lensBlur\":0,\"lensBlurCoverage\":0,\"lensBorderWidth\":2,\"lensDispersion\":1.101822,\"lensDisper" \
    "sionTopRatio\":0.143891,\"lensDispersionWidth\":6.406753,\"lensEdgeSharpness\":4.148446,\"lensEdgeWidt" \
    "h\":25.44105,\"lensElasticHeight\":1,\"lensElasticKeepStrip\":0.57717,\"lensElasticOn\":1,\"lensGlassBor" \
    "derWidth\":2,\"lensGlassDarkBorderWidth\":1.025723,\"lensGlassDarkRim27Angle\":0,\"lensGlassDarkRim27D" \
    "arkModeAngle\":0,\"lensGlassDarkRim27DarkModeEndLevel\":0.15,\"lensGlassDarkRim27DarkModeFalloff\":1." \
    "090836,\"lensGlassDarkRim27DarkModeHex\":\"#FFFFFFFF\",\"lensGlassDarkRim27DarkModeOpacity\":0.226688," \
    "\"lensGlassDarkRim27DarkModeSharpness\":5.761001,\"lensGlassDarkRim27DarkModeWidth\":1.665862,\"lensG" \
    "lassDarkRim27EndLevel\":0.15,\"lensGlassDarkRim27Falloff\":1.090836,\"lensGlassDarkRim27Hex\":\"#FFFFF" \
    "FFF\",\"lensGlassDarkRim27Opacity\":1,\"lensGlassDarkRim27Sharpness\":5.761001,\"lensGlassDarkRim27Wid" \
    "th\":3.151393,\"lensGlassDarkRimBrightness\":0.5456,\"lensGlassDarkRimFade\":0,\"lensGlassDarkRimHex\":" \
    "\"#5C5C5CFF\",\"lensGlassDarkRimOpacity\":0.626474,\"lensGlassDarkRimSampleBrightness\":0.5456,\"lensGl" \
    "assDarkRimSampleFade\":0,\"lensGlassDarkRimSampleOpacity\":0.228,\"lensGlassDarkRimSampleSoftLevel\":" \
    "0.5,\"lensGlassDarkRimSampleSoftWidth\":0.8,\"lensGlassDarkRimSampleWidth\":1.0093,\"lensGlassDarkRim" \
    "SoftLevel\":0.5,\"lensGlassDarkRimSoftWidth\":0.8,\"lensGlassRim27Angle\":90.237946,\"lensGlassRim27Da" \
    "rkModeAngle\":90.237946,\"lensGlassRim27DarkModeEndLevel\":0.23693,\"lensGlassRim27DarkModeFalloff\":" \
    "1.068328,\"lensGlassRim27DarkModeHex\":\"#FFFFFFFF\",\"lensGlassRim27DarkModeOpacity\":0.343516,\"lensG" \
    "lassRim27DarkModeSharpness\":5.057376,\"lensGlassRim27DarkModeWidth\":1.129421,\"lensGlassRim27EndLe" \
    "vel\":0.23693,\"lensGlassRim27Falloff\":1.068328,\"lensGlassRim27Hex\":\"#FFFFFFFF\",\"lensGlassRim27Opa" \
    "city\":1,\"lensGlassRim27Sharpness\":5.057376,\"lensGlassRim27Width\":3.473258,\"lensGlassRimBrightnes" \
    "s\":1,\"lensGlassRimFade\":0,\"lensGlassRimHex\":\"#FFFFFFFF\",\"lensGlassRimInward\":0,\"lensGlassRimOpac" \
    "ity\":0.658628,\"lensGlassRimSampleBrightness\":1,\"lensGlassRimSampleFade\":0,\"lensGlassRimSampleOpa" \
    "city\":0.4318,\"lensGlassRimSampleSoft\":1,\"lensGlassRimSampleSoftLevel\":0.5,\"lensGlassRimSampleSof" \
    "tWidth\":0.8,\"lensGlassRimSampleWidth\":0.9871,\"lensGlassRimSoftLevel\":0.5,\"lensGlassRimSoftWidth\"" \
    ":0.8,\"lensGlassRimStyle\":2,\"lensGrowth\":1.181511,\"lensIconEdgeSharpness\":4.684351,\"lensIconEdgeW" \
    "idth\":16.904072,\"lensIconRefraction\":2.21865,\"lensIconTopEdgeRatio\":0.4709,\"lensOffsetCancel\":0." \
    "07985,\"lensRefraction\":4.705251,\"lensRefractsBar\":1,\"lensRimHex\":\"#FFFFFFFF\",\"lensRimOpacity\":0." \
    "658628,\"lensTintHex\":\"#EBEBEB65\",\"lensTintOn\":1,\"lensTintOpacity\":0.532154,\"lensTopEdgeRatio\":0." \
    "332958,\"lensZoom\":1.0694,\"lift\":-6.680297,\"localTabRadius\":14.989619,\"localTileRadius\":20.033772" \
    ",\"materialEdgeFade\":15.895641,\"materialEdgeFadeEnabled\":false,\"materialFadeWidth\":7.43837,\"mater" \
    "ialHex\":\"#FFFFFFFF\",\"materialOpacity\":0.585778,\"messageMenuCornerRadius\":25.744907,\"motionPredic" \
    "tion\":false,\"navEdge\":14.107181,\"navNativeButtons\":0,\"navOffsetY\":0,\"performanceMode\":true,\"pinn" \
    "edGapAdjust\":-4.47529,\"pressStretch\":true,\"pressStretchAmount\":0.863072,\"pressStretchCapsule\":0." \
    "305054,\"pressStretchDistance\":17.668806,\"pressStretchFollow\":0.222689,\"pressStretchMax\":9.812069" \
    ",\"pressStretchNative\":true,\"pressedOpacity\":0.4,\"refraction\":8.670954,\"renderMode\":2,\"rim27Angle" \
    "\":0,\"rim27DarkModeAngle\":0,\"rim27DarkModeEndLevel\":0.038049,\"rim27DarkModeFalloff\":4,\"rim27DarkM" \
    "odeHex\":\"#FFFFFFFF\",\"rim27DarkModeOpacity\":0.595391,\"rim27DarkModeSharpness\":4.647106,\"rim27Dark" \
    "ModeWidth\":5.198124,\"rim27EndLevel\":0.203765,\"rim27Falloff\":4,\"rim27Hex\":\"#FFFFFFFF\",\"rim27Opaci" \
    "ty\":0.949089,\"rim27Sharpness\":6,\"rim27Width\":2.02074,\"rimBrightness\":1.0008,\"rimDetails\":true,\"r" \
    "imFade\":0.7095,\"rimFadeBottomRight\":0,\"rimFadeTopLeft\":0,\"rimHex\":\"#FFFFFFFF\",\"rimInnerFade\":0.8" \
    ",\"rimInnerShadowHex\":\"#000000FF\",\"rimInnerShadowOpacity\":0.0145,\"rimInnerShadowRadius\":1.461,\"ri" \
    "mInward\":1,\"rimOpacity\":0.5057,\"rimOuterFade\":0.1,\"rimSampleBlur\":10,\"rimSampleBrightness\":0.524" \
    "732,\"rimSampleColor\":false,\"rimSampleContrast\":1.2569,\"rimSampleFade\":0,\"rimSampleGain\":0.8799,\"" \
    "rimSampleLift\":0.4852,\"rimSampleOpacity\":0.420686,\"rimSamplePlusLighter\":true,\"rimSampleSaturati" \
    "on\":3,\"rimSampleSoft\":1,\"rimSampleSoftLevel\":0.132096,\"rimSampleSoftWidth\":1.723244,\"rimSampleWi" \
    "dth\":0.894766,\"rimSideDarken\":false,\"rimSideLevel\":0.1298,\"rimSoftLevel\":0.5,\"rimSoftWidth\":0.8," \
    "\"rimStyle\":0,\"samplerSource\":1,\"searchFloat\":1,\"segmentAccentHex\":\"#0088FFFF\",\"segmentAccentOn\":" \
    "1,\"segmentBarGrowth\":1.035671,\"segmentBlur\":1.088315,\"segmentBlurCoverage\":71.650589,\"segmentBod" \
    "yPinch\":0.131029,\"segmentBorderWidth\":0.9871,\"segmentDarkBorderWidth\":1.0093,\"segmentDarkInkHex\"" \
    ":\"#F7F7F7F7\",\"segmentDarkLensBorderWidth\":0.6892,\"segmentDarkLensRimHex\":\"#D6D6D6FF\",\"segmentDar" \
    "kLensRimOpacity\":0.2696,\"segmentDarkLensTintHex\":\"#FFFFFF00\",\"segmentDarkLensTintOpacity\":0,\"seg" \
    "mentDarkMaterialHex\":\"#191919FF\",\"segmentDarkMaterialOpacity\":0.248124,\"segmentDarkPillHex\":\"#5C" \
    "5C5C80\",\"segmentDarkPillOpacity\":0.611066,\"segmentDarkRim27Angle\":0,\"segmentDarkRim27DarkModeAng" \
    "le\":0,\"segmentDarkRim27DarkModeEndLevel\":0.15,\"segmentDarkRim27DarkModeFalloff\":3.874029,\"segmen" \
    "tDarkRim27DarkModeHex\":\"#FFFFFFFF\",\"segmentDarkRim27DarkModeOpacity\":0.687889,\"segmentDarkRim27D" \
    "arkModeSharpness\":5.761001,\"segmentDarkRim27DarkModeWidth\":0.741533,\"segmentDarkRim27EndLevel\":0" \
    ".15,\"segmentDarkRim27Falloff\":3.874029,\"segmentDarkRim27Hex\":\"#FFFFFFFF\",\"segmentDarkRim27Opacit" \
    "y\":0.687889,\"segmentDarkRim27Sharpness\":5.761001,\"segmentDarkRim27Width\":0.460932,\"segmentDarkRi" \
    "mBrightness\":0.5456,\"segmentDarkRimFade\":0,\"segmentDarkRimHex\":\"#FFFFFFFF\",\"segmentDarkRimOpacit" \
    "y\":0.228,\"segmentDarkRimSampleBrightness\":0.5456,\"segmentDarkRimSampleFade\":0.758307,\"segmentDar" \
    "kRimSampleOpacity\":0.228,\"segmentDarkRimSampleSoftLevel\":0.5,\"segmentDarkRimSampleSoftWidth\":0.8" \
    ",\"segmentDarkRimSampleWidth\":0.444802,\"segmentDarkRimSoftLevel\":0.5,\"segmentDarkRimSoftWidth\":0." \
    "8,\"segmentDispersion\":2.216506,\"segmentDockLook\":1,\"segmentEdgeWidth\":10.833332,\"segmentEndWrap\"" \
    ":9.11254,\"segmentInkHex\":\"#1A1A1AEB\",\"segmentLensBarDispersion\":0.785638,\"segmentLensBarDispersi" \
    "onNearRim\":0.449625,\"segmentLensBarDispersionOn\":1,\"segmentLensBlur\":0,\"segmentLensBlurCoverage\"" \
    ":0,\"segmentLensBorderWidth\":0.521972,\"segmentLensDispersion\":0.62165,\"segmentLensDispersionTopRa" \
    "tio\":0.6,\"segmentLensDispersionWidth\":39.54287,\"segmentLensEdgeSharpness\":1.790461,\"segmentLensE" \
    "dgeWidth\":10.011254,\"segmentLensElasticHeight\":1,\"segmentLensElasticKeepStrip\":1,\"segmentLensEla" \
    "sticOn\":1,\"segmentLensGlassBorderWidth\":2,\"segmentLensGlassDarkBorderWidth\":1.025723,\"segmentLen" \
    "sGlassDarkRim27Angle\":0,\"segmentLensGlassDarkRim27DarkModeAngle\":0,\"segmentLensGlassDarkRim27Dar" \
    "kModeEndLevel\":0.15,\"segmentLensGlassDarkRim27DarkModeFalloff\":1.090836,\"segmentLensGlassDarkRim" \
    "27DarkModeHex\":\"#FFFFFFFF\",\"segmentLensGlassDarkRim27DarkModeOpacity\":0.226688,\"segmentLensGlass" \
    "DarkRim27DarkModeSharpness\":5.761001,\"segmentLensGlassDarkRim27DarkModeWidth\":1.665862,\"segmentL" \
    "ensGlassDarkRim27EndLevel\":0.15,\"segmentLensGlassDarkRim27Falloff\":1.090836,\"segmentLensGlassDar" \
    "kRim27Hex\":\"#FFFFFFFF\",\"segmentLensGlassDarkRim27Opacity\":1,\"segmentLensGlassDarkRim27Sharpness\"" \
    ":5.761001,\"segmentLensGlassDarkRim27Width\":3.151393,\"segmentLensGlassDarkRimBrightness\":0.5456,\"" \
    "segmentLensGlassDarkRimFade\":0,\"segmentLensGlassDarkRimHex\":\"#5C5C5CFF\",\"segmentLensGlassDarkRim" \
    "Opacity\":0.626474,\"segmentLensGlassDarkRimSampleBrightness\":0.5456,\"segmentLensGlassDarkRimSampl" \
    "eFade\":0,\"segmentLensGlassDarkRimSampleOpacity\":0.228,\"segmentLensGlassDarkRimSampleSoftLevel\":0" \
    ".5,\"segmentLensGlassDarkRimSampleSoftWidth\":0.8,\"segmentLensGlassDarkRimSampleWidth\":1.0093,\"seg" \
    "mentLensGlassDarkRimSoftLevel\":0.5,\"segmentLensGlassDarkRimSoftWidth\":0.8,\"segmentLensGlassRim27" \
    "Angle\":90.237946,\"segmentLensGlassRim27DarkModeAngle\":90.237946,\"segmentLensGlassRim27DarkModeEn" \
    "dLevel\":0.23693,\"segmentLensGlassRim27DarkModeFalloff\":1.068328,\"segmentLensGlassRim27DarkModeHe" \
    "x\":\"#FFFFFFFF\",\"segmentLensGlassRim27DarkModeOpacity\":0.343516,\"segmentLensGlassRim27DarkModeSha" \
    "rpness\":5.057376,\"segmentLensGlassRim27DarkModeWidth\":1.129421,\"segmentLensGlassRim27EndLevel\":0" \
    ".23693,\"segmentLensGlassRim27Falloff\":1.068328,\"segmentLensGlassRim27Hex\":\"#FFFFFFFF\",\"segmentLe" \
    "nsGlassRim27Opacity\":1,\"segmentLensGlassRim27Sharpness\":5.057376,\"segmentLensGlassRim27Width\":3." \
    "473258,\"segmentLensGlassRimBrightness\":1,\"segmentLensGlassRimFade\":0,\"segmentLensGlassRimHex\":\"#" \
    "FFFFFFFF\",\"segmentLensGlassRimInward\":0,\"segmentLensGlassRimOpacity\":0.658628,\"segmentLensGlassR" \
    "imSampleBrightness\":1,\"segmentLensGlassRimSampleFade\":0,\"segmentLensGlassRimSampleOpacity\":0.431" \
    "8,\"segmentLensGlassRimSampleSoft\":1,\"segmentLensGlassRimSampleSoftLevel\":0.5,\"segmentLensGlassRi" \
    "mSampleSoftWidth\":0.8,\"segmentLensGlassRimSampleWidth\":0.9871,\"segmentLensGlassRimSoftLevel\":0.5" \
    ",\"segmentLensGlassRimSoftWidth\":0.8,\"segmentLensGlassRimStyle\":2,\"segmentLensGrowth\":1.181511,\"s" \
    "egmentLensIconEdgeSharpness\":1.790461,\"segmentLensIconEdgeWidth\":14.374599,\"segmentLensIconRefra" \
    "ction\":2.454447,\"segmentLensIconTopEdgeRatio\":0.316559,\"segmentLensOffsetCancel\":0.07985,\"segmen" \
    "tLensRefraction\":5.369775,\"segmentLensRimHex\":\"#FFFFFFFF\",\"segmentLensRimOpacity\":0.658628,\"segm" \
    "entLensTintHex\":\"#EBEBEB65\",\"segmentLensTintOn\":1,\"segmentLensTintOpacity\":0.532154,\"segmentLens" \
    "TopEdgeRatio\":0.316559,\"segmentLensZoom\":1.12567,\"segmentMaterialEdgeFade\":3.540837,\"segmentMate" \
    "rialEdgeFadeEnabled\":0,\"segmentMaterialHex\":\"#FFFFFFFF\",\"segmentMaterialOpacity\":0.637901,\"segme" \
    "ntPillAuto\":0,\"segmentPillHex\":\"#85858533\",\"segmentPillOpacity\":0.611066,\"segmentPillPressedOpac" \
    "ity\":0.4,\"segmentPillRimAtRest\":0,\"segmentRefraction\":7.513397,\"segmentRim27Angle\":90.237946,\"se" \
    "gmentRim27DarkModeAngle\":90.237946,\"segmentRim27DarkModeEndLevel\":0.23693,\"segmentRim27DarkModeF" \
    "alloff\":3.474776,\"segmentRim27DarkModeHex\":\"#000000FF\",\"segmentRim27DarkModeOpacity\":0.8517,\"seg" \
    "mentRim27DarkModeSharpness\":5.057376,\"segmentRim27DarkModeWidth\":0.756373,\"segmentRim27EndLevel\"" \
    ":0.23693,\"segmentRim27Falloff\":3.474776,\"segmentRim27Hex\":\"#000000FF\",\"segmentRim27Opacity\":0.85" \
    "17,\"segmentRim27Sharpness\":5.057376,\"segmentRim27Width\":0.361897,\"segmentRimBrightness\":1,\"segme" \
    "ntRimFade\":0,\"segmentRimHex\":\"#FFFFFFFF\",\"segmentRimInward\":1,\"segmentRimOpacity\":0.4318,\"segmen" \
    "tRimSampleBrightness\":1,\"segmentRimSampleFade\":0.739014,\"segmentRimSampleOpacity\":0.4318,\"segmen" \
    "tRimSampleSoft\":1,\"segmentRimSampleSoftLevel\":0.5,\"segmentRimSampleSoftWidth\":0.8,\"segmentRimSam" \
    "pleWidth\":0.496249,\"segmentRimSoftLevel\":0.5,\"segmentRimSoftWidth\":0.8,\"segmentRimStyle\":1,\"segm" \
    "entSelectionInset\":2,\"segmentTitleSize\":14,\"segmentTitleWeight\":2,\"selectionHex\":\"#85858533\",\"se" \
    "lectionInset\":4.00067,\"selectionOpacity\":0.611066,\"settingsBackgroundHex\":\"#F2F2F7FF\",\"settingsD" \
    "arkBackgroundHex\":\"#1C1C1EFF\",\"syncBlurScale\":0.993364,\"syncCaptureScale\":3,\"syncDispersion\":tru" \
    "e,\"syncMeshRefraction\":true,\"syncPresent\":true,\"useWeChatIcons\":true,\"widthFraction\":0.898473},\"" \
    "integration\":{\"adaptiveIdle\":true,\"avatarTitle\":true,\"bubbles\":true,\"chatAvatarButton\":true,\"doc" \
    "k\":true,\"dockSearch\":false,\"dockSearchLeading\":false,\"edgeFade\":true,\"hideTopSearch\":true,\"input" \
    "\":true,\"localEmoji\":true,\"localNavButtons\":true,\"localPanel\":true,\"localSearch\":true,\"localSearc" \
    "hThemeFirst\":false,\"localSheet\":true,\"localTitle\":true,\"nativeInputTest\":false,\"nav\":true,\"sizeS" \
    "cale\":1.097522},\"ui\":{\"cardRadius\":26}}"
// FIX114 G: the defaults before this set (tools/bake_defaults.py keeps them):
// a phone's setting still at one of these moves to the new default once.
#define WXG_PREVIOUS_DEFAULT_OPTICS_JSON \
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
