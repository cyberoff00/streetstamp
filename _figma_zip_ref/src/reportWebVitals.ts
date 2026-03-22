import { onCLS, onINP, onLCP, onTTFB, type Metric } from "web-vitals";

function sendToAnalytics(metric: Metric) {
  const body = JSON.stringify(metric);
  if (navigator.sendBeacon) {
    navigator.sendBeacon("/vitals", body);
  } else {
    fetch("/vitals", { method: "POST", body, keepalive: true }).catch(() => {});
  }
  if (import.meta.env.DEV) {
    console.debug("[web-vitals]", metric.name, metric.value, metric.rating);
  }
}

export function reportWebVitals() {
  onCLS(sendToAnalytics);
  onINP(sendToAnalytics);
  onLCP(sendToAnalytics);
  onTTFB(sendToAnalytics);
}
