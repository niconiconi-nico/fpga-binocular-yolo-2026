# 构建与复现

## 软件与工程基线

- 安路 TD V6.2.168116，器件库包含 `ph1_35p.db`；器件 PH1P35MDG324，speed 3。
- Python 3 用于本仓库路径迁移工具；该工具仅使用标准库。
- 部分独立仿真使用 Linux/WSL、Verilator、C++ 编译工具及 Python NumPy；厂商加密 IP 的整机仿真需相应厂商支持的仿真器/库。
- 原始快照位于 `FPGA_two_boards_20261101`。HDL 中部分中文注释保留原编码，不要对全工程批量转码。

## 生成可迁移构建副本

原 TCL、Verilog include 和 ROM 路径含作者机器上的绝对路径。不要直接运行原目录里的 TCL。

```powershell
python tools/prepare_build.py --output build/local
```

输出目录必须不存在。工具按字节替换两个已知工程前缀，保留原 RTL 算法、IP、时钟约束、频率和布局布线选项；同时在构建副本中修正下板两个跨目录 checkpoint 导入路径。原快照和原 bit 不改动。

准备完成后会检查 TCL 中的源文件、include 与 ADC/SDC 输入，及下板四个初始化 ROM。**路径检查通过只表示静态输入存在，不等于综合或时序通过。**

## 上板 FPGA-2

构建根目录：`build/local/upper_FPGA2_zoom30/project`

| 顺序 | TD 执行脚本 | 主要产物 |
|---|---|---|
| 1 | `whole/run.tcl` | `whole/local_gate.db`、综合资源/时序 |
| 2 | `place1/run.tcl` | `place1/place_pre_reports.db` 等 placement checkpoint |
| 3 | `route1/run.tcl` | `route1/final.db`、最终报告 |
| 4 | `bit1/run.tcl` | `bit1/FPGA2_CLAUDE_ZOOM_ENGINEERING.bit` |

顶层：`eth_stereo_raw_top1`。引脚：`stereo.adc`。综合约束：`raw_signoff2.sdc`；物理约束：`physical_signoff1.sdc`。脚本进入自身目录，使用 TD 的 Tcl 批处理入口依次运行，例如在正确安装的 TD 命令环境中执行 `td -script <脚本绝对路径>`；可执行文件名称/路径按本机安装确认。

## 下板 FPGA-1

构建根目录：`build/local/lower_FPGA1_CC24_PE16/project/cc24_perf_20261031/input4`

| 顺序 | TD 执行脚本 | 主要产物 |
|---|---|---|
| 1 | `whole1/run.tcl` | `whole1/camera_yolo_gate.db` |
| 2 | `phys1/placement.tcl` | `phys1/own_place.db` |
| 3 | `phys1/route.tcl` | `phys1/own_final.db`、最终报告 |
| 4 | `bit1/bitgen.tcl` | `bit1/CC24_PE16_ACCEL_20261031.bit` |

顶层：`a2_camera_yolo_board_top`。`whole1/camera_yolo.adc` 与 `whole1/camera_yolo.sdc` 定义引脚/时序。基础摄像头及 IP 源码在同级工程树的 `il3/source_snapshot`，不要只复制 input4。

原流程由外部脚本把 `camera_yolo_gate.db` 复制到 phys1，把 `own_final.db` 复制到 bit1。迁移工具仅在构建副本里把这两个 import 改成相对路径，因此不需要人工复制 DB。

### 补齐的 ROM 文件

原 RAR 未收录以下文件。本仓库从对应生产 `input4/whole1` 原样补入并加入 SHA256SUMS：

| 文件 | 用途 |
|---|---|
| `cc9_tone_lut.hex` | 颜色处理 tone LUT |
| `fat_program3.hex` | TF/FAT32 控制微程序 |
| `flash_model_header.hex` | 模型加载器预期头信息 |
| `numeric_context1.hex` | 数值上下文微程序 |

RTL 使用相对 `$readmemh` 路径，综合脚本切换到 whole1 后读取这些文件。单独运行相关仿真时也要把 ROM 放到仿真工作目录或显式传参。

### TF 模型依赖

`tf_fat32_file_context.sv` 默认期望模型文件长度为 **1,816,576 字节**。`tf_model_stream_loader.sv` 使用头 ROM 校验模型；这不是通用 ONNX/PT 模型加载器。需要原系统对应的 FAT32 TF 模型包和固件约定。本次公开包没有完整权重、训练代码或 TF 卡镜像，因而没有把 YOLO 整机运行写成开箱即用。视频和检测协议源码可以独立研究。

## 仿真入口与边界

上板 `simulation/unit_lat`、`unit_z29`、`unit_z30` 保存局部测试与模型比较源码。部分 `.sh` 是开发阶段脚本，包含 WSL 路径转换、不同历史候选对比或外部生成文件；不能把所有 run 脚本当成当前版本的一键全回归。

`unit_z30/run_rm.sh` 接收 tag、`range_meter.sv` 路径和更新次数，构建 Verilator 测试；`scene.py` 生成场景，`check_rtl.py` 用 NumPy 模型比较 RTL 日志中的中心坐标和 lock。先检查各脚本参数与数据文件路径，按同一场景/同一源码运行。

本仓库未提供完整训练集、所有历史 12 帧 DDR 仿真日志或全套板测采集数据；不能仅凭已有测试文件宣称整机完整回归已重跑通过。

## 重新构建后的验收

每阶段必须检查退出码和实际报告，失败时停止后续阶段。生成 bit 前至少重新检查最终 Setup/Hold、未布线网络、DRC、IO、时钟及 CDC 约束与实际结构。bitgen 成功不自动代表全部验收通过；原 TCL 的 DONE 字样也不能替代报告。

不同 TD 版本、源文件、约束或布局布线条件可能产生不同 bit 和时序。不要为匹配本仓库数字修改约束或跳过检查。
