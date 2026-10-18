# desktop-takeover

让 Agent 安全接管桌面完成 GUI 操作的编排技能：先路由判断最优通路，权限就绪后再派发 computer use 任务并以截图验收。另内置 AX 兜底工具（`tools/`：Swift 源码 + 预编译二进制 + 一键安装脚本），computer use 不可用时做元素级无障碍操作。

## 这个工具适合你吗？

**适合谁**：希望让 WorkBuddy 操控本机图形界面软件（改设置、点按钮、填表单），但不想每次都从零摸索流程的用户。

**典型场景**：

| 痛点 | 对应能力 |
|---|---|
| "这个软件只有 GUI 入口，Agent 能帮我改个设置吗" | 五级路由决策树，确认无更优通路后才动 GUI |
| "Agent 说没权限，我勾了还是不行" | 授权引导含实测踩坑记录（Quit & Reopen 必须确认、勾选后不生效先取消再勾） |
| "Agent 说做完了，其实根本没点上" | 强制以最终截图验收，文字自述不算数 |
| "任务跑一半卡死反复点同一个地方" | 任务描述三段式含失败处理规则，防止重试耗尽步数 |
| "报"无可见窗口"，是应用坏了吗" | 台前调度激活时窗口真实存在但不可捕获——判断顺序与恢复手段（开关两组对照实验确认） |

**不适合谁**：
- 浏览器网页操作 → 用 browser-use 技能，不需要桌面接管
- Office/WPS 文档读写 → 用 office 技能族（workbuddy-docx / sheetagent / local-office-edit）
- 有连接器直达的应用（GitHub、WPS 知识库等）→ 直接用连接器
- Windows 用户 → 当前版本仅验证 macOS；Windows 权限模型不同，暂不承诺支持

## 快速开始

1. 将本目录放入 `~/.workbuddy/skills/`（用户级，跨项目可用）
2. 对 WorkBuddy 说一个 GUI 任务，如"帮我打开某应用改某个设置"
3. 首次使用时 Agent 会检测权限并引导你完成 macOS 授权（辅助功能 + 屏幕录制，一次性）
4. （可选）AX 兜底工具首次使用前，Agent 会运行 `sh tools/install.sh` 完成安装——有 Xcode 命令行工具则现场编译，否则用随包预编译二进制（仅 Apple Silicon），无需手动操作

## 作为 Agent Skill 使用

本技能是 **computer use 的编排层**，不替代内置 computer use 技能，而是补足它缺失的三块：

1. **路由决策**：连接器 → 浏览器控制 → Office 技能 → 命令行 → computer use 的完整判断链（内置技能只提了"连接器优先"）
2. **主动授权引导**：内置技能只在报错后被动处理；本技能提供检测 → 引导 → 踩坑处理的完整流程（见 `references/authorization-macos.md`）
3. **任务描述规范**：目标/边界/失败处理三段式模板，这是 GUI 任务成败的关键变量

依赖：WorkBuddy 内置 computer use 插件（`workbuddy-computer-use`）。AX 兜底层另需 macOS「辅助功能」TCC 权限；其工具随包分发（`tools/`），首次运行 `sh tools/install.sh` 安装。

## 文件说明

| 文件 | 用途 |
|---|---|
| `SKILL.md` | 路由决策树、任务派发规范、结果验证、排错速查 |
| `references/authorization-macos.md` | macOS 授权全流程与实测踩坑记录 |
| `tools/axctl.swift` | AX 兜底工具源码（Swift 单文件，可完整审计） |
| `tools/axctl` | 预编译二进制（仅 Apple Silicon，ad-hoc 签名；有 swiftc 时 install.sh 会改为现场编译） |
| `tools/install.sh` | 一键安装：swiftc 在场→现场编译，否则→用预编译二进制并自动去隔离属性 |

## 安全与信任（关于 tools/axctl 二进制）

三层说明，按可信程度排列：

1. **源码可审计 + 现场编译优先**：`tools/axctl.swift` 是完整源码（约 200 行，只调用 AppKit / ApplicationServices 公共 API，无网络、无文件读写、无子进程）。装有 Xcode 命令行工具时，`install.sh` 会自动用本机 `swiftc` 重新编译，不使用随包二进制。
2. **ad-hoc 签名 + 去隔离属性**：随包二进制仅做 ad-hoc 签名（未公证）。从网络下载的包会被 macOS 标记隔离属性导致无法运行，`install.sh` 会自动清除；如手动使用，可执行 `xattr -d com.apple.quarantine tools/axctl` 或在 Finder 中右键打开。
3. **自验方法**：`codesign -dv tools/axctl` 应显示 `Signature=adhoc`；`sh tools/install.sh` 结尾的自检会实际运行一次 `axctl list com.apple.finder` 并报告结果。

## 系统要求

- macOS（已在 macOS 15 实测；Windows 未验证）
- WorkBuddy 桌面客户端 + 内置 computer use 插件
- Xcode Command Line Tools（可选）：装有则 `tools/install.sh` 现场编译 axctl；未装则用随包预编译二进制（仅 Apple Silicon）

## License

MIT（见 LICENSE 文件）
