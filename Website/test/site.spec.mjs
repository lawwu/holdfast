import { expect, test } from '@playwright/test';
import { base } from '../site.mjs';

test('read the docs and navigate without horizontal overflow', async ({ page }, info) => {
  const failures = [];
  page.on('pageerror', error => failures.push(error.message));
  await page.goto('./');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Keep your knowledge close.');
  await page.screenshot({ path: `test-results/${info.project.name}-home.png`, fullPage: true });
  await page.getByRole('link', { name: 'Get started', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Getting started');
  for (const path of ['guide/', 'packages/local-mlx/', 'development/releases/', 'architecture/']) {
    await page.goto(path);
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBeTruthy();
  }
  await page.goto('explore/');
  await page.getByRole('link', { name: '← Holdfast documentation' }).click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('How Holdfast fits together');
  expect(failures).toEqual([]);
});

test('search finds the approval documentation', async ({ page }) => {
  await page.goto('./');
  await page.getByRole('button', { name: /Search/ }).click();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('textbox', { name: 'Search', exact: true }).fill('Undo');
  const result = dialog.locator('.pagefind-ui__result-link').first();
  await expect(result).toBeVisible();
  await result.click();
  await expect(page).toHaveURL(url => url.pathname.startsWith(base + '/') && url.pathname !== base + '/');
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible();
});

test('theme selection remains readable', async ({ page }, info) => {
  await page.goto('getting-started/');
  const menu = page.getByRole('button', { name: 'Menu', exact: true });
  if (await menu.isVisible()) await menu.click();
  await page.getByRole('combobox', { name: 'Select theme' }).selectOption('dark');
  if (await menu.isVisible()) await menu.click();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await page.screenshot({ path: `test-results/${info.project.name}-dark.png`, fullPage: true });
});

test('tour loads its video, captions, chapters, and screenshots', async ({ page }, info) => {
  await page.goto('tour/');
  const video = page.locator('video');
  await expect(video).toBeVisible();
  await expect(video).toHaveAttribute('controls', '');
  await expect(video).not.toHaveAttribute('autoplay', '');
  await expect(page.locator('track[kind="captions"]')).toHaveAttribute('src', base + '/demo/holdfast-tour.vtt');
  await expect.poll(() => video.evaluate(v => v.readyState)).toBeGreaterThanOrEqual(1);
  const duration = await video.evaluate(v => v.duration);
  expect(duration).toBeGreaterThan(140);
  expect(duration).toBeLessThan(160);
  await page.getByRole('button', { name: /REQUEST A CHANGE|You have the final say/i }).click();
  await expect.poll(() => video.evaluate(v => v.currentTime)).toBeGreaterThan(80);
  await video.evaluate(v => v.pause());
  await expect.poll(() => video.evaluate(v => v.textTracks[0]?.cues?.length ?? 0)).toBeGreaterThan(30);
  for (const image of await page.locator('main img').all()) {
    await image.scrollIntoViewIfNeeded();
    await expect.poll(() => image.evaluate(i => i.complete && i.naturalWidth > 0)).toBeTruthy();
    await expect(image).toHaveAttribute('alt', /.+/);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBeTruthy();
  await page.screenshot({ path: `test-results/${info.project.name}-tour.png`, fullPage: true });
  const download = await page.request.get(base + '/demo/holdfast-sample-notes.zip');
  expect(download.ok()).toBeTruthy();
  expect((await download.body()).subarray(0, 2).toString()).toBe('PK');
});
