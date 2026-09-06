import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import { bunny } from 'laravel-vite-plugin/fonts';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
    plugins: [
        laravel({
            input: ['resources/css/app.css', 'resources/js/app.js'],
            refresh: true,
            fonts: [
                bunny('Instrument Sans', {
                    weights: [400, 500, 600],
                }),
            ],
        }),
        tailwindcss(),
    ],
    server: {
        // Bind to all interfaces inside the container (Docker needs it)...
        host: '0.0.0.0',
        port: 5173,
        // ...but advertise a browser-friendly URL. Without this the dev server
        // writes public/hot as http://0.0.0.0:5173, which browsers block, so
        // no CSS/JS would load. Change this if you access the app from another
        // machine (e.g. `hmr: { host: 'my.hostname' }`).
        hmr: { host: 'localhost' },
        watch: {
            ignored: ['**/storage/framework/views/**'],
        },
    },
});