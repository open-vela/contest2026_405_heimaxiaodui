/* 自动生成：tools/gen_ui_screens.py，勿手改 */
#ifndef _UI_SCREENS_H_
#define _UI_SCREENS_H_

#ifdef __cplusplus
extern "C" {
#endif

#define UI_SCREEN_COUNT 3
#define UI_SCREEN_BYTES 17664

extern const unsigned char ui_screen_badge[UI_SCREEN_BYTES];
extern const unsigned char ui_screen_weather[UI_SCREEN_BYTES];
extern const unsigned char ui_screen_todo[UI_SCREEN_BYTES];

/* 按键循环顺序：0=工卡 1=天气日历 2=待办 */
extern const unsigned char *const ui_screens[UI_SCREEN_COUNT];
extern const char *const ui_screen_names[UI_SCREEN_COUNT];

#ifdef __cplusplus
}
#endif

#endif
