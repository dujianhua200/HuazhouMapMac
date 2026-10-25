# 滑洲云图 Mac（HuazhouMap）

macOS 原生通信线路外业工具：**现场打点 → 自动连成杆路 → 算距离方位 → 一键导出 DXF 出图**。

纯 Swift / SwiftUI / MapKit，**零第三方依赖**，`swift build` 直出 `.app`，GitHub Actions 自动测试并产出安装包。

> 需求来源：分析 `奥维地图-SVIP9.exe` 的功能与实现后，只保留「打点—连杆—出图」这条主线，重写为 macOS 原生程序。
> 分析过程与结论见 [`docs/逆向分析报告.md`](docs/逆向分析报告.md)。全部代码为原创实现，未复用原程序任何代码或资源。

## 功能

| 模块 | 说明 |
|---|---|
| 打点 | 地图单击即落点，自动命名 `G001…`，可改点名/备注 |
| 成链 | 「按打点顺序」或「自动最近邻成链」（野外乱序打点后自动排成一条杆路） |
| 距离 | Vincenty 椭球大地线，逐段长度 / 累计长度 / 方位角 + 象限角（如 `北偏东 34°33'`） |
| 坐标系 | 高斯-克吕格 3°带 / 6°带（自动分带或指定中央子午线）、本地平面（以首点为原点）、经纬度 |
| 出图 | DXF R2000，图层：`电杆`(圆) / `杆号`(文字) / `线路`(多段线) / `段长标注`(文字)，GB18030 编码不乱码 |
| 点表 | CSV（UTF-8 BOM，Excel 直接打开），含经纬度、N/E 坐标、段长、累计、方位角、备注 |
| 工程 | `.hzmap`（JSON），可保存/打开 |
| 底图 | 标准 / 卫星 / 卫星混合，或填自己的瓦片服务 URL 模板 |

## 构建与运行

要求 macOS 13+、Swift 5.9+（命令行工具即可，不需要完整 Xcode）。

```bash
# 跑测试
swift test

# 编译并打包成 .app（产物在 dist/）
./scripts/build_app.sh release

# 启动
open "dist/滑洲云图.app"
```

> 本机若只装了 Command Line Tools，SwiftPM 的沙箱可能被系统拒绝，此时加 `--disable-sandbox`：
> `swift build --disable-sandbox` / `swift test --disable-sandbox`。

## GitHub Actions

`.github/workflows/build.yml`：push / PR / 手动触发时在 `macos-latest` 上

1. `swift test`（23 项单元测试：大地线、投影正反算、成链、DXF、CSV、工程文件）
2. `./scripts/build_app.sh release` 打包 `.app`
3. 校验 `Info.plist` 并上传 `HuazhouMap-macOS.zip` 为构建产物

## 目录

```
Sources/HuazhouCore/          纯逻辑库（可单测，无 UI 依赖）
  Geo.swift                   经纬度/平面坐标类型、WGS84 常数
  Geodesy.swift               Vincenty 反解、方位角、象限角
  TransverseMercator.swift    高斯-克吕格正反算（Snyder 级数）+ 分带
  Projection.swift            出图坐标系选择与批量投影
  ChainBuilder.swift          成链策略与分段统计
  DXFWriter.swift             DXF R2000 生成（GB18030）
  CSVWriter.swift             点表导出
  SurveyProject.swift         工程模型（Codable）
Sources/HuazhouMap/           macOS 界面
  AppState.swift              状态与文件/导出动作
  SurveyMapView.swift         MKMapView 封装（点击打点、标注、多段线、自定义瓦片）
  ContentView.swift           侧栏（点位/分段/设置）+ 地图 + 状态栏
Tests/HuazhouCoreTests/       单元测试
docs/逆向分析报告.md           目标软件的功能与原理分析
```

## DXF 使用说明

- **坐标约定**：DXF 的 `X = 东坐标(easting)`，`Y = 北坐标(northing)` —— 与 CAD 图纸习惯一致（注意：测绘习惯写作 `X=北, Y=东`，本项目在界面与 CSV 里用 `N/E` 标明，避免混淆）。
- **带号**：东坐标只含 500000 伪偏移，**不加带号前缀**（否则图形会整体偏移 3800 万米）。带号只在界面/CSV 里提示。
- **符号尺寸**：杆符号半径默认 0.5 m、文字高 1.5 m，出 1:500 图约 1 mm / 3 mm，可在「设置」里改。
- 打开后如看到图很小/很大，先 `ZOOM E` 或检查插入单位（文件已写 `$INSUNITS = 6` 即米）。

## 已知限制

- 底图用 Apple 地图，国内显示与坐标偏移由系统处理；不提供离线瓦片下载（瓦片版权原因），需要自有离线源时用「自定义瓦片 URL」。
- 只导 DXF，不读写 DWG（DWG 为封闭格式）。
- 打点目前只有「地图单击」一种录入方式，未做 GPS 实时采集与照片附件。

## 手动自测清单

1. 启动 → 地图定位到信阳（32.1301, 114.0814）。
2. 在空地上点 4 下 → 左侧出现 G001~G004，红色多段线连起来，状态栏显示总长。
3. 切「分段」→ 每段有长度、累计、方位角。
4. 切「设置」→ 坐标系选 3°带，中央子午线留空 → 显示「第 38 带，中央子午线 114°」。
5. ⌘E 导出 DXF → 用 CAD/CASS 打开，`ZOOM E` 应看到 4 个圆 + 杆号 + 线路 + 段长。
6. ⌘S 保存 `.hzmap`，⌘O 重新打开，点位与设置不丢。
