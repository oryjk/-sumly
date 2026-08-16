<script setup lang="ts">
import { onHide, onLaunch, onPageNotFound, onShow } from "@dcloudio/uni-app";
import { ensureSessionReady } from "@/stores/appSession";

const HOME_PAGE_PATH = "/pages/home/index";

onLaunch(() => {
  console.log("sumly_mini launch");
  ensureSessionReady().catch((error) => {
    console.warn("session bootstrap failed", error);
  });
});

onShow(() => {
  console.log("sumly_mini show");
});

onHide(() => {
  console.log("sumly_mini hide");
});

onPageNotFound((options) => {
  console.warn("page not found, relaunch home", options);
  uni.reLaunch({
    url: HOME_PAGE_PATH,
  });
});
</script>

<style>
/* 全局样式与设计令牌统一收敛在 uni.css */
@import "./uni.css";
</style>
