# Edge Agent 使用指南（ESP32-P4）

本文档是 ESP-Claw 主固件应用 `edge_agent` 的**使用指南 + 外设移植说明**，面向在
**ESP32-P4 Function EV Board** 上构建、烧录、使用，以及想把新外设移植进来的开发者。

> 项目整体介绍见仓库根 [README.md](../../README.md)；架构与开发规范见
> [AGENTS.md](../../AGENTS.md)；每个 Lua 模块的 API 详解见
> [components/lua_modules/](../../components/lua_modules/) 下各 `README.md`。

---

## 1. 概述

**ESP-Claw** 是 Espressif 的物联网设备 AI 智能体框架：Agent Loop 直接跑在 ESP32 芯片上，
通过对话定义设备行为，完成「感知 → 决策 → 执行」的完整闭环。

`edge_agent` 是 ESP-Claw 的主固件应用，目标板为 **ESP32-P4 Function EV Board**。目前板上的
摄像头（SC2336）、音频编解码（ES8311）、墨水屏（Waveshare 3.5" 4 色）等外设已点亮，AI 可以
通过 Lua 模块 + skill 把它们当作工具调用。

已点亮并可供 AI 调用的外设一览：

| 外设 | 状态 | AI 调用方式 |
|------|------|-------------|
| 摄像头（SC2336 MIPI-CSI） | ✅ board_manager 初始化 | `camera` 模块 / `take_picture` skill |
| 音频（ES8311 录/放） | ✅ board_manager 初始化 | `audio` 模块 |
| 墨水屏（3.5" 4 色） | ✅ `lua_module_epaper` 直驱 | `epaper` 模块 / `epaper_show_text` skill |
| SD 卡存储 | ✅（可无卡启动） | `storage` 模块 |

---

## 2. 硬件概览

### 2.1 芯片特性

- **ESP32-P4**：无内置 WiFi/BLE，用 **RMII EMAC 以太网** 替代（`eth_init()` 启动，DHCP 拿 IP）
- 内存：**32MB Hex PSRAM** @200MHz（模型推理/帧缓冲放 PSRAM）
- 存储：**16MB QIO flash**

### 2.2 板载外设与引脚

引脚分配来自 `boards/espressif/esp32_p4_function_ev/` 下的
[board_devices.yaml](boards/espressif/esp32_p4_function_ev/board_devices.yaml) 与
[board_peripherals.yaml](boards/espressif/esp32_p4_function_ev/board_peripherals.yaml)：

| 外设 | 芯片/型号 | 类型 | 关键引脚 |
|------|-----------|------|----------|
| 摄像头 | SC2336 | MIPI-CSI | I2C@100kHz、LDO VO3（2.5V） |
| 音频 DAC | ES8311 | audio_codec | I2S out、I2C@400kHz 0x30、MCLK=13 |
| 音频 ADC | ES8311 | audio_codec | I2S in、I2C@400kHz 0x30 |
| PA 控制 | — | gpio | GPIO53 |
| I2C 主机 | — | i2c | SDA=7、SCL=8 |
| I2S 音频 | — | i2s | MCLK=13、BCLK=12、WS=10、DOUT=9、DIN=11 |
| LDO MIPI | — | ldo | chan3、2500mV |
| 墨水屏 | Waveshare 3.5" 4 色 | bit-bang SPI | SCK=21、MOSI=22、CS=33、DC=32、RST=5、BUSY=20 |

> **注意**：墨水屏引脚由 `lua_module_epaper` **直接通过 GPIO 驱动**（bit-bang SPI），**不走**
> `board_manager`。这些引脚在 `board_peripherals.yaml` 里只作保留登记（避免被其他设备复用），
> 真正初始化在 `lua_module_epaper/src/DEV_Config.h` 里。

---

## 3. 已启用外设与 Lua 模块

### 3.1 board_manager 自动初始化

`app_main()`（`main/main.c`）调用 `esp_board_manager_init()`，按 YAML 自动初始化：
camera、audio_dac / audio_adc、i2c_master、i2s_audio_out / in、ldo_mipi、gpio_pa_control。

- 摄像头初始化成功 → `dev_path: /dev/video0`
- SD 卡**未插入时**会打 `E ... Failed to init device: fs_sdcard`，但**不影响启动**，
  自动回退到 flash FATFS（日志 `app_fs: No SD card device, using flash fatfs`）

### 3.2 已启用 Lua 模块

以下来自 `sdkconfig` 的 `CONFIG_APP_CLAW_LUA_MODULE_*=y`（共 17 个模块 + 8 个 driver）：

| 模块 | 功能 | 带 skill? |
|------|------|-----------|
| `camera` | 拍照（借帧 API） | `take_picture` |
| `audio` | 音频录制/播放 | — |
| `epaper` | 墨水屏显示 | `epaper_show_text` |
| `image` | 图像格式转换 / JPEG | — |
| `vision` | 视觉（motion/color） | — |
| `storage` | FAT 文件系统 | — |
| `system` | 系统信息 / 网络 | — |
| `board_manager` | 从 Lua 使用 board_manager | — |
| `button` | 按键 | — |
| `delay` | 延时 | — |
| `event_publisher` | 从 Lua 发事件 | — |
| `http_server` | Lua 静态资源/回调 | `http_server_lua_demo` |
| `json` | JSON 编解码 | — |
| `thread` | FreeRTOS 任务/同步 | — |
| `ledc` | PWM 输出 | — |
| `led_strip` | LED 灯带 | — |
| `capability` | 从 Lua 调已注册 capability | — |
| （`lua_driver_*` ×8） | gpio / i2c / adc / uart / rmt / mcpwm / pcnt / touch | `read_touch` |

### 3.3 启动验证状态（实测 boot log）

```text
I (8240) cap_lua_rt: Lua runtime ready: registered_modules=25
I (8189) claw_skill: Reloaded registry with 20 skill(s)
I (6729) app: Ethernet got IP: 192.168.137.xxx
I (8347) app_claw: Starting root agent backend=openai_compatible ... model=deepseek-v4-flash
```

- `registered_modules=25` = 17 个 `lua_module_*` + 8 个 `lua_driver_*`
- `20 skill(s)` 含 `epaper_show_text`、`take_picture`、`board_hardware_info`、`builtin_lua_modules` 等

---

## 4. 构建与烧录（ESP-IDF v6.1-beta1）

### 4.1 环境要求

- **ESP-IDF v6.1-beta1**（本仓库用的非标路径：IDF `E:\esp\v6.1-beta1\esp-idf`、工具 `E:\Espressif`）
- **必须用原生 PowerShell**：ESP-IDF v6 已弃用 MSys/Git-Bash。若从 Git Bash 里再调
  `powershell.exe`，子进程会继承 `MSYSTEM`，触发 `MSys/Mingw is no longer supported` 拦截。
  请直接在 Windows PowerShell 里跑下面命令。

先固化环境变量（把路径换成你的实际安装位置）：

```powershell
$env:IDF_PATH = "E:\esp\v6.1-beta1\esp-idf"
$env:IDF_TOOLS_PATH = "E:\Espressif"
$env:IDF_PYTHON_ENV_PATH = "E:\Espressif\tools\python\v6.1-beta1\venv"
$env:ESP_IDF_VERSION = "6.1.0"
$env:PATH = "E:\Espressif\tools\python\v6.1-beta1\venv\Scripts;E:\Espressif\tools\cmake\4.0.3\bin;E:\Espressif\tools\ninja\1.12.1;E:\Espressif\tools\riscv32-esp-elf\esp-15.2.0_20251204\riscv32-esp-elf\bin;$env:PATH"
Remove-Item Env:MSYSTEM -ErrorAction SilentlyContinue
```

之后统一用下面的入口调用 `idf.py`：

```powershell
& "E:\Espressif\tools\python\v6.1-beta1\venv\Scripts\python.exe" "E:\esp\v6.1-beta1\esp-idf\tools\idf.py" <args>
```

### 4.2 配置

```powershell
pip install esp-bmgr-assist   # 一次性

# 1. 选板（生成板级支持文件）
& ...\idf.py bmgr -c ./boards -b esp32_p4_function_ev

# 2. 配 LLM API Key / 模型、IM、时区等
& ...\idf.py menuconfig
```

> 板级源码在 `boards/espressif/esp32_p4_function_ev/`，含 `board_devices.yaml` /
> `board_peripherals.yaml` / `board_info.yaml` / `sdkconfig.defaults.board` / `setup_device.c`。

> ⚠️ **Kconfig 陷阱**：`sdkconfig.defaults.*` 只填充 sdkconfig 里**完全不存在的符号**。新加的
> `default n` Kconfig 符号首次构建会以 `# ... is not set` 落盘，此后 defaults 里的 `=y` **永不生效**
> （增量 build 不重应用 defaults）。**对策**：直接改 `sdkconfig` 对应行，或 `idf.py fullclean`
> 从 defaults 重新生成。

### 4.3 构建

```powershell
& ...\idf.py build
```

> 若改完 sdkconfig 后，新增组件（依赖 `$CONFIG{...}` rules）没被组件管理器识别，是因为
> **依赖解析被缓存**。用 `idf.py fullclean` 强制重算 rules。

### 4.4 烧录

```powershell
& ...\idf.py -p COM3 flash
```

> 若报 `Could not open COM3 ... 拒绝访问`，是有残留的 `idf_monitor` 进程占着串口。先释放：

```powershell
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "COM3|monitor" } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

分区布局（16MB，`partitions_16MB.csv`）：

| 分区 | 类型 | 大小 |
|------|------|------|
| nvs / otadata / phy_init | data | — |
| ota_0 / ota_1 | app | 各 5M |
| system | fat（只读，`/system`） | 2600K |
| storage | fat（可写，`/fatfs`） | 3M |

### 4.5 启动验证

串口看关键行：

```text
I (...) cap_lua_rt: Lua runtime ready: registered_modules=25
I (...) claw_skill: Reloaded registry with 20 skill(s)
I (...) app: Ethernet got IP: 192.168.137.xxx
```

然后在浏览器打开 `http://<板子IP>`（Web IM），对 AI 说：

- 「拍一张照片保存」→ 应激活 `take_picture` skill
- 「在墨水屏上显示 Hello AI」→ 应激活 `epaper_show_text` skill

---

## 5. 外设移植指南

### 5.1 移植模式：Lua 模块 + skill（标准范式）

每个新外设走「Lua 模块 + skill」，让 AI 通过激活 skill 跑 `.lua` 脚本来驱动。模板参考
`lua_module_camera`（借帧式）/ `lua_module_display`（帧缓冲+字体式）。

新增 `lua_module_xxx` 需在**五处**登记（模板见 `components/lua_modules/lua_module_camera/`）：

1. **组件目录** `components/lua_modules/lua_module_xxx/`
   - `CMakeLists.txt`：`idf_component_register(SRCS ... INCLUDE_DIRS ... REQUIRES ...)`
   - `src/lua_module_xxx.c`：实现 `luaopen_xxx` + `lua_module_xxx_register()`，后者调
     `cap_lua_register_module("xxx", luaopen_xxx)`
2. **登记** `components/common/app_claw/app_lua_modules.c`：在 `s_lua_module_entries[]` 加
   `{ "xxx", "Xxx", app_lua_register_xxx }`，用 `#if CONFIG_APP_CLAW_LUA_MODULE_XXX` 守卫
3. **Kconfig** `components/common/app_claw/Kconfig`：加 `config APP_CLAW_LUA_MODULE_XXX` bool
4. **依赖规则** `components/common/app_claw/idf_component.yml`：加

   ```yaml
   lua_module_xxx:
     rules:
       - if: $CONFIG{APP_CLAW_CAP_LUA} == True
       - if: $CONFIG{APP_CLAW_LUA_MODULE_XXX} == True
     path: ../../lua_modules/lua_module_xxx
   ```

5. **skill** `components/lua_modules/lua_module_xxx/skills/<task>/SKILL.md` +
   `scripts/<task>.lua`。`sync_component_skills.py` 会**自动**把已构建组件的 `skills/` 同步到
   `build/system_fs_image/skills/`，**无需**在 CMakeLists 里做任何调用。

### 5.2 移植案例：墨水屏（e-paper）

从 `vela-esp32` 项目把 `DEV_Config.*` + `EPD_3in5g_V2.*` 驱动拷进
`components/lua_modules/lua_module_epaper/src/`，再加 Lua 绑定。

- **引脚**：SCK=21、MOSI=22、CS=33、DC=32、RST=5、BUSY=20（bit-bang SPI，无专用 SPI 外设）
- **Lua API**（`epaper` 模块，7 个函数）：

| 函数 | 说明 |
|------|------|
| `epaper.init()` | GPIO + 面板初始化（幂等） |
| `epaper.clear(color)` | 填充帧缓冲（黑0/白1/黄2/红3），不刷屏 |
| `epaper.text(str, x, y, size, color)` | 往帧缓冲画字（size 8/16/24） |
| `epaper.display()` | 帧缓冲刷到面板（慢，数秒） |
| `epaper.sleep()` | 面板深度睡眠 |
| `epaper.width()` / `epaper.height()` | 184 / 384 |

- **skill** `epaper_show_text` 的 `show_text.lua` 流程：
  `init → clear(background) → text(...) → display() → sleep()`
- **面板特性**：4 色（黑/白/黄/红）、184×384、整屏刷新数十秒，适合静态信息。

Lua 直调示例：

```lua
local epaper = require("epaper")
epaper.init()
epaper.clear(1)                       -- 白底
epaper.text("Hello AI", 0, 0, 24, 0)  -- 黑字，字号 24
epaper.display()                      -- 刷屏（数十秒）
epaper.sleep()
```

### 5.3 移植坑总结（按踩中顺序）

1. **Kconfig `default n` 陷阱**：`app_claw/Kconfig` 的 `APP_CLAW_LUA_MODULE_EPAPER` 默认 `n`，
   首次进 sdkconfig 为 `# ... is not set`，`sdkconfig.defaults.board` 的 `=y` 不覆盖。
   → 直接改 `sdkconfig` 对应行，或 `idf.py fullclean`。
2. **组件管理器 rules 缓存**：改完 sdkconfig 增量 build 不重算 `$CONFIG{}` rules，新组件不进
   `build_component_info` → C 模块不编译、skill 不同步。→ `idf.py fullclean`。
3. **IDF v6 driver 拆分**：`driver/gpio.h` 已迁到 `esp_driver_gpio` 组件。CMakeLists `REQUIRES`
   写 `driver` 会报 `Please add esp_driver_gpio to REQUIRES`。→ 改 `esp_driver_gpio`
   （参考 `lua_driver_gpio/CMakeLists.txt`）。
4. **C++ Lua 头缺 `extern "C"`**：`georgik__lua` 的 `lua.h`/`lauxlib.h` **没有** `extern "C"`
   守卫（`luaconf.h` 的 `LUA_API` 是裸 `extern`）。`.cpp` 直接 include 会导致
   `lua_createtable` 等符号被 C++ name-mangling，链接报 `undefined reference`。→ 用
   `extern "C" { #include "lauxlib.h" }` 包住（参考已修的 `lua_module_epaper.cpp` / `.h`）。
5. **串口占用**：残留 `idf_monitor` 进程锁 COM3 → 烧录报「拒绝访问」。→ 杀掉残留 python 进程
   （见 §4.4）。

---

## 6. 使用示例（AI 对话触发）

| 对 AI 说 | 效果 |
|----------|------|
| 「拍一张照片保存到 SD 卡」 | AI 激活 `take_picture` → `camera` 模块拍照 + JPEG 落盘 |
| 「在墨水屏上显示 Hello AI」 | AI 激活 `epaper_show_text` → 面板刷出字（数十秒） |
| 「录 3 秒音并播放」 | `audio` 模块录音 + 播放 |

也可以直接在 Lua 里调（`require("epaper")` / `require("camera")` / `require("storage")` 等，
见各模块 README）。

---

## 7. 参考链接

- [README.md](../../README.md) / [README_CN.md](../../README_CN.md) — 项目落地页
- [AGENTS.md](../../AGENTS.md) — 架构与开发规范
- [components/lua_modules/](../../components/lua_modules/) — 各 Lua 模块 API 详解（40 篇）
- `.agents/spec/lua-module-spec` / `.agents/spec/claw-skill-spec` — Lua 模块与 skill 规范
