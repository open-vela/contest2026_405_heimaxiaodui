#ifndef _SCREEN_SWITCHER_H_
#define _SCREEN_SWITCHER_H_

#ifdef __cplusplus
extern "C" {
#endif

/*
 * 按键循环切屏：BOOT 键(GPIO14) 按一次切下一屏
 * 循环顺序：工卡 → 天气日历 → 待办 → 工卡
 */
void screen_switcher_start(int start_index);

/*
 * 定时刷新待办屏：仅当当前正显示待办屏(index 2)时重读 schedule 缓存并刷屏，
 * 否则不动（不打扰工卡/天气屏、省电、避免不必要全刷）。由 main.c 每小时
 * 刷新任务在重渲染 schedule 缓存后调用。
 */
void screen_switcher_refresh_schedule(void);

#ifdef __cplusplus
}
#endif

#endif
