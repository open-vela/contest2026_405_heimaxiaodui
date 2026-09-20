# schedule_manager skill 设计文档

## 1. 功能概述

`schedule_manager` 是一个纯 Lua skill（无需任何 C 代码），让设备具备日程管理能力：

1. **接收日程**：用户通过聊天（飞书/Web IM）用自然语言提供日程，LLM 解析为结构化数据
2. **持久存储**：日程以 JSON 格式写入板子可写 FAT 分区 `/fatfs/schedules/schedules.json`，掉电不丢
3. **e-paper 显示**：在对应日期显示当日日程（时间 + 英文/拼音标签）
4. **自动语音播报**：到日程时间时，设备端调度器唤醒 LLM，LLM 调 `announce_time` 报时 + 发飞书日程详情

## 2. 架构总览

```
用户聊天："明天8点半早会，下午3点项目评审"
         │
         ▼
LLM 解析 → 调 add_schedule.lua（传 schedules 数组 + chat_channel + chat_id）
         │
         ├─→ 写 /fatfs/schedules/schedules.json（持久存储）
         ├─→ 对每条日程调 capability.call("scheduler_add", {schedule_json})
         │      └─ kind="once", start_at_ms=os.time()*1000, mode="wake_agent"
         │         text="日程提醒：早会。请播报当前时间，并通过飞书发送日程详情。"
         └─→ 调 show_schedule.lua 更新 e-paper 显示

         ⋮ （到日程时间）

cap_scheduler_task tick（FreeRTOS 任务，1 秒一次）→ start_at_ms <= now_ms
         │
         ▼
claw_event_router_publish({event_type:"message", source_channel:"feishu", ...})
         │
         ▼
im_any_message_agent 路由规则匹配 → run_agent
         │
         ▼
LLM 收到 "日程提醒：早会。请播报当前时间，并通过飞书发送日程详情。"
         │
         ├─→ 调 get_current_time 拿到时间
         ├─→ 调 announce_time skill 报时（喇叭播放预录制片段）
         ├─→ 发飞书消息 "您有日程：早会"
         └─→ 调 show_schedule.lua 刷新 e-paper
```

### 关键机制（探查证实，均为 esp-claw 已有能力）

| 机制 | 组件 | 说明 |
|------|------|------|
| 设备端调度器 | `cap_scheduler` | FreeRTOS 任务，1 秒 tick，支持 once/interval/cron 三种 kind |
| 事件总线 | `claw_event_router` | 发布/订阅，调度器触发时发布 event |
| 路由规则 | `cap_router_mgr` | `im_any_message_agent` 规则把消息事件路由给 LLM 代理 |
| wake_agent 模式 | 调度器条目 | 合成一条"伪用户消息"，复用 `im_any_message_agent` 规则唤醒 LLM |

## 3. 日程 JSON 格式

存储路径：`<storage_root>/schedules/schedules.json`（即 `/fatfs/schedules/schedules.json`）

```json
{
  "schedules": [
    {
      "id": "sched_20260916_0830",
      "date": "2026-09-16",
      "time": "08:30",
      "hour": 8,
      "minute": 30,
      "title": "早会",
      "title_ascii": "Morning Meeting",
      "description": "团队晨会",
      "recurrence": "once",
      "weekday": -1,
      "enabled": true
    }
  ]
}
```

字段说明：

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 唯一标识，同时作为调度器条目 id（`sched_YYYYMMDD_HHMM`，冲突自动加 `_2`） |
| `date` | string | 起始日期（once 为具体日期；daily/weekly 为起始日期） |
| `time` | string | 触发时间 `HH:MM` |
| `hour` / `minute` | int | 触发时间（小时/分钟） |
| `title` | string | 日程标题（中文，供飞书消息和 LLM 阅读） |
| `title_ascii` | string | 英文/拼音标签（供 e-paper 显示，因 e-paper 无中文字体） |
| `description` | string | 可选描述 |
| `recurrence` | string | `once` / `daily` / `weekly` |
| `weekday` | int | weekly 专用，0-6（0=周日）；其余为 -1 |
| `enabled` | bool | 是否启用 |

## 4. 脚本职责

### 4.1 add_schedule.lua（添加日程）

输入：`schedules` 数组（每条含 date/time/title/title_ascii/description/recurrence/weekday）+ `chat_channel` + `chat_id`

职责：
1. 读取现有 `schedules.json`（不存在则初始化）
2. 对每条日程：解析日期时间 → 计算 `start_at_ms` 或 `cron_expr` → 构建调度器条目 → `scheduler_add`
3. 追加到 JSON 数组并写回

### 4.2 show_schedule.lua（e-paper 显示今日日程）

输入：`date`（可选，缺省用 `os.date("%Y-%m-%d")`）

职责：读取 JSON → 过滤今日日程（once 匹配日期；daily 总是显示；weekly 匹配星期）→ 按时间排序 → e-paper 绘制。

### 4.3 list_schedules.lua（列出所有日程）

职责：读取 JSON，逐条 `print`，供 LLM 读取后回复用户。

### 4.4 remove_schedule.lua（删除日程）

输入：`schedule_id`

职责：从 JSON 删除匹配条目 → `scheduler_remove` 删除调度器条目 → 写回。

## 5. e-paper 显示布局

面板：184×384，4 色（黑/白/黄/红），仅 ASCII 字体（8/16/24px），无画线函数。

```
y=0:   "TODAY"           (Font24, 17px/char, 黑色)
y=30:  "2026-09-16"      (Font16, 11px/char)
y=52:  "----------------" (Font16, 分隔线)
y=72:  "08:30 Meeting"   (Font16, 每条日程一行)
y=92:  "15:00 Review"
...
```

- 每行 20px 间距，从 y=72 开始，最多约 15 条日程
- Font16 每行最多 16 字符：`"HH:MM "`（6 字符）+ 标签（截断到 10 字符）
- 无日程时显示 `"No schedules"`

## 6. 调度器条目构建（wake_agent 模式）

对每条日程构建的调度器条目（`scheduler_add` 的 `schedule_json`）：

```json
{
  "id": "sched_20260916_0830",
  "enabled": true,
  "kind": "once",
  "start_at_ms": 1726446600000,
  "end_at_ms": 0,
  "interval_ms": 0,
  "cron_expr": "",
  "event_type": "message",
  "event_key": "text",
  "source_channel": "feishu",
  "chat_id": "ou_xxx",
  "content_type": "text",
  "session_policy": "chat",
  "text": "日程提醒：早会。请播报当前时间，并通过飞书发送日程详情。",
  "payload_json": "{}",
  "max_runs": 1
}
```

各 recurrence 对应的 kind/cron：

| recurrence | kind | 时间字段 | max_runs |
|-----------|------|---------|----------|
| `once` | `once` | `start_at_ms = os.time({...}) * 1000` | 1 |
| `daily` | `cron` | `cron_expr = "M H * * *"` | 0（无限） |
| `weekly` | `cron` | `cron_expr = "M H * * N"`（N=weekday） | 0（无限） |

## 7. 自动触发流（wake_agent 唤醒后 LLM 的动作）

调度器触发后，LLM 会收到以 "日程提醒：" 开头的消息。SKILL.md 中文档化 LLM 应执行的动作：

1. 调 `get_current_time` 获取当前时间
2. 激活 `announce_time` skill，传 hour/minute，喇叭报时
3. 提取日程标题，通过飞书发 "您有日程提醒：{标题}"
4. 激活 `schedule_manager`，跑 `show_schedule.lua` 刷新 e-paper
5. 回复简短文本

## 8. 设计约束与限制

- **无中文字体**：e-paper 仅 ASCII，标题须有 `title_ascii`（英文/拼音）
- **cron 语法受限**：`cap_scheduler_parser.c` 只支持 `*`、`*/N`、单个数字，不支持范围/列表。故"工作日 Mon-Fri"需 5 条条目，v1 不支持
- **无 TTS**：语音播报只能拼接预录制 WAV 片段（复用 `announce_time`），无法朗读日程标题——标题详情靠飞书消息传递
- **两个独立 JSON**：skill 维护 `/fatfs/schedules/schedules.json`（数据源），`cap_scheduler` 维护 `/fatfs/scheduler/schedules.json`（触发源），二者独立

## 9. 复用的已有模块（零新 C 代码）

| 模块 | 用途 |
|------|------|
| `require("storage")` | `get_root_dir/join_path/exists/mkdir/write_file/read_file` |
| `require("json")` | `encode/decode`（cJSON） |
| `require("capability")` | `capability.call("scheduler_add"/"scheduler_remove", ...)` |
| `require("arg_schema")` | 参数归一化 |
| `require("epaper")` | `init/clear/text/display/sleep` |
| `os.time` / `os.date` | Unix 时间戳换算 + 当前日期 |
| `announce_time` skill | 报时音频片段（wake_agent 触发时 LLM 调用） |
