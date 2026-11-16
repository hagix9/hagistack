import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// Planned production URL (GitHub Pages custom domain). Nothing is published
// until the Owner approves DNS, GitHub Pages and the push.
const site = 'https://hagistack.fulltrust.co.jp';

const t = (en, ja) => ({ label: en, translations: { ja } });

export default defineConfig({
  site,
  base: '/',
  // Japanese is the primary audience: the bare domain opens the Japanese site.
  redirects: { '/': '/ja/' },
  integrations: [
    starlight({
      title: 'HAGISTACK',
      description:
        'HAGISTACK installs OpenStack 2026.1 on Rocky Linux 10.2 from prebuilt RPMs: all-in-one or controller + compute.',
      defaultLocale: 'en',
      locales: {
        ja: { label: '日本語', lang: 'ja' },
        en: { label: 'English', lang: 'en' },
      },
      logo: { src: './src/assets/logo.svg', replacesTitle: false },
      favicon: '/favicon.svg',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/hagix9/hagistack' },
      ],
      editLink: undefined,
      lastUpdated: false,
      customCss: ['./src/styles/custom.css'],
      sidebar: [
        {
          ...t('Getting started', 'はじめに'),
          items: [
            { slug: 'quickstart/prepare' },
            { slug: 'quickstart/install' },
            { slug: 'quickstart/first-vm' },
          ],
        },
        {
          ...t('Guides', 'ガイド'),
          items: [
            { slug: 'guides/horizon' },
            { slug: 'guides/add-compute' },
          ],
        },
        {
          ...t('OpenStack CLI', 'OpenStack CLI'),
          items: [
            { slug: 'cli/overview' },
            { slug: 'cli/keystone' },
            { slug: 'cli/glance' },
            { slug: 'cli/nova' },
            { slug: 'cli/neutron' },
            { slug: 'cli/placement' },
          ],
        },
        {
          ...t('Architecture and operations', '構成・運用'),
          items: [
            { slug: 'operations/architecture' },
            { slug: 'operations/status' },
            { slug: 'operations/troubleshooting' },
            { slug: 'operations/limitations' },
          ],
        },
        {
          ...t('Release', 'リリース'),
          items: [{ slug: 'download' }, { slug: 'faq' }],
        },
        {
          ...t('In development', '開発中の機能'),
          items: [{ slug: 'development/novnc' }],
        },
      ],
    }),
  ],
});
