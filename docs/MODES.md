# 40 种模式与编号

本表按提交版 `modes/mode_tables.vh` 的实际 next_mode 循环生成，名称取自 `mode_catalog.vh`。屏幕编号连续为 1–40，内部 ID 保留历史接口，因此不能直接用屏幕编号去比较 RTL 的 active_mode。

| 屏幕编号 | 内部 ID | OSD 名称 | 功能 |
|---:|---:|---|---|
| 1 | 1 | ORIGINAL | 原图 |
| 2 | 2 | GRAY | 灰度 |
| 3 | 3 | BINARY | 二值化 |
| 4 | 4 | INVERT | 反色 |
| 5 | 5 | RED | 红色通道 |
| 6 | 6 | GREEN | 绿色通道 |
| 7 | 7 | BLUE | 蓝色通道 |
| 8 | 8 | BRIGHT | 亮度增强 |
| 9 | 9 | CONTRAST | 对比度 |
| 10 | 10 | GAMMA | Gamma 查找表 |
| 11 | 11 | MEAN | 均值滤波 |
| 12 | 12 | GAUSS | 高斯滤波 |
| 13 | 14 | SHARPEN | 锐化 |
| 14 | 15 | LAPLACE | 拉普拉斯 |
| 15 | 16 | SOBEL-X | 水平 Sobel |
| 16 | 17 | SOBEL-Y | 垂直 Sobel |
| 17 | 18 | SOBEL | Sobel 边缘 |
| 18 | 19 | EDGE | 边缘二值 |
| 19 | 20 | ERODE | 腐蚀 |
| 20 | 21 | DILATE | 膨胀 |
| 21 | 24 | EMBOSS | 浮雕 |
| 22 | 25 | SKIN | 肤色提取 |
| 23 | 26 | CHROMA | 色度处理 |
| 24 | 27 | DIAG EDGE | 斜向边缘 |
| 25 | 29 | HEATMAP | 热力伪彩 |
| 26 | 30 | EDGE RGB | 彩色边缘 |
| 27 | 31 | ADAPTIVE | 自适应阈值 |
| 28 | 32 | POSTER | 色阶海报 |
| 29 | 33 | SEPIA | 复古色调 |
| 30 | 34 | SOLAR | 曝光反转风格 |
| 31 | 35 | SKETCH | 素描 |
| 32 | 36 | CARTOON | 卡通 |
| 33 | 37 | STEREO | 双目显示 |
| 34 | 38 | YOLO ONLY | YOLO 检测显示；K4 切 ALL/BOTTLE |
| 35 | 45 | RANGE | 局部双目测距 |
| 36 | 47 | DEPTH | 视差/深度显示 |
| 37 | 48 | TEMPLATE | 灰度模板捕获与跟踪 |
| 38 | 49 | COLOR | 颜色分割与区域跟踪，K4 切红/绿/蓝 |
| 39 | 50 | MOTION | 跨帧运动检测 |
| 40 | 51 | ZOOM | 数字缩放，K4 操作 |

例如视频中的 **31 SKETCH** 对应内部 ID **35**；本交付版 **37 TEMPLATE** 对应内部 ID **48**。较早 zoom8 或单模式工程中的“35 TEMPLATE”不是本次提交版编号。

13 MEDIAN、22 OPEN、23 CLOSE、28 BIN MATCH 等历史定义仍可出现在文件中，但不在本版本按键可达列表；不能据源码字符串把它们算成额外可用模式。

算法资源以模式互斥方式复用。TEMPLATE、COLOR 可接跟随；MOTION 主要显示运动区域，不应当成带类别识别的跟随模式。缩放模式是图像缩放，不是另一个模板匹配器。
