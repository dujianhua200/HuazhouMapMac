# 滑洲云图 Mac（HuazhouMap）

macOS 原生通信线路外业工具：**现场打点 → 自动连成杆路 → 算距离方位 → 一键导出 DXF 出图**。

纯 Swift / SwiftUI / MapKit，**零第三方依赖**，`swift build` 直出 `.app`，GitHub Actions 自动测试并产出安装包。

- 需求来源：分析 `奥维地图-SVIP9.exe` 的功能与实现后，聚焦「打点—连杆—出图」主线重写为 macOS 原生程序。
- [`docs/逆向分析报告.md`](docs/逆向分析报告.md) —— 目标软件的技术栈、功能矩阵、实现原理。
- [`docs/功能对照与路线图.md`](docs/功能对照与路线图.md) —— **298 个命令 vs 本项目的差距**与优先级路线。
- [`docs/结构组成分析.md`](docs/结构组成分析.md) —— 深度重做：941 个 RTTI 类、302 个对话框字段、模块分解与数据流。
- [`docs/测试与修复记录.md`](docs/测试与修复记录.md) —— 下载 CI 产物实测后**发现并修复的 9 个问题**（含 1 个裁切布局 bug、1 个数据丢失 bug、1 个性能问题）。

> 全部代码为原创实现，未复用原程序任何代码或资源。

## 功能（v2.1.0）

| 模块 | 说明 |
|---|---|
| 打点 | 地图单击落点；**手动输入经纬度**（支持粘贴 `32.1301, 114.0814`）；自动编号按类型给前缀（电杆 G、人孔 R、接头盒 J…） |
| 对象类型 | 电杆 / 人孔 / 接头盒 / 标石 / 跨越点 / 机房 / 其他；按类型配色、DXF 分图层 |
| 编辑 | 拖动标注改位、改点名、切类型、删除、清空 |
| 成链 | 「按打点顺序」或「自动最近邻成链」（野外乱序打点后自动排序） |
| 距离 | Vincenty 椭球大地线；逐段长度 / 累计 / 平均 / 总长 / 方位角 + 象限角；**闭合面积** |
| 坐标系 | 高斯-克吕格 3°带 / 6°带（自动分带或指定中央子午线）、本地平面、经纬度 |
| 纠偏 | WGS84 ↔ GCJ-02 正反算；显示层纠偏开关，对齐高德/腾讯瓦片（数据始终存 WGS84） |
| 导出 | **DXF R2000**（圆 + 多段线 + 杆号 + 段长，GB18030 不乱码，按类型分图层）、CSV 点表、KML、GPX |
| 导入 | CSV 点表（有/无表头、经度在前、带引号备注、GB18030）、KML（Point / LineString） |
| 底图 | Apple 标准/卫星/混合；自定义瓦片模板 + 高德/腾讯/天地图/OSM/本地服务预设 |
| **离线瓦片** | 本地缓存（`z/x/y.png`）+ 缓存优先读取；按当前视野、指定级别区间一键下载；缓存块数/占用/清空 |
| **等间距插杆** | 按档距在整条链路上自动插点，插前给出预计数量；距终点不足半档跳过 |
| 工程 | `.hzmap`（JSON），兼容 v1 工程（缺字段自动补默认值）；Finder 双击或拖到 Dock 图标即可打开，终端 `HuazhouMap 工程.hzmap` 亦可 |

## 构建与运行

要求 macOS 13+、Swift 5.9+（命令行工具即可，不需要完整 Xcode）。

```bash
swift test                      # 70 项单元测试（47 核心 + 23 状态机/自检）
./scripts/build_app.sh release  # 打包，产物在 dist/
open "dist/滑洲云图.app"

# 无头自检：直接跑打包后的二进制，验证打点/成链/存储/四种导出/导入/清空
"dist/滑洲云图.app/Contents/MacOS/HuazhouMap" --self-test
```

**只装了 Command Line Tools 时**（本机就是这种情况）需要两处额外处理：

1. SwiftPM 沙箱会被系统拒绝 → 加 `--disable-sandbox`：`swift build --disable-sandbox`。
2. `@State` 在新 SDK 里是宏（`SwiftUIMacros`），CLT 缺少该插件 → 本项目统一用 `@StateObject` + `@Published`，**不要用 `@State`**。
3. `swift test` 可能报 `TestingMacros ... plugin not found`（增量构建的插件路径问题）：**重跑不一定好使，`swift package clean` 一定好使**。

## GitHub Actions

`.github/workflows/build.yml`：push / PR / 手动触发时在 `macos-latest` 上

1. `swift test`（70 项：大地线、投影正反算、纠偏、几何量算、成链、DXF、CSV/KML 导入导出、工程文件，以及 18 项 AppState 端到端：打点/改位/删除/导入合并/导出落盘/保存后重读）
2. `./scripts/build_app.sh release` 打包 `.app`
3. **跑打包产物的 `--self-test`**（19 项：打点/成链/改位/中央子午线/保存重开/四种导出/导入改号/离线瓦片规划与缓存/等间距插杆/清空）
4. 校验 `Info.plist` 并上传 `HuazhouMap-macOS.zip`

## 目录

```
Sources/HuazhouCore/          纯逻辑库（可单测，无 UI 依赖）
  Geo.swift                   经纬度/平面坐标类型、WGS84 常数
  Geodesy.swift               Vincenty 反解、方位角、象限角
  TransverseMercator.swift    高斯-克吕格正反算（Snyder 级数）+ 分带
  Projection.swift            出图坐标系选择与批量投影
  CoordinateCorrection.swift  GCJ-02 正反算（纠偏）
  ObjectKind.swift            对象类型与图层/前缀
  ChainBuilder.swift          成链策略与分段统计
  Geometry.swift              折线长度、多边形面积、点在面内
  DXFWriter.swift             DXF R2000 生成（GB18030、分图层）
  CSVWriter.swift             点表导出
  KMLGPXWriter.swift          KML / GPX 导出
  TileCache.swift             离线瓦片：Web Mercator 换算 / 本地缓存 / 批量下载
  RoutePlanner.swift          等间距插杆（线路加密）
  Importers.swift             CSV / KML 导入
  SurveyProject.swift         工程模型（Codable，向前兼容）
Sources/HuazhouAppCore/       可测的应用状态机（不含视图）
  AppState.swift              状态、缓存成链、文件、导入导出、纠偏
Sources/HuazhouMap/           macOS 界面
  SurveyMapView.swift         MKMapView 封装（打点、拖动、标注、多段线、自定义瓦片）
  ContentView.swift           侧栏（点位/分段/设置）+ 地图 + 状态栏 + 手动输入表单
Tests/HuazhouCoreTests/       36 项核心算法测试
Tests/HuazhouAppCoreTests/    19 项状态机端到端测试 + 自检
docs/                         逆向分析报告 + 功能对照与路线图
```

## DXF 使用说明

- **坐标约定**：DXF 的 `X = 东坐标(easting)`，`Y = 北坐标(northing)`（与 CAD 图纸一致；测绘习惯写作 `X=北, Y=东`，本项目界面与 CSV 用 `N/E` 标明）。
- **带号**：东坐标只含 500000 伪偏移，**不加带号前缀**（否则图形整体偏 3800 万米）。带号只在界面提示。
- **图层**：按对象类型分层（电杆/人孔/接头盒/标石/跨越点/机房/其他）+ `线路` + `杆号` + `段长标注`。
- **符号尺寸**：杆符号半径默认 0.5 m、文字高 1.5 m，出 1:500 图约 1 mm / 3 mm，可在「设置」改。

## 已知限制

- 无离线瓦片缓存、无图片附件、无 GPS 采集、无轨迹记录、无云同步（见路线图 P0/P1）。
- 只写 DXF，不读 DWG；DXF 只导出，不导入（P0 计划补）。
- 底图默认走 Apple 地图；国内第三方瓦片需自备源并开启纠偏。

## 手动自测清单

1. 启动 → 地图定位信阳（32.1301, 114.0814）。
2. 点 4 下 → G001~G004，红色多段线连通，状态栏显示总长与闭合面积。
3. 拖动任一标注 → 段长、方位角、面积实时变化。
4. `⌘⇧P` 手动输入 `32.1301` / `114.0914` → 新点插入列表。
5. 「导入 ▾ → 从 CSV 导入」选一份 `点名,纬度,经度` 表 → 点名/备注保留。
6. 设置里切「高斯-克吕格 3 度带」→ 显示「第 38 带，中央子午线 114°」。
7. `⌘E` 导出 DXF → CAD/CASS 打开 `ZOOM E`，应见按类型分层的圆 + 杆号 + 线路 + 段长。
8. 「其他格式 ▾」导出 KML → Google Earth/手机地图能打开且位置正确。
9. `⌘S` 保存 `.hzmap`，`⌘O` 重开，点位与设置不丢（含中央子午线）。
10. 在 Finder 里双击 `.hzmap`，应用应直接载入该工程。
