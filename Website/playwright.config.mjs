import { defineConfig } from '@playwright/test';
import { base } from './site.mjs';

const previewURL = `http://127.0.0.1:4321${base}/`;

export default defineConfig({
  testDir: './test',
  use: { baseURL: previewURL, screenshot: 'only-on-failure' },
  projects: [
    { name: 'desktop', use: { browserName: 'chromium', viewport: { width: 1440, height: 1000 } } },
    { name: 'mobile', use: { browserName: 'chromium', viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true } },
  ],
  webServer: {
    // Keep the server in the foreground so Playwright owns its lifecycle.
    command: 'npm run preview -- --host 127.0.0.1 --port 4321 --ignore-lock',
    url: previewURL,
    reuseExistingServer: !process.env.CI,
  },
});
