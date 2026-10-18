---
name: desktop-takeover
display_name: "Desktop Takeover（桌面接管编排）"
display_name_en: "Desktop Takeover"
version: "1.3.1"
author: "冯金岳 (Feng Jinyue)"
license: MIT
description_zh: "桌面 GUI 操作的统一编排入口：路由决策（连接器/浏览器/Office/命令行/computer use 五级判断）、macOS 授权引导（含实测踩坑处理）、任务三段式派发与截图验收。"
description_en: "Orchestration entry for desktop GUI operations: 5-level routing (connector/browser/Office/CLI/computer use), macOS permission onboarding with tested pitfalls handling, and task dispatch with screenshot-based verification."
description: "桌面 GUI 操作的统一编排入口。当用户要求操作一个只有图形界面的应用（改设置、点按钮、填表单、操作无 CLI/连接器的软件）时使用此 skill。提供四级能力：①路由决策——判断任务该走连接器、浏览器控制、Office 技能、命令行还是 computer use 桌面接管；②授权引导——检测并引导用户完成 macOS 辅助功能/屏幕录制权限授权，处理授权不生效等常见坑；③任务派发与验证——按目标/边界/失败处理三段式描述派发 GUI 任务，并以最终截图为准确认结果；④AX 兜底层——内置 axctl 工具做元素级无障碍读写（AXPress 语义点击，不碰鼠标不抢焦点），适用于 computer use 不可用或轻量场景。台前调度全场景实测（macOS 15 + 27.0.1 复检）。触发词：操控电脑、操作某个软件、点某个按钮、GUI 操作、电脑设置。"
tags: [computer-use, gui, desktop-automation, macos, orchestration]
---

# Desktop Takeover

## Overview

统一编排"让 Agent 接管桌面完成 GUI 操作"的全流程：先路由判断最优通路，再确保 computer use 权限就绪，最后派发任务并验证。computer use 是兜底通路而非首选通路——仅当任务必须通过 GUI 完成时才使用。

## Workflow Decision Tree

接到桌面操作类请求时，按以下顺序判断通路，**命中即停**：

```
1. 连接器/MCP 可直达？
   目标应用有已连接的连接器（GitHub、WPS 知识库、企业微信等）
   → 走连接器，不碰 GUI
   例：查 GitHub PR → gh 连接器；读 WPS 库文档 → wps-knowledgebase

2. 纯浏览器操作？
   任务发生在网页上（填表单、网页点击、截图比对）
   → 走 browser-use 技能，不动系统 GUI
   例：登录某网站改设置 → browser-use

3. Office/WPS 文件读写？
   目标是 doc/docx/xls/xlsx/ppt/pptx 文件内容
   → 走 office 技能族（workbuddy-docx / sheetagent / local-office-edit）
   例：改 Word 里的表格 → local-office-edit

4. 命令行/脚本可达？
   任务本质是文件操作、数据处理、系统配置，且有 CLI 或脚本通路
   → 直接用 Bash/脚本
   例：批量重命名 → 脚本；查系统信息 → 命令

5. 以上全部不通 → computer use 桌面接管
   任务必须操作某个 GUI 应用的界面元素（按钮、菜单、非网页窗体）
   例：某国产软件里改一个只有 GUI 入口的设置项
```

判断原则：**每往下一级，可靠性和速度都在下降，不确定性在上升**。GUI 操作涉及元素定位、窗口焦点、界面语言等多重不确定性，是最后手段。

> 注意：第 5 级的可见性依赖（窗口枚举 + 截图）在台前调度开启时是**结构性短板**（见 Pre-flight 第 2 项与「不可见窗口陷阱」）。AX 系工具（无障碍树感知）读取的是**逻辑几何**，不受台前调度缩略位移欺骗，是替代/补充通路——27.0.1 复检已部分证实（详见陷阱小节发现 5），限定条件：全新启动、从未上过舞台的窗口 AX 树同样看不见。本 skill 内置的 AX 兜底工具：`tools/axctl`（用法见「AX 兜底层」章节）。

路由时如不确定目标应用是否有连接器，先查 `list_installed_plugins`，不要凭记忆断言。

## Pre-flight: 权限与环境双预检

走 computer use 前必须完成两项预检，**缺一不可跳过**：

### 1. 权限检查

调用 `gui_permission_status`：

- `all_granted: true` → 进入第二项预检
- 缺权限 → 按 references/authorization-macos.md 的流程引导用户授权（macOS）
- Windows → 当前版本仅支持 macOS，明确告知用户

### 2. 台前调度预检（必做，用户台前调度常开）

执行 `defaults read com.apple.WindowManager GloballyEnabled`：

- 返回 `1`（开启）→ **派发前必须先 `open -a <应用名>` 激活目标应用**使其回到当前舞台（会短暂抢焦点，先告知用户），再 `gui_list_windows` 确认目标窗口可见，最后才 `create_task`。若激活后窗口仍不在列表，直接进入下方「不可见窗口陷阱」排查序列——**不要**重试 `create_task`，**不要**断定应用故障
- 返回 `0`（关闭）→ 直接走正常派发流程

此项预检把台前调度陷阱从「事后诊断」升级为「事前绕开」。台前调度在 macOS 15+ 用户中并不少见，对开启者这条是**每次派发的默认路径**，不是特例。激活-显形机制已于同日在 macOS 27.0.1 上复验成立，但存在「首次激活不粘住」与「显形后回缩」两个新细节，详见「不可见窗口陷阱」的 27 复检小节。

## 任务派发

权限就绪后，按内置 computer use 技能的标准工作流执行：

1. `gui_list_windows` 定位目标应用窗口；未命中则 `open_app` 启动
2. **启动后验证可见性**：`open_app` 后必须再次 `gui_list_windows` 确认窗口真的出现在列表中。未出现时不要急着下结论"应用坏了"，先看下方"不可见窗口陷阱"
3. 台前调度开启时（预检已确认）：**先 `open -a` 激活目标应用再派发**——见 Pre-flight 第 2 项，此处不重复判断
4. `create_task(window_id, task)` 派发任务

### 不可见窗口陷阱（台前调度场景）

**结论适用范围**：macOS 15 对照实验首次建立；**已在 macOS 27.0.1 上复检复验**（Swift 双通道探针 + AX API 原生二进制实测，机制成立且发现新增细节，见下）。AX 层结论已由 27.0.1 授权后实测确认（AXError=0 通路），不再依赖推断。

**触发条件**：台前调度（Stage Manager）激活，与后台启动本身无关。开启时，未上当前舞台的应用窗口**真实存在但无法被窗口枚举和截图正常捕获**——进程活着、窗口已创建（如 Cmd+N 生效了），但 `gui_list_windows` 看不到正常窗口。一旦激活应用（窗口回到当前舞台），窗口立即显形。

**macOS 27.0.1 复检新发现**：

1. **缩略条机制可视化**：下场应用的窗口被缩成侧边缩略小窗（实测 Calculator 主窗被缩至 39×100pt 贴左缘，另派生 4 个全宽 34pt 的舞台占位窗）。`gui_list_windows` 若按"正常尺寸窗口"过滤，这类缩略窗可能被漏检或误判
2. **激活显形仍然成立，但存在「首次激活不粘住」现象**：实测第一次 `open -a` 后主窗仍处缩略态（前台被其他应用占用时），第二次 `open -a` 才扩为全尺寸 (405, 517, 230×408)。**处置：激活后必须立即 `gui_list_windows` 验证，未显形则再次 `open -a`（最多 2 次），仍未显形才进入排查序列**
3. **显形后可能回缩**：前台被其他应用抢回后约 5 秒内，窗口可重新缩回缩略态（实测复现）。**推论：截图验收存在时间窗——`create_task` 执行期间前台被抢时，任务本身不受影响，但 `gui_screenshot` 若在回缩后拍摄，目标窗口将不在画面中**。处置：截图前若刚发生前台切换，先 `open -a` 再拍
4. **CGWindowList 通道不受影响**：`optionOnScreenOnly` 与全量列表均能枚举到窗口（仅标题需屏幕录制权限）——但注意 onScreenOnly 列表里出现的是**缩略窗**，不是主窗。依赖窗口坐标做点击定位的工具会点错位置（点到缩略图而非真实按钮）
5. **AX 树读逻辑几何，对缩略位移免疫，但有盲区**（授权后 27.0.1 实测）：AX 返回的 window frame 是全尺寸逻辑坐标（如 (405,517,230×408)），同一时刻 CGWindowList 渲染态是 39×100 缩略窗——台前调度的几何位移骗不过 AX。**但盲区：全新启动、从未上过舞台的窗口，AX 树报 windows=0**；上过舞台后再后台启动，AX 持续可见。推论：AX 感知也不是无条件免疫，首次启动的app仍需先激活上舞台。另：按 AX 逻辑坐标向屏幕打合成鼠标事件会点错应用（逻辑位置 ≠ 当前渲染位置）——AX 系工具做动作必须走 AXPress 等无障碍动作 API（如 axctl），不能走坐标点击

**判断顺序**（遇到目标应用不在窗口列表时）：

1. 先查进程是否存活（`pgrep`）：活着 → 大概率是可见性问题，不是应用故障
2. 确认用户是否开启了台前调度（macOS 15+，`defaults read com.apple.WindowManager GloballyEnabled`，1=开启）：开启 → 走第 3 步；未开启 → 可能是窗口突然不存在或其他原因
3. 激活应用使其显形：`open -a <应用名>`（会短暂抢焦点，先告知用户）；**27 上首次激活可能不粘住，激活后立即验证，未显形再激活一次（上限 2 次）**
4. 重新 `gui_list_windows`，通常即可拿到 window_id

**附加信号**：台前调度开启时 `open_app` 通常**拿不到** window_id（返回 hint 让二次枚举）；关闭时正常返回 window_id。

**重要推论**：
- 报 `无可见窗口` ≠ 窗口不存在，更 ≠ 前序操作失败——上次"失败"的任务可能实际已成功（窗口已创建，只是看不到）
- 对话框型窗口（如"打开"文件对话框）被任务自己关闭后，其 window_id 随之失效，后续截图会报错——这是正常现象，重新枚举拿新 ID 即可
- 部分应用（如文本编辑）无文档启动时本来就没有窗口，属正常行为，需带文件打开

### 任务描述三段式（成败关键）

`task` 参数必须包含三部分：

```
目标：分步描述要完成什么
边界：明确不能碰什么，如"不要点击历史记录列表中的任何条目"
失败处理：若某操作无响应，准确记录发生了什么并进入下一步，不要重试或换方法
```

失败处理规则**不可省略**——缺了它，单次失败会触发反复重试，耗尽整轮步数配额。

描述中**不要包含像素坐标或数字位置**，用界面可见文本和控件名指代目标。

### 示例

用户请求："帮我打开 XX 应用，把导出格式改成 CSV"

```
目标：1. 找到并点击菜单栏或工具栏中的"设置"或"Preferences"入口
2. 在设置面板中找到"导出格式"或"Export Format"选项
3. 将其值改为 CSV
4. 保存设置并关闭面板
边界：不要修改任何其他设置项；不要点击"重置"按钮
失败处理：若找不到上述控件，记录实际看到的控件名称并结束任务，不要猜测性点击
```

## AX 兜底层（axctl）

当内置 computer use 不可用（未启用、gui_* 工具缺失、任务过小不值得派发）或需要语义级元素操作时，使用本 skill 内置的 AX 兜底工具 `tools/axctl`。纯 Accessibility API 实现，**不碰鼠标、不抢焦点、不受 AppleEvents 沙箱限制**（WorkBuddy 沙箱禁向 System Events 发控制类事件，osascript 路线已废弃勿再尝试）。

**位置与安装**：二进制 `tools/axctl`、源码 `tools/axctl.swift`（Swift 单文件），均随 skill 分发。首次使用前运行 `sh tools/install.sh`：检测到 swiftc 则**现场编译**（推荐，源码可审计、适配本机架构），否则使用随包预编译二进制（仅 Apple Silicon）。改动源码后在 tools 目录内执行 `swiftc -O -o axctl axctl.swift` 重编译。

**前置条件**：宿主需持有「辅助功能」TCC 权限（在 系统设置 → 隐私与安全性 → 辅助功能 中勾选宿主后**重启宿主**生效；以 AX 调用返回 AXError=0 为就绪标志）。

### 子命令

```
axctl list <bundle-id|pid>        列窗口：标题 + 逻辑几何 frame
axctl tree <target> [depth]       读 UI 树：角色/标题/描述/值/frame（默认 depth=2）
axctl actions <target> <标题>     查匹配元素的可用动作列表
axctl press <target> <标题>       按 AXPress（语义点击，元素级，无需坐标）
axctl activate <target>           激活应用（NSRunningApplication.activate）
```

`<target>` 支持 bundle id（推荐，如 `com.apple.calculator`）、数字 PID、或本地化应用名（小写匹配——**中文系统下是「计算器」不是 Calculator**，名字匹配易错，优先 bundle id）。

### 使用规则

1. **元素查找**：先 `tree` 或按已知按钮标题直接 `actions` 确认存在 `AXPress`，再 `press`。press 只对含 AXPress 动作的元素生效，菜单项是 AXPick，逐类判断
2. **动作验证**：press 返回 `PRESSED` 后，用 `tree` 读取目标元素或关联显示区的新值做证据（参照计算器实测：press "3" 后 StaticText 值变 3）——与 computer use 的截图验收同理，文字自述不算数
3. **台前调度场景**：AX 树读逻辑几何，缩略态窗口可读可操作（实测过）；但**全新启动未上舞台的 app AX 树为空**——先 `axctl activate` 或 `open -a` 上舞台再操作
4. **适用边界**：axctl 适合元素级读写（按钮/菜单/文本框）；需要跨应用菜单栏点击、系统级键鼠模拟、或复杂多步 GUI 流程时仍走内置 computer use 派发
5. **已知局限**：无 UI 变更监听（axmcp 的 observe_changes 能力，上游适配 Swift 6.4 后再评估）；单次单元素操作，无批量事务

### 实测记录（macOS 27.0.1，台前调度开启）

`axctl press com.apple.calculator "3"` → `PRESSED path=w/0/0/0/1/0/15` → `tree` 读回 AXStaticText 值为 3——读树、定位、语义点击、效果验证四环全通。

## 结果验证

GUI agent 的文字自述**不足以作为完成证据**——残留的旧界面状态可能被误判为成功。必须：

1. 任务返回 `done=true` 后，调用 `gui_screenshot(window_id)` 取最终截图
2. 以截图内容判断目标是否达成
3. 向用户汇报时注明结论依据是截图

每轮之间默认**不要**截图（`continue_task` 返回值已含执行历史），仅在 agent 连续数轮 reasoning/action_desc 无变化时补拍一次以判断是否卡死。

## 排错速查

| 症状 | 处理 |
|---|---|
| `permission_denied` | 见 references/authorization-macos.md |
| 连续多轮停在同一步 | `continue_task` 带 `hint` 参数给出控件准确可见文本 |
| 界面无变化但报告成功 | 依赖 `gui_screenshot`；确认 window_id 正确 |
| `conflict` | 该窗口已有任务，先 `delete_task` |
| `window_not_found` | 窗口已关闭或 ID 过期，重新 `gui_list_windows` |
| `无可见窗口`（进程存活时） | 台前调度激活致窗口不可捕获：`open -a` 激活 → 立即重新枚举；未显形再激活一次（27 上首次激活可能不粘住，上限 2 次），见"不可见窗口陷阱"（15 与 27.0.1 均已实验证实） |
| 截图拍到的窗口异常小/贴屏幕边缘 | 目标窗口处于台前调度缩略态（27 复检发现）：先 `open -a` 激活使其恢复全尺寸再拍，见"不可见窗口陷阱"27 复检小节第 1、3 条 |
| 状态为 `call_user` | 需人工介入，转述 `reasoning` 给用户，不调 `continue_task` |

## Platform Support

- **macOS**：完整支持。授权流程见 references/authorization-macos.md
- **Windows**：暂未验证，当前版本不承诺支持。遇到 Windows 环境时如实告知用户此限制，不要尝试套用 macOS 权限模型

## Resources

- `references/authorization-macos.md` — macOS 授权全流程，含实测踩坑记录（勾选后不生效、Quit & Reopen 弹窗等）
- `tools/axctl` — AX 兜底工具（源码 `tools/axctl.swift` 同目录；首次使用运行 `sh tools/install.sh`），用法见「AX 兜底层」章节
