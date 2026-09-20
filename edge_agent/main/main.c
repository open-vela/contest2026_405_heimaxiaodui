/*
 * SPDX-FileCopyrightText: 2026 Espressif Systems (Shanghai) CO LTD
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#include "app_claw.h"
#include "app_fs.h"
#include "claw_version.h"
#include "claw_paths.h"
#include "edge_agent_version.h"
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include "esp_netif.h"
#include "esp_eth.h"
#include "esp_eth_mac.h"
#include "esp_eth_phy.h"
#include "esp_event.h"
#include <arpa/inet.h>
#include "freertos/event_groups.h"
#include "time.h"
#include "nvs_flash.h"
#include "http_server.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_check.h"
#include "esp_system.h"
#include "esp_board_manager_includes.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#if CONFIG_APP_CLAW_CAP_IM_WECHAT
#include "cap_im_wechat.h"
#endif
#include "app_config.h"
#include "screen_switcher.h"
#include "cap_scheduler.h"
#include "cap_lua.h"

#define APP_ENABLE_MEM_LOG        (1)

static const char *TAG = "app";

static app_config_t *s_config;
static app_claw_config_t *s_claw_config;

static esp_err_t app_allocate_runtime_state(void)
{
    if (!s_config) {
        s_config = calloc(1, sizeof(*s_config));
    }
    if (!s_claw_config) {
        s_claw_config = calloc(1, sizeof(*s_claw_config));
    }

    ESP_RETURN_ON_FALSE(s_config && s_claw_config, ESP_ERR_NO_MEM, TAG,
                        "Failed to allocate runtime state");

    return ESP_OK;
}

static void app_free_runtime_state(void)
{
    free(s_claw_config);
    s_claw_config = NULL;

    free(s_config);
    s_config = NULL;
}

/* Ethernet state: the ESP32-P4 has no on-chip radio, so WiFi is replaced by
 * the RMII EMAC + generic 802.3 PHY on the function EV board. */
static esp_netif_t *s_eth_netif;
static EventGroupHandle_t s_eth_event_group;
static bool s_eth_link_up;
static char s_eth_ip_str[16];

#define ETH_GOT_IP_BIT BIT0

static void eth_event_handler(void *arg, esp_event_base_t event_base,
                              int32_t event_id, void *event_data)
{
    (void)arg;
    (void)event_base;
    (void)event_data;

    switch (event_id) {
    case ETHERNET_EVENT_CONNECTED:
        s_eth_link_up = true;
        ESP_LOGI(TAG, "Ethernet link up");
        break;
    case ETHERNET_EVENT_DISCONNECTED:
        s_eth_link_up = false;
        s_eth_ip_str[0] = '\0';
        ESP_LOGW(TAG, "Ethernet link down");
        app_claw_set_network_status(false, NULL);
        break;
    case ETHERNET_EVENT_START:
        ESP_LOGI(TAG, "Ethernet started");
        break;
    case ETHERNET_EVENT_STOP:
        ESP_LOGW(TAG, "Ethernet stopped");
        break;
    default:
        break;
    }
}

static void eth_got_ip_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data)
{
    (void)arg;
    (void)event_base;
    (void)event_id;

    ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
    esp_ip4addr_ntoa(&event->ip_info.ip, s_eth_ip_str, sizeof(s_eth_ip_str));
    ESP_LOGI(TAG, "Ethernet got IP: %s", s_eth_ip_str);
    app_claw_set_network_status(true, NULL);
    xEventGroupSetBits(s_eth_event_group, ETH_GOT_IP_BIT);
}

static esp_err_t eth_init(void)
{
    /* wifi_manager_init() used to provide netif/event-loop init; with WiFi
     * removed, Ethernet takes over that responsibility. */
    ESP_RETURN_ON_ERROR(esp_netif_init(), TAG, "esp_netif_init failed");
    ESP_RETURN_ON_ERROR(esp_event_loop_create_default(), TAG,
                        "esp_event_loop_create_default failed");

    s_eth_event_group = xEventGroupCreate();
    ESP_RETURN_ON_FALSE(s_eth_event_group, ESP_ERR_NO_MEM, TAG, "eth event group create failed");

    esp_netif_config_t netif_cfg = ESP_NETIF_DEFAULT_ETH();
    s_eth_netif = esp_netif_new(&netif_cfg);
    ESP_RETURN_ON_FALSE(s_eth_netif, ESP_FAIL, TAG, "esp_netif_new failed");

    eth_mac_config_t mac_config = ETH_MAC_DEFAULT_CONFIG();
    eth_phy_config_t phy_config = ETH_PHY_DEFAULT_CONFIG();
    eth_esp32_emac_config_t emac_config = ETH_ESP32_EMAC_DEFAULT_CONFIG();

    esp_eth_mac_t *mac = esp_eth_mac_new_esp32(&emac_config, &mac_config);
    ESP_RETURN_ON_FALSE(mac, ESP_FAIL, TAG, "Ethernet MAC create failed");

    esp_eth_phy_t *phy = esp_eth_phy_new_generic(&phy_config);
    if (!phy) {
        ESP_LOGE(TAG, "Ethernet PHY create failed");
        mac->del(mac);
        return ESP_FAIL;
    }

    esp_eth_handle_t eth_handle = NULL;
    esp_eth_config_t eth_config = ETH_DEFAULT_CONFIG(mac, phy);
    ESP_ERROR_CHECK(esp_eth_driver_install(&eth_config, &eth_handle));

    ESP_ERROR_CHECK(esp_netif_attach(s_eth_netif, esp_eth_new_netif_glue(eth_handle)));

    ESP_ERROR_CHECK(esp_event_handler_register(ETH_EVENT, ESP_EVENT_ANY_ID,
                                               &eth_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_ETH_GOT_IP,
                                               &eth_got_ip_handler, NULL));

    ESP_ERROR_CHECK(esp_eth_start(eth_handle));
    ESP_LOGI(TAG, "Ethernet started, waiting for DHCP IP ...");

    EventBits_t bits = xEventGroupWaitBits(s_eth_event_group, ETH_GOT_IP_BIT,
                                           pdFALSE, pdFALSE, pdMS_TO_TICKS(10000));
    if (bits & ETH_GOT_IP_BIT) {
        ESP_LOGI(TAG, "Ethernet ready (DHCP): %s", s_eth_ip_str);
        return ESP_OK;
    }

    ESP_LOGW(TAG, "DHCP timeout, falling back to static IP 192.168.1.10");
    esp_netif_dhcpc_stop(s_eth_netif);
    esp_netif_ip_info_t ip_info;
    ip_info.ip.addr = inet_addr("192.168.1.10");
    ip_info.netmask.addr = inet_addr("255.255.255.0");
    ip_info.gw.addr = inet_addr("192.168.1.1");
    ESP_ERROR_CHECK(esp_netif_set_ip_info(s_eth_netif, &ip_info));

    /* 静态回退路径没有 DHCP 下发 DNS，必须显式设置，否则 SNTP(pool.ntp.org)
     * 和 LLM HTTPS(api.deepseek.com) 都解析不了域名。 */
    esp_netif_dns_info_t dns_info = {0};
    dns_info.ip.type = IPADDR_TYPE_V4;
    dns_info.ip.u_addr.ip4.addr = inet_addr("223.5.5.5");      /* AliDNS，国内快 */
    ESP_ERROR_CHECK(esp_netif_set_dns_info(s_eth_netif, ESP_NETIF_DNS_MAIN, &dns_info));
    dns_info.ip.u_addr.ip4.addr = inet_addr("114.114.114.114"); /* 114DNS，备份 */
    ESP_ERROR_CHECK(esp_netif_set_dns_info(s_eth_netif, ESP_NETIF_DNS_BACKUP, &dns_info));

    strlcpy(s_eth_ip_str, "192.168.1.10", sizeof(s_eth_ip_str));
    s_eth_link_up = true;
    app_claw_set_network_status(true, NULL);
    ESP_LOGI(TAG, "Ethernet ready (static): %s", s_eth_ip_str);
    return ESP_OK;
}

static esp_err_t main_load_config(app_config_t *config)
{
    return app_config_load(config);
}

static esp_err_t main_save_config(const app_config_t *config)
{
    esp_err_t err;
    app_claw_config_t *claw_config = NULL;

    ESP_RETURN_ON_FALSE(config, ESP_ERR_INVALID_ARG, TAG, "config is NULL");
    ESP_RETURN_ON_ERROR(app_config_validate_wifi(config, NULL), TAG, "Invalid Wi-Fi config");

    err = app_config_save(config);
    if (err != ESP_OK) {
        return err;
    }

    claw_config = calloc(1, sizeof(*claw_config));
    if (!claw_config) {
        ESP_LOGW(TAG, "Failed to allocate Claw config for runtime update");
        return ESP_OK;
    }
    app_config_to_claw(config, claw_config);
    err = app_claw_update_config(claw_config);
    free(claw_config);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "Failed to update running Claw config: %s", esp_err_to_name(err));
    }
    return ESP_OK;
}

static void main_copy_claw_to_app_config(const app_claw_config_t *src, app_config_t *dst)
{
    strlcpy(dst->llm_api_key, src->llm_api_key, sizeof(dst->llm_api_key));
    strlcpy(dst->llm_backend_type, src->llm_backend_type, sizeof(dst->llm_backend_type));
    strlcpy(dst->llm_model, src->llm_model, sizeof(dst->llm_model));
    strlcpy(dst->llm_base_url, src->llm_base_url, sizeof(dst->llm_base_url));
    strlcpy(dst->llm_auth_type, src->llm_auth_type, sizeof(dst->llm_auth_type));
    strlcpy(dst->llm_timeout_ms, src->llm_timeout_ms, sizeof(dst->llm_timeout_ms));
    strlcpy(dst->llm_max_tokens, src->llm_max_tokens, sizeof(dst->llm_max_tokens));
    strlcpy(dst->llm_default_image_max_bytes,
            src->llm_default_image_max_bytes,
            sizeof(dst->llm_default_image_max_bytes));
    strlcpy(dst->llm_max_tokens_field, src->llm_max_tokens_field, sizeof(dst->llm_max_tokens_field));
    strlcpy(dst->llm_supports_tools, src->llm_supports_tools, sizeof(dst->llm_supports_tools));
    strlcpy(dst->llm_supports_vision, src->llm_supports_vision, sizeof(dst->llm_supports_vision));
    strlcpy(dst->llm_image_remote_url_only,
            src->llm_image_remote_url_only,
            sizeof(dst->llm_image_remote_url_only));
}

static esp_err_t main_save_claw_config(const app_claw_config_t *config, void *user_ctx)
{
    esp_err_t err;
    app_config_t *app_config = NULL;

    (void)user_ctx;
    ESP_RETURN_ON_FALSE(config, ESP_ERR_INVALID_ARG, TAG, "config is NULL");

    app_config = calloc(1, sizeof(*app_config));
    ESP_RETURN_ON_FALSE(app_config, ESP_ERR_NO_MEM, TAG, "Failed to allocate app config for Claw save");

    err = app_config_load(app_config);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to load config for Claw save: %s", esp_err_to_name(err));
        free(app_config);
        return err;
    }
    main_copy_claw_to_app_config(config, app_config);
    err = app_config_save(app_config);
    free(app_config);
    return err;
}

static esp_err_t main_get_wifi_status(http_server_wifi_status_t *status)
{
    ESP_RETURN_ON_FALSE(status, ESP_ERR_INVALID_ARG, TAG, "status is NULL");

    status->wifi_connected = s_eth_link_up && s_eth_ip_str[0] != '\0';
    status->ip = s_eth_ip_str[0] ? s_eth_ip_str : NULL;
    status->ap_active = false;
    status->ap_ssid = NULL;
    status->ap_ip = NULL;
    status->wifi_mode = "ethernet";
    return ESP_OK;
}

static void main_restart_task(void *arg)
{
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
}

static esp_err_t main_restart_device(void)
{
    BaseType_t ok = xTaskCreate(main_restart_task, "http_restart", 2048, NULL, 5, NULL);
    ESP_RETURN_ON_FALSE(ok == pdPASS, ESP_ERR_NO_MEM, TAG, "Failed to create restart task");
    return ESP_OK;
}

#if CONFIG_APP_CLAW_CAP_IM_WECHAT
static esp_err_t main_wechat_login_start(const char *account_id, bool force)
{
    return cap_im_wechat_qr_login_start(account_id, force);
}

static esp_err_t main_wechat_login_get_status(http_server_wechat_login_status_t *status)
{
    esp_err_t ret = ESP_OK;
    cap_im_wechat_qr_login_status_t *raw = NULL;

    ESP_RETURN_ON_FALSE(status, ESP_ERR_INVALID_ARG, TAG, "status is NULL");

    raw = calloc(1, sizeof(*raw));
    ESP_RETURN_ON_FALSE(raw, ESP_ERR_NO_MEM, TAG, "Failed to allocate login status");

    ESP_GOTO_ON_ERROR(cap_im_wechat_qr_login_get_status(raw), cleanup, TAG,
                      "Failed to query WeChat login status");

    memset(status, 0, sizeof(*status));
    status->active = raw->active;
    status->configured = raw->configured;
    status->completed = raw->completed;
    status->persisted = raw->persisted;
    strlcpy(status->session_key, raw->session_key, sizeof(status->session_key));
    strlcpy(status->status, raw->status, sizeof(status->status));
    strlcpy(status->message, raw->message, sizeof(status->message));
    strlcpy(status->qr_data_url, raw->qr_data_url, sizeof(status->qr_data_url));
    strlcpy(status->account_id, raw->account_id, sizeof(status->account_id));
    strlcpy(status->user_id, raw->user_id, sizeof(status->user_id));
    strlcpy(status->token, raw->token, sizeof(status->token));
    strlcpy(status->base_url, raw->base_url, sizeof(status->base_url));

cleanup:
    free(raw);
    return ret;
}

static esp_err_t main_wechat_login_cancel(void)
{
    return cap_im_wechat_qr_login_cancel();
}

static esp_err_t main_wechat_login_mark_persisted(void)
{
    return cap_im_wechat_qr_login_mark_persisted();
}
#endif

static esp_err_t init_nvs(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    return err;
}

static esp_err_t init_timezone(const char *timezone)
{
    esp_err_t ret = ESP_OK;

    ESP_GOTO_ON_FALSE(timezone && timezone[0] != '\0', ESP_ERR_INVALID_ARG, tz_default, TAG,
                      "Timezone is empty.");
    ESP_GOTO_ON_FALSE(setenv("TZ", timezone, 1) == 0, ESP_FAIL, tz_default, TAG,
                      "Failed to set TZ env");
    tzset();
    ESP_LOGI(TAG, "Timezone set to %s", timezone);
    return ESP_OK;

tz_default:
    assert(setenv("TZ", "CST-8", 1) == 0);
    tzset();
    ESP_LOGI(TAG, "Timezone set to default: CST-8");
    return ret;
}

#if APP_ENABLE_MEM_LOG

static void print_task_stack_info(void)
{
#ifdef CONFIG_FREERTOS_GENERATE_RUN_TIME_STATS
    static TaskStatus_t s_task_status_snapshot[24];
    UBaseType_t count = uxTaskGetSystemState(s_task_status_snapshot,
                                             sizeof(s_task_status_snapshot) / sizeof(s_task_status_snapshot[0]),
                                             NULL);

    for (UBaseType_t i = 0; i < count; i++) {
        ESP_LOGI(TAG,
                 "Task %s  %u",
                 s_task_status_snapshot[i].pcTaskName,
                 s_task_status_snapshot[i].usStackHighWaterMark);
    }
#endif
}

/* Periodic task: print internal free, minimum free, and PSRAM free every 20s */
static void memory_monitor_task(void *arg)
{
    (void)arg;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        size_t internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
        size_t internal_min = heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL);
        size_t psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
        ESP_LOGI(TAG, "Memory: internal_free=%u bytes, internal_min_free=%u bytes, psram_free=%u bytes",
                 (unsigned)internal_free, (unsigned)internal_min, (unsigned)psram_free);
        print_task_stack_info();
    }
}

#endif

/* 开机填充「待办」屏缓存：show_schedule.lua 自包含（读本地 JSON + 画屏 +
 * save_schedule_cache，不依赖 LLM/网络），直接同步跑一遍即可让第 3 页在首次
 * 按键切换时就显示真实日程，而非回退静态占位。技能烘焙在只读 system 分区
 * （/system/skills/…），故走绝对路径。放独立任务里：epaper 由 screen_switcher
 * 与 Lua 侧共享互斥锁，启动阶段给它留出稳定时间，避免抢锁/未初始化竞态。 */
#define SCHEDULE_CACHE_SCRIPT "/system/skills/schedule_manager/scripts/show_schedule.lua"
#define SCHEDULE_CACHE_BOOT_DELAY_MS 500
#define SCHEDULE_CACHE_BOOT_TIMEOUT_MS 15000

static void schedule_cache_boot_task(void *arg)
{
    vTaskDelay(pdMS_TO_TICKS(SCHEDULE_CACHE_BOOT_DELAY_MS));

    char output[512];
    output[0] = '\0';
    esp_err_t err = cap_lua_run_script(SCHEDULE_CACHE_SCRIPT, "{}",
                                       SCHEDULE_CACHE_BOOT_TIMEOUT_MS,
                                       output, sizeof(output));
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "开机填充待办缓存失败 (%s): %s",
                 esp_err_to_name(err), output[0] ? output : "(no output)");
    } else {
        ESP_LOGI(TAG, "开机填充待办缓存完成: %s", output[0] ? output : "(no output)");
    }

    vTaskDelete(NULL);
}

/* 每小时自动重渲染待办屏缓存并刷新显示：show_schedule.lua 自包含（读本地 JSON
 * + 画屏 + save_schedule_cache），直接同步跑即可，不依赖 LLM/网络。跑完后若当前
 * 正显示待办屏，则 screen_switcher_refresh_schedule() 重读缓存刷屏，让过期/未开始
 * 的颜色状态随时间自动更新。 */
static void schedule_cache_refresh_task(void *arg)
{
    const TickType_t one_hour = pdMS_TO_TICKS(60 * 60 * 1000);
    for (;;) {
        vTaskDelay(one_hour);

        char output[512];
        output[0] = '\0';
        esp_err_t err = cap_lua_run_script(SCHEDULE_CACHE_SCRIPT, "{}",
                                           SCHEDULE_CACHE_BOOT_TIMEOUT_MS,
                                           output, sizeof(output));
        if (err != ESP_OK) {
            ESP_LOGW(TAG, "每小时刷新待办缓存失败 (%s): %s",
                     esp_err_to_name(err), output[0] ? output : "(no output)");
        } else {
            ESP_LOGI(TAG, "每小时刷新待办缓存完成: %s", output[0] ? output : "(no output)");
            screen_switcher_refresh_schedule();
        }
    }
}

/* 天气屏刷新调度器条目 id（文件作用域，供延迟触发任务引用）。 */
#define WEATHER_SCHED_ID "weather_hourly"

/* 开机延迟触发天气屏刷新：天气刷新走 LLM 唤醒链（scheduler → web_search → LLM →
 * show_weather.lua），依赖网络与 NTP。开机立即触发时 NTP 异步同步几乎肯定未完成，
 * show_weather.lua 的 os.date("*t") 会拿到无效时间 → 画进缓存的日期是错的（显示
 * 昨天/1970）。这里轮询 time(NULL) 越过最小有效 epoch（与 cap_system 同阈值）后再
 * 触发，确保首帧日期正确；60s 仍未同步则 best-effort 触发，由下一小时刷新兜底。 */
#define WEATHER_CACHE_MIN_EPOCH      1704067200  /* 2024-01-01 UTC */
#define WEATHER_CACHE_BOOT_POLL_MS   3000
#define WEATHER_CACHE_BOOT_TIMEOUT_MS 60000

static void weather_cache_boot_task(void *arg)
{
    bool synced = false;
    for (int waited = 0; waited < WEATHER_CACHE_BOOT_TIMEOUT_MS;
         waited += WEATHER_CACHE_BOOT_POLL_MS) {
        if (time(NULL) >= WEATHER_CACHE_MIN_EPOCH) {
            synced = true;
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(WEATHER_CACHE_BOOT_POLL_MS));
    }

    if (synced) {
        ESP_LOGI(TAG, "开机触发天气屏：NTP 已同步，触发首次刷新");
    } else {
        ESP_LOGW(TAG, "开机触发天气屏：等待 NTP 同步 %dms 超时，best-effort 触发",
                 WEATHER_CACHE_BOOT_TIMEOUT_MS);
    }

    esp_err_t trig_err = cap_scheduler_trigger_now(WEATHER_SCHED_ID);
    if (trig_err != ESP_OK) {
        ESP_LOGW(TAG, "天气屏首次触发失败: %s", esp_err_to_name(trig_err));
    }

    vTaskDelete(NULL);
}

void app_main(void)
{
    esp_log_level_set("esp-x509-crt-bundle", ESP_LOG_WARN);
    esp_log_level_set("http_reuse", ESP_LOG_WARN);

    ESP_LOGI(TAG, "Starting app");
    ESP_LOGI(TAG, "ESP-Claw version: %s", claw_get_version());
    ESP_LOGI(TAG, "ESP-Claw git version: %s", claw_get_git_version());
    ESP_LOGI(TAG, "Edge Agent version: %s", edge_agent_get_version());
    ESP_ERROR_CHECK(app_allocate_runtime_state());
    ESP_ERROR_CHECK(init_nvs());
    ESP_ERROR_CHECK(app_config_init());
    ESP_ERROR_CHECK(app_config_load(s_config));
    app_config_to_claw(s_config, s_claw_config);
    init_timezone(app_config_get_timezone(s_config)); // no need to check error
    ESP_ERROR_CHECK(esp_board_manager_init());
    ESP_ERROR_CHECK(app_fs_init());

    /* Publish the resolved storage roots so any component can compose paths
     * without knowing whether data lives on flash or an SD card. */
    ESP_ERROR_CHECK(claw_paths_set(CLAW_PATH_DATA, app_fs_storage_base_path()));
    ESP_ERROR_CHECK(claw_paths_set(CLAW_PATH_SYSTEM, app_fs_system_base_path()));

    ESP_ERROR_CHECK(eth_init());

    ESP_ERROR_CHECK(app_claw_ui_start());

    ESP_ERROR_CHECK(http_server_init(&(http_server_config_t) {
        .storage_base_path = app_fs_storage_base_path(),
        .services = {
            .load_config = main_load_config,
            .save_config = main_save_config,
            .get_wifi_status = main_get_wifi_status,
            .restart_device = main_restart_device,
#if CONFIG_APP_CLAW_CAP_IM_WECHAT
            .wechat_login_start = main_wechat_login_start,
            .wechat_login_get_status = main_wechat_login_get_status,
            .wechat_login_cancel = main_wechat_login_cancel,
            .wechat_login_mark_persisted = main_wechat_login_mark_persisted,
#endif
        },
    }));
    ESP_ERROR_CHECK(http_server_start());

    ESP_ERROR_CHECK(app_claw_set_save_config_callback(main_save_claw_config, NULL));
    ESP_ERROR_CHECK(app_claw_start(s_claw_config));
#if CONFIG_APP_CLAW_CAP_IM_LOCAL
    ESP_ERROR_CHECK(http_server_webim_bind_im());
#endif

    /* BOOT 键循环切屏：开机显示工卡屏，按键在 工卡→天气日历→待办 间循环。
     * 放在 app_claw_start() 之后：epaper 组件已就绪，内部自初始化 EPD 硬件。 */
    screen_switcher_start(0);

    /* 开机异步填充「待办」屏缓存（show_schedule.lua），让第 3 页首次切换即显真实日程。 */
    xTaskCreate(schedule_cache_boot_task, "sched_cache", 6144, NULL, 5, NULL);

    /* 每小时自动刷新待办内容与待办屏显示（重渲染缓存 + 若在待办屏则刷屏）。 */
    xTaskCreate(schedule_cache_refresh_task, "sched_refresh", 6144, NULL, 5, NULL);

    /* 天气屏定时刷新：每小时唤起 agent，web_search 真实天气后调 show_weather.lua
     * 画屏存缓存(不刷当前屏)。注册后立即 trigger_now 触发首次生成，尽快填缓存。
     * 路由规则 im_any_message_agent 已匹配 event_type=message/content_type=text。 */
    {
        const char *city = app_config_get_weather_city(s_config);
        if (city == NULL || city[0] == '\0') {
            city = "Beijing";
        }
        cap_scheduler_item_t item = {};
        item.kind = CAP_SCHEDULER_ITEM_INTERVAL;
        item.enabled = true;
        item.interval_ms = 60 * 60 * 1000;  /* 每小时 */
        strncpy(item.id, WEATHER_SCHED_ID, sizeof(item.id) - 1);
        strncpy(item.event_type, "message", sizeof(item.event_type) - 1);
        strncpy(item.content_type, "text", sizeof(item.content_type) - 1);
        strncpy(item.source_channel, "system", sizeof(item.source_channel) - 1);
        snprintf(item.text, sizeof(item.text),
                 "定时刷新天气屏：web_search 搜「%s 今天天气」解析后，必须运行 show_weather.lua "
                 "画屏存缓存（不运行=任务失败）；拿不到数据才回复天气暂不可用，勿编造。",
                 city);
        esp_err_t sched_err = cap_scheduler_add(&item);
        if (sched_err == ESP_ERR_INVALID_STATE) {
            /* 重启后 schedules.json 已持久化 weather_hourly，add 返回 INVALID_STATE；
             * 回退 update 整体覆盖 item，让新配置的 weather_city 刷新进 text。 */
            sched_err = cap_scheduler_update(&item);
        }
        if (sched_err != ESP_OK) {
            ESP_LOGW(TAG, "注册天气屏定时刷新失败: %s", esp_err_to_name(sched_err));
        } else {
            /* 首次刷新延迟到 NTP 同步后触发（见 weather_cache_boot_task），
             * 避免把无效时间画进天气屏缓存。 */
            xTaskCreate(weather_cache_boot_task, "weather_cache", 6144, NULL, 5, NULL);
        }
    }

#if APP_ENABLE_MEM_LOG
    /* Start memory monitor: print internal free, min free, PSRAM free every 20s */
    xTaskCreate(memory_monitor_task, "mem_mon", 4096, NULL, 1, NULL);
#endif

    app_free_runtime_state();
}
