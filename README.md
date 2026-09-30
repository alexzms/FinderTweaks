# FinderTweaks

给 macOS Finder 加功能的菜单栏小工具。所有改动集中在一个 App 里：授权一次，在菜单栏里逐项开关。

需要 macOS 14 或更高版本（在 macOS 26 Tahoe 上开发），只需要 Command Line Tools，不需要 Xcode。

## 功能

### 路径栏

盖在 Finder 窗口标题的位置，显示当前文件夹的完整路径。

- 路径太长时**从开头省略**，最后一段加粗：`…/2026/some-project/最终的文件夹`
- **单击编辑**：整条路径已选中，可以直接粘贴或改写
  - **回车**跳转；如果输入的是文件，会跳到它所在的文件夹并选中它
  - **Tab** 补全，有多个候选时显示在右侧
  - **Esc** 或点别处取消
  - 可以输入 `~`、相对路径（如 `..`）、从终端复制的带 `\ ` 的路径、`file://` 链接
- **拖动**路径栏可以移动窗口
- **右键**可以拷贝路径

路径栏会占满标题区域，也就是"返回/前进按钮"和"下一个工具栏按钮"之间的空间。

**紧凑搜索框**（默认开启，在菜单栏"路径栏"下面）：工具栏一有空位，Finder 就会把搜索框展开成约 300 宽的输入框，而且没有设置能改它的宽度。开启后：

- 平时：路径栏一直延伸到搜索框的位置，最右端只留一个短的"🔍 搜索"按钮。
- 点这个按钮或按 ⌘F：路径栏临时缩回去，露出 Finder 原生的搜索框。
- 搜索框清空并失去焦点后：路径栏重新伸长。

这需要搜索框紧挨在标题右边。第一次开启时，会提示你调整工具栏顺序并重启访达。

"Finder 设置"里的"窗口标题显示完整路径"请保持开启：在 macOS 26 上，路径栏是从窗口标题里读取路径的。

### Finder 设置

菜单栏里的"Finder 设置"子菜单，修改的是 Finder 自己的偏好设置，改完要重启访达才生效：

- 新窗口默认视图：图标、列表、分栏、画廊（对应 ⌘1 到 ⌘4）
- 窗口标题显示完整路径
- 显示隐藏文件
- 窗口底部显示路径栏、状态栏
- 排序时文件夹排在前面

## 安装

```bash
make cert      # 只需一次：在登录钥匙串里创建本地代码签名证书
make install   # 编译、签名、复制到 ~/Applications 并启动
```

第一次启动需要授予两项权限：

1. **系统设置 › 隐私与安全性 › 辅助功能**：打开 FinderTweaks。
2. 弹出"想要控制访达"时点**允许**。回车跳转要用到这项权限。

`make cert` 是可选的，但强烈建议执行。不执行的话 App 用临时签名，每次重新编译后 macOS 都会把它当成新程序，需要重新授权。

## 开发

```bash
make test       # 单元测试（swift-testing）
make snapshot   # 离屏渲染界面的各种状态到 build/snapshots/，不需要打开 Finder
make logs       # 跟踪诊断日志 ~/Library/Logs/FinderTweaks.log（只记录位置和尺寸，不记录文件夹名）
```

```
Sources/
  FinderTweaksCore/          通用部分，所有功能共用
    FinderTracker.swift      每秒 30 次读取当前 Finder 窗口（位置、路径、工具栏布局），推送给各功能
    ToolbarProbe.swift       通过辅助功能 API 读取工具栏布局，计算标题所在的空白区域
    Finder.swift             FinderScript（用 AppleScript 控制 Finder）、FinderPreferences（读写 com.apple.finder）
    AX.swift, Paths.swift, ScreenGeometry.swift, Log.swift
  FinderTweaks/              App 本体
    AppDelegate.swift        菜单栏图标、权限、登录时启动
    Feature.swift            功能模块协议
    Features/
      PathBar/               路径栏
      FinderSettings/        Finder 设置子菜单
Tests/FinderTweaksCoreTests/
scripts/                     build.sh、install.sh、create-signing-cert.sh
```

**添加一个新功能**：在 `Features/<名称>/` 下新建一个类型，实现 `Feature` 协议，然后加到 `AppDelegate.features` 列表里。需要跟随 Finder 窗口的功能，用 `tracker.observe { state in … }` 订阅窗口状态。

**微调路径栏位置**：不用重新编译，改完下一次刷新就生效：

```bash
defaults write io.github.alexzms.FinderTweaks pathBar.insetLeft -float 10   # 左右留白，默认 6（还有 insetRight）
defaults write io.github.alexzms.FinderTweaks pathBar.height -float 36      # 高度，默认跟工具栏按钮一样
defaults write io.github.alexzms.FinderTweaks pathBar.offsetY -float 1      # 上下偏移
defaults write io.github.alexzms.FinderTweaks pathBar.placement above       # 改为浮在窗口上方
```

## 原理与限制

- Finder 没有公开的、能往窗口里加界面的插件接口。路径栏是一个悬浮在 Finder 窗口上的独立面板：它用辅助功能 API 读取窗口位置和工具栏布局，用 AppleScript 让 Finder 跳转到指定文件夹。
- 右键菜单项、文件角标、工具栏按钮这类功能，需要 Apple 的 Finder Sync 扩展，而扩展必须用完整的 Xcode 构建。以后要加的话，放在单独的 `Extensions/` 目录下。
- Finder 在你第一次自定义工具栏之前，不会保存工具栏的按钮列表，所以本工具不会去改写工具栏。增删按钮请用 ⌘ 拖动。

## 卸载

1. 在菜单栏图标里选"退出 FinderTweaks"，然后删除 `~/Applications/FinderTweaks.app`。
2. 在系统设置的"辅助功能"和"自动化"里移除它。
3. 删除签名证书：`security delete-identity -c "FinderTweaks Local Signing"`
