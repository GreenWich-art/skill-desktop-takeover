# macOS 授权全流程（实测记录）

WorkBuddy computer use 在 macOS 上需要两项 TCC 权限：

| 权限 | 用途 |
|---|---|
| 辅助功能 (Accessibility) | 模拟点击与键盘输入 |
| 屏幕录制 (Screen Recording) | 截图识别界面 |

## 检测

调用 `gui_permission_status`，返回结构：

```json
{
  "accessibility": bool,
  "screen_recording": bool,
  "all_granted": bool,
  "missing": [...]
}
```

## 授权引导流程

1. 调用 `gui_setup_permission`，它会打开系统设置的对应面板并轮询等待
2. 指导用户在系统设置中为 WorkBuddy 勾选两项权限
3. 系统弹出「退出并重新打开」(Quit & Reopen) 对话框时，**必须点击确认**，权限才会写入
4. 工具检测到 service 重启且权限齐全后返回 `all_granted: true`
5. 若一轮内未完成，返回 `waiting: true`，再次调用 `gui_setup_permission` 继续等待

权限生效后**无需**手动调 `gui_apply_permission`（托管模式下由系统管理生命周期），可直接重试 `create_task` / `gui_screenshot`。

## 实测踩坑记录（macOS 15 + WorkBuddy 托管模式）

1. **勾选后权限不生效**：若已勾选仍报缺失，先**取消勾选再重新勾选一次**，触发完整授权流程；或重启 WorkBuddy 后重试
2. **Quit & Reopen 弹窗不可忽略**：跳过它权限不会写入，且不会报错——表现为"明明勾了但 `all_granted` 仍为 false"
3. **等待机制**：`gui_setup_permission` 本身会阻塞轮询，实测权限授予后自动返回成功，全程无需用户重复操作
4. **前台整屏模式默认关闭**：默认只有后台窗口任务（不抢用户鼠标键盘）。如需前台整屏模式，需设置环境变量 `WORKBUDDY_COMPUTER_USE_FOREGROUND_DISABLED=false`（默认返回的窗口列表不含 screen 目标）
5. **osascript 退出应用报权限违例**：沙箱环境下 `osascript -e 'quit app "XX"'` 可能被 macOS 拒绝（错误 -10004 权限违例），替代方案是直接 `kill <pid>`（温和终止，等效于用户手动退出）
6. **台前调度下后台应用不可捕获**：用户开启台前调度（Stage Manager）时，未上当前舞台的应用窗口可能不被窗口枚举和截图捕获——窗口真实存在但看不到。恢复手段是 `open -a <应用名>` 激活应用。判断顺序见 SKILL.md"不可见窗口陷阱"一节。**触发条件经对照实验收窄为台前调度**：关闭台前调度后，后台启动应用的窗口枚举/截图/`open_app` 返回 window_id 均正常，与是否后台运行无关。

   底层机制（经网络资料核实）：台前调度会将未上台应用的窗口**几何移出屏幕**（表现为侧栏中的倾斜缩略图，见 Sidebar 开发者反馈 feedback.sidebarapp.net/posts/1358）；而 macOS 的窗口捕获（CGWindowListCreateImage）只能对**在屏窗口**成像——它向 WindowServer 请求用户正在看的像素，窗口不在屏幕上就无像可取；窗口枚举若使用 OnScreenOnly 类过滤，离屏窗口也会从列表消失。激活应用后窗口回到屏幕，枚举与截图即恢复。注意：Apple 在新系统版本中持续调整此行为，本文所述以 macOS 15 实测 + 当时的公开资料为准。

## 验证授权成功

授权完成后，调用 `gui_list_windows` 确认可枚举窗口（返回各窗口的 window_id/name/PID），即可证明截图链路通畅。再走一个最小任务实测（如对任一窗口派发一个只读任务）确认完整链路。
