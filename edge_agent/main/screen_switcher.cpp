/*
 * screen_switcher - BOOT 键循环切换墨水屏界面
 *
 * 板载 BOOT 键接 GPIO14（按下接地，平时上拉）。运行时读它安全，
 * 只有"按住 BOOT + 复位"才进下载模式。
 * 按一次切下一屏（工卡→天气日历→待办），松开才重新计一次按下，
 * 不连发；刷新期间（四色全刷约几秒）忽略按键。
 *
 * 与 vela-esp32 原版不同：本工程 EPD 由 lua_module_epaper 统一管理，
 * 这里通过 epaper_display_raw() 推图，内部互斥锁与 Lua 侧（AI 脚本）
 * 序列化，因此不再需要本地的 s_refreshing 标志——按键期间若 AI 正在刷屏，
 * 会在 epaper_display_raw 内阻塞等锁，刷完再切。
 */
#include <stdbool.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "driver/gpio.h"
#include "epaper_display.h"
#include "ui_screens.h"
#include "screen_switcher.h"

static const char *TAG = "switcher";

#define BUTTON_GPIO     54      /* 按键输入（另一端接 GND）。原 35 被 RMII 以太网 TXD1 占用 */
#define POLL_MS         20      /* 轮询周期 */
#define DEBOUNCE_TICKS  3       /* 3 x 20ms 稳定才认定电平变化 */

static int s_index;

static void show_screen(int idx)
{
    /* 天气屏(1)/待办屏(2)：优先显示 LLM 后台生成的缓存(秒刷)，未就绪则回退静态占位。 */
    static uint8_t buf[UI_SCREEN_BYTES];  /* static 进 BSS，不占 4KB 任务栈（否则 17KB 栈溢出崩溃） */
    bool valid = false;
    esp_err_t get_err = ESP_ERR_NOT_FOUND;

    if (idx == 1) {
        get_err = epaper_get_weather_cache(buf, sizeof(buf), &valid);
    } else if (idx == 2) {
        get_err = epaper_get_schedule_cache(buf, sizeof(buf), &valid);
    }

    if (get_err == ESP_OK && valid) {
        if (epaper_display_raw(buf, UI_SCREEN_BYTES) == ESP_OK) {
            ESP_LOGI(TAG, "显示缓存屏 [%d] %s", idx, ui_screen_names[idx]);
            return;
        }
    }

    esp_err_t err = epaper_display_raw(ui_screens[idx], UI_SCREEN_BYTES);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "show_screen(%d) failed: 0x%x", idx, (unsigned)err);
    }
}

static void button_task(void *arg)
{
    int stable = 1;                     /* 上电默认松开（高） */
    int count = 0;
    while (1) {
        int raw = gpio_get_level((gpio_num_t)BUTTON_GPIO);
        if (raw != stable) {
            if (++count >= DEBOUNCE_TICKS) {
                stable = raw;
                count = 0;
                if (stable == 0) {  /* 下降沿 = 按下 */
                    s_index = (s_index + 1) % UI_SCREEN_COUNT;
                    ESP_LOGI(TAG, "切换到 [%d] %s", s_index, ui_screen_names[s_index]);
                    show_screen(s_index);
                }
            }
        } else {
            count = 0;
        }
        vTaskDelay(pdMS_TO_TICKS(POLL_MS));
    }
}

void screen_switcher_start(int start_index)
{
    s_index = start_index % UI_SCREEN_COUNT;

    gpio_config_t io = {};               /* 零初始化：下拉/中断默认关闭 */
    io.pin_bit_mask = 1ULL << BUTTON_GPIO;
    io.mode = GPIO_MODE_INPUT;
    io.pull_up_en = GPIO_PULLUP_ENABLE;
    ESP_ERROR_CHECK(gpio_config(&io));

    show_screen(s_index);               /* 开机立即显示初始屏 */

    xTaskCreate(button_task, "btn_switch", 4096, NULL, 8, NULL);
    ESP_LOGI(TAG, "按键切屏就绪：GPIO%d，当前 [%d] %s",
             BUTTON_GPIO, s_index, ui_screen_names[s_index]);
}

void screen_switcher_refresh_schedule(void)
{
    if (s_index == 2) {
        show_screen(2);
    }
}
