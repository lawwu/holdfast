import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { unified } from '@astrojs/markdown-remark';
import repositoryLinks from './scripts/remark-links.mjs';
import { base, origin } from './site.mjs';

export default defineConfig({
  site: origin,
  base,
  trailingSlash: 'always',
  integrations: [starlight({
    title: 'Holdfast',
    description: 'A local-first knowledge base for macOS. Search your notes, ask questions with sources, and approve changes in your Inbox.',
    logo: { src: './src/assets/mark.svg', replacesTitle: false },
    favicon: '/favicon.svg',
    customCss: ['./src/styles/custom.css'],
    credits: false,
    sidebar: [
      { label: 'Welcome', slug: '' },
      { label: 'Using Holdfast', items: [
        { label: 'Getting started', slug: 'getting-started' },
        { label: 'App and CLI guide', slug: 'guide' },
        { label: 'Reference collections', slug: 'reference-collections' },
      ] },
      { label: 'How it works', items: [
        { label: 'Architecture', slug: 'architecture' },
        { label: 'ModelProviders', slug: 'packages/model-providers' },
        { label: 'LocalMLX', slug: 'packages/local-mlx' },
        { label: 'pi-swift-mlx', slug: 'packages/pi-swift-mlx' },
      ] },
      { label: 'Development', items: [
        { label: 'Pi bridge', slug: 'development/pi' },
        { label: 'Builds and releases', slug: 'development/releases' },
        { label: 'Changelog', slug: 'changelog' },
      ] },
      { label: 'Release notes', items: [{ autogenerate: { directory: 'releases' } }] },
    ],
  })],
  markdown: { processor: unified({ remarkPlugins: [repositoryLinks] }) },
});
