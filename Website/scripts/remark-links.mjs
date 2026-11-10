import { existsSync, statSync } from 'node:fs';
import { dirname, join, posix, relative } from 'node:path';
import { sources, root } from './content.mjs';
import { base, repository } from '../site.mjs';

const routes = new Map(sources.map(page => [page.source, `${base}/${page.route ? page.route + '/' : ''}`]));
routes.set('docs/local-mlx-architecture.html', `${base}/explore/`);

export default function repositoryLinks() {
  return (tree, file) => {
    const generated = relative(join(root, 'Website/src/content/docs'), file.path).replace(/\.(md|mdx)$/, '');
    const source = sources.find(page => (page.route || 'index') === generated)?.source;
    if (!source) return;
    function visit(node) {
      if (['link', 'image', 'definition'].includes(node.type) && node.url
          && !/^(?:[a-z][a-z0-9+.-]*:|#|\/)/i.test(node.url)) {
        const [pathname, suffix = ''] = node.url.split(/(?=[?#])/s, 2);
        const target = posix.normalize(posix.join(dirname(source), decodeURIComponent(pathname)));
        if (routes.has(target)) node.url = routes.get(target) + suffix;
        else {
          if (target.startsWith('../') || !existsSync(join(root, target))) {
            throw new Error(`Broken repository link in ${source}: ${node.url}`);
          }
          const kind = statSync(join(root, target)).isDirectory() ? 'tree' : 'blob';
          node.url = `${repository}/${kind}/main/${target}${suffix}`;
        }
      }
      node.children?.forEach(visit);
    }
    visit(tree);
  };
}
