HX1P35A 竞赛 · 双板 FPGA 全部代码（2026-11-01 打包）
==========================================================

器件：安路 PH1P35MDG324（speed 3），工具：Tang Dynasty (TD) V6.2.168116

两块板
------
1. upper_FPGA2_zoom30/   上板（FPGA-2）：双目摄像头 / HDMI 显示 / 40 种算法模式 / 远端视频接收 / YOLO 结果显示 / 云台 / 监控 OSD
   - 顶层：project/eth_stereo_raw_top1.v（module eth_stereo_raw_top1）
   - 约束：project/raw_signoff2.sdc（综合），project/physical_signoff1.sdc（布局布线），project/stereo.adc（管脚）
   - TD 流程脚本：project/whole/run.tcl -> project/place1/run.tcl -> project/route1/run.tcl -> project/bit1/run.tcl
   - 源码：project/rtl（自研模块），project/modes（单目算法模式），project/source（摄像头 / ISP / DDR / HDMI 参考工程与 IP），
           project/ethernet（以太网协议栈），project/control2
   - 比特流：bitstream/FPGA2_CLAUDE_ZOOM30.bit
     SHA256 fbe7d4bced50ac7ee40bbf607c81f8cf56bd6689718f5c87e439dcc2440b011f
     布线结果：Slice 20592/21216，ERAM 108/108，DSP 35/40，SWNS +0.114 ns，HWNS +0.020 ns，0 open net，DRC 通过
   - simulation/：本轮新增功能的仿真与模型（Verilator / Python）
       unit_lat  采集->显示延迟、CAP/DISP/LAG/LAT、SHOW/UDP FPS、UDP Mbps 统计与 OSD 渲染测试
       unit_z29  远端视频三缓冲接收（以太网/UDP 真包 + 接收 RTL）测试
       unit_z30  模式 48 模板跟踪（原始模板纠偏 + 纹理判定）RTL 与精确模型逐次比对

2. lower_FPGA1_CC24_PE16/   下板（FPGA-1）：摄像头 + YOLOv5n 硬件推理 + UDP 视频 / 检测结果发送（TF 卡加载模型）
   - 顶层：project/cc24_perf_20261031/input4/rtl/a2_camera_yolo_board_top.v（module a2_camera_yolo_board_top）
   - 约束：project/cc24_perf_20261031/input4/whole1/camera_yolo.sdc、camera_yolo.adc
   - TD 流程脚本：project/cc24_perf_20261031/input4/whole1/run.tcl -> phys1/placement.tcl -> phys1/route.tcl -> bit1/bitgen.tcl
   - 源码：project/cc24_perf_20261031/input4/rtl（YOLO / TF 加载 / 摄像头 / 网络），
           project/il3/source_snapshot/reference/user_source（摄像头 / ISP / DDR 参考工程与 IP）
   - 比特流：bitstream/CC24_PE16_ACCEL_20261031.bit
     SHA256 a1845afed593110a6e28ea8d9ddf07233178b7a3d65f543d9930a069eea2ccb7
   - 说明：YOLO 模型权重文件在 TF 卡上，由 FPGA 上电后读取，不在本压缩包内。

说明
----
- 两块板当前 Flash 中固化的就是以上两个比特流（2026-11-01）。
- TD 脚本中的源文件路径是开发机上的绝对路径（G:/anlogic/HX1P35A_Contest_202606/work/...）；在其他电脑上重新编译时，
  把脚本中的路径前缀替换为本压缩包内 project/ 目录的位置即可（相对目录结构保持不变）。
- 只包含源码、约束、流程脚本和最终比特流；综合 / 布局 / 布线的中间数据库（.db）和日志未包含。
- 加密 IP（*.enc.v / *.enc.sv）为安路官方 IP 原样文件。
