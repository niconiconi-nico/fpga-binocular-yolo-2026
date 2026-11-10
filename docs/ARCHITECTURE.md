# 架构、源码导读与板间协议

下文路径均相对仓库根目录。两个顶层和其 analyze 列表是生产配置依据，不以未实例化的历史模块推断功能。

## FPGA-1：采集、YOLO 推理、以太网发送

主要目录 `FPGA_two_boards_20261101/lower_FPGA1_CC24_PE16/project/cc24_perf_20261031/input4/rtl`：

| 模块 | 作用 |
|---|---|
| `a2_camera_yolo_board_top.v` | 采集、DDR、推理、视频/检测发送总集成 |
| `v5n_fixed_graph_accelerator.sv` | YOLO 固定计算图硬件加速器 |
| `v5n_fixed_graph_scheduler.sv` | 图调度与描述符 |
| `r10_tf_source.sv` | TF 模型加载控制及就绪交接 |
| `tf_fat32_file_context.sv` | FAT32 元数据/文件控制 |
| `tf_model_stream_loader.sv` | 模型头校验和数据流加载 |
| `camera_yolo_detection_tx.sv` | Y5CD 检测记录打包 |
| `camera_awb_frame_gain.sv` | 摄像头颜色与 tone 处理 |

网络配置来自 `project/il3/source_snapshot/camera/generated/camera_video_config.vh`：

- 板端源 IP：`192.168.240.1`。
- 目的 IP：`192.168.240.2`。宏名仍叫 `NET_PC_IP`，在双板系统中目的角色是接收板，不能据宏名误认为必须由 PC 推理。
- 配置端口 `NET_VIDEO_PORT = 6003`。
- 视频为 1280×720、RGB565 大端像素，单帧 1,843,200 字节；视频头 32 字节，配置数据分片 636 字节。
- 使用 UDP，需要解析有效帧与分片、完整性及帧号；不能把任意 UDP 数据直接写成一帧。

## FPGA-2：双源显示与共享算法硬件

目录 `FPGA_two_boards_20261101/upper_FPGA2_zoom30/project`：

| 模块 | 作用 |
|---|---|
| `eth_stereo_raw_top1.v` | 上板生产顶层与模式/云台接入 |
| `rtl/checked_media_ethernet_rx3.sv` | 以太网接收与校验入口 |
| `rtl/video_udp_receiver.sv` | 视频 UDP 解析及帧状态 |
| `rtl/remote_media_ingress5.sv` | 远端媒体写入交接 |
| `rtl/stereo_raw_memory1.sv` | 本地/远端 DDR 缓冲管理 |
| `rtl/stereo_raw_reader1.sv` | 显示读取与坐标处理 |
| `rtl/vision_core.sv` | RANGE / DEPTH / TEMPLATE / MOTION 的共享图像存储与模式调度 |
| `rtl/range_meter.sv` | 模板匹配、局部双目搜索；track_only 模式为单目跟踪 |
| `rtl/depth_map.sv` | 双目视差图 |
| `rtl/color_cells.sv` + `rtl/blob_engine.sv` | 颜色条件命中、32×32 单元统计与区域选择 |
| `rtl/motion_cells.sv` + `rtl/blob_engine.sv` | 跨帧差分与运动区域框 |
| `rtl/y5cd_tracks1.sv` | 检测记录校验、类别/置信度/BBox 缓存、显示关联 |
| `rtl/yolo_box_overlay1.sv` | 检测框、类别文字、置信度等叠加 |
| `rtl/bottle_seed.sv` | 使用检测结果初始化 BOTTLE 模板跟踪 |
| `rtl/gimbal_lite.sv` + `rtl/gimbal_mc.sv` | 跟随状态与电机串口控制 |
| `rtl/latency_meter5.sv` | 内部延迟、帧计数和速率统计 |
| `rtl/common_logo1.sv`、`rtl/vision_osd.sv` | Logo 与算法状态叠加 |
| `modes/mono_algorithms4.sv`、`mono_window2.sv` | 基础图像算法及窗口共享 |
| `modes/mode_tables.vh`、`mono_keys1.sv` | 实际可达模式与按键切换 |

## Y5CD 实际报文

来源是下板 `camera_yolo_detection_tx.sv` 的 `payload_byte`，接收端是上板 `y5cd_tracks1.sv`。以下偏移从 **UDP payload 第 0 字节**计算，不包括 Ethernet/IP/UDP 头。

| 偏移 | 长度 | 内容 / 格式 |
|---:|---:|---|
| 0 | 4 | ASCII `Y5CD` |
| 4 | 1 | 版本 1 |
| 5 | 1 | 类型：1 检测记录，2 帧汇总 |
| 6 | 1 | 标志，发送端设为 1（STRICT_AI） |
| 7 | 1 | 保留，0 |
| 8 | 4 | frame_id，uint32，小端 |
| 12 | 2 | count，uint16 小端，最多 300 |
| 14 | 2 | index，uint16 小端 |
| 16 | 4 | latency_cycles，uint32 小端；不是直接的毫秒 |
| 20 | 2 | ROI 宽 1024，小端 |
| 22 | 2 | ROI 高 600，小端 |
| 24 | 2 | 网络输入宽 320，小端 |
| 26 | 2 | 网络输入高 320，小端 |
| 28 | 4 | 保留，0 |
| 32 | 1 | class_id：0 PERSON，1 CAR，2 CHAIR，3 BOTTLE |
| 33 | 2 | confidence，uint16 小端，Q15，合法值 ≤32768 |
| 35 | 4 | x1，有符号 32 位 Q16，小端 |
| 39 | 4 | y1，有符号 32 位 Q16，小端 |
| 43 | 4 | x2，有符号 32 位 Q16，小端 |
| 47 | 4 | y2，有符号 32 位 Q16，小端 |

类型 1 长度 **51 字节**；类型 2 长度 **32 字节**，不携带单框字段。接收端按一组有序检测记录与最后汇总提交，不把半组结果立即替换上屏。

坐标不能直接当作 HDMI 坐标：接收端 `map_x/map_y` 对 ROI、缩放/letterbox 做映射并裁剪到 1280×720。视频头中的全帧尺寸与 Y5CD 的 1024×600 ROI 尺寸不是冲突。

上板显示缓存每条 80 位，包含 x1/y1/x2/y2、16 位 confidence、2 位 class、ID、valid 与 observed。显示选取置信度较高的最多 4 项；**最多 300 条协议记录不等于同时画 300 个框**。置信度最低显示阈值默认 8192（Q15 的 25%）。

提交版已经有类别名称/置信度文字绘制；不能沿用早期“只有 BBox，没有标签”的描述。检测结果按帧号关联，存在带标识的延迟显示/保持；这不等于每个视频帧都完成了同帧推理。

## 跟踪、视差与测量的区别

- TEMPLATE 使用 `range_meter` 的 track_only 分支，从当前图像捕获 32×32 灰度模板，在局部窗口内匹配；提交版含锚点与纹理相关处理。它不是 YOLO 分类器。
- COLOR 根据 RGB 强度和通道差值分割，统计区域并选框；相似颜色、遮挡和光照改变仍会影响效果。
- MOTION 比较当前/历史图像，并包含整体亮度偏移处理；摄像机运动、曝光变化或纹理边缘可能影响运动框，它不是语义目标识别。
- 双目测距/DEPTH 依赖左右图像和安装标定。左右 FID 不证明曝光同步；仓库里的距离表/经验映射仅适用于当时装配，不能承诺换板换镜头后的厘米精度。
- LAT 以采集帧标记和显示选择事件计算，按 10 个显示帧平均；SHOW FPS 只计显示了新相机帧的次数，重复帧不计。该测量不包含显示器光学响应。
