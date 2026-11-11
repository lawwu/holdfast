import { readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const root = fileURLToPath(new URL('../../', import.meta.url));
export const sources = [
  { source: 'Website/content/index.mdx', route: '', authored: true },
  { source: 'Website/content/tour.mdx', route: 'tour', authored: true },
  { source: 'Website/content/getting-started.md', route: 'getting-started', authored: true },
  { source: 'Website/content/architecture.md', route: 'architecture', authored: true },
  { source: 'docs/guide.md', route: 'guide', title: 'App and command-line guide', description: 'Search, Ask, imports, model providers, privacy, and approved edits in Holdfast.' },
  { source: 'Packages/ModelProviders/README.md', route: 'packages/model-providers', title: 'ModelProviders', description: 'Shared inference types and HTTP providers for Swift apps.' },
  { source: 'Packages/LocalMLX/README.md', route: 'packages/local-mlx', title: 'LocalMLX', description: 'Embed MLX inference in a Swift app or run local-mlx-host.' },
  { source: 'Packages/pi-swift-mlx/README.md', route: 'packages/pi-swift-mlx', title: 'pi-swift-mlx', description: 'Connect a Swift MLX engine to Pi or Pi Durable.' },
  { source: 'Runtime/pi/README.md', route: 'development/pi', title: 'Holdfast’s Pi bridge', description: 'How Pi uses Holdfast’s tools, conversations, privacy rules, and Inbox.' },
  { source: 'docs/releases.md', route: 'development/releases', title: 'Builds and releases', description: 'Build, test, and publish the macOS installer.' },
  { source: 'packs/README.md', route: 'reference-collections', title: 'Reference collections', description: 'Add reference material alongside your notes.' },
  { source: 'CHANGELOG.md', route: 'changelog', title: 'Changelog', description: 'Changes to the Holdfast app and its reusable packages.' },
  ...readdirSync(new URL('../../docs/releases/', import.meta.url)).filter(name => /^v\d+\.\d+\.\d+\.md$/.test(name)).map(name => ({
    source: 'docs/releases/' + name, route: 'releases/' + name.slice(0, -3),
    title: 'Holdfast ' + name.slice(0, -3), description: 'Installation notes and limitations for Holdfast ' + name.slice(0, -3) + '.',
  })),
];
