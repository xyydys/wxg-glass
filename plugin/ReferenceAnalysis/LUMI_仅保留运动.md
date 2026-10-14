# 仅保留 LUMI 的展开后运动形变

沿用上一版已静态核实的 `LGTabBarBackgroundView updateThumbElasticityWithDeltaTime:`（0x378194）公式。来源原二进制 SHA-256：ec3224f40ce1c8e9e94d670724e5e118c8c444d4e1c433f8b82322c1e3eeef67。

保留：速度绝对值与加速度滤波 dt/(dt+1/55)、speedFactor=1-exp(-speed/300)、加/减速归一化 7000/5200、drive 的 0.85/0.15/1.35 系数、log1p(0.34×drive)、伸缩弹簧 121/9.24、log(0.78)…log(1.391) 限幅、负形变时 exp(-0.78×stretch) 的增高规律。

撤回：LUMI 的 activeScale、log(1.28)/log(1.4) 呼出尺度、按路程收回、静置/按压 alpha 交叉渐变、LUMI 光学倒角及边缘留白。着色器恢复 TEST9，位置与按压弹簧恢复 TEST9。

适配：在 TEST9 按压进度 65%～100% 间用 smoothstep 接入形变；正形变的竖向压缩按 TEST9 透镜的原始高度归一化到当前底栏高度。原生点击、纵向中心、屏幕与画布边界保持原工程逻辑。这是指定部分的移植，不是 LUMI 全部运动系统的复制。
